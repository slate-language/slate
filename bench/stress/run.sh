#!/bin/sh
# The server stress harness: starts the same three-endpoint server as `bench/serve/` (slate, and
# node/Go for reference), points `stress.sl` at it one mode at a time, and records server RSS and
# open-fd counts before, during and after each mode. The slate tool reports PASS/FAIL from the
# client's side; this harness reports what the server process did.
#
#     bench/stress/run.sh [-o file] [--only name] [--mode m] [-d soak-secs] <path-to-slate>
#
#   -o      also write the results table to this file
#   --only  one of slate, node, go (repeatable); default slate node go
#   --mode  one of slowloris idleflood halfclose malformed h2abuse soak (repeatable); default all
#   -d      soak duration in seconds (default 30)
#
# **Run it under `caffeinate -dimsu` on a quiet box.** The TCP modes hit a plain HTTP/1.1 server;
# h2abuse hits the same server on TLS, where it negotiates h2. ANY FAILURE OF THE SLATE SERVER IS A
# BUG -- the table and this script's exit status both record it.
#
# A quick self-hosted smoke that needs no external server is `slate bench/stress/stress.sl --check`.

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
serve="$root/bench/serve"
OUT=""
ONLY=""
MODES=""
SOAK=30

while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT=$2; shift 2 ;;
    --only) ONLY="$ONLY $2"; shift 2 ;;
    --mode) MODES="$MODES $2"; shift 2 ;;
    -d) SOAK=$2; shift 2 ;;
    *) break ;;
  esac
done

SLATE=${1:-}
if [ -z "$SLATE" ]; then
  echo "usage: bench/stress/run.sh [options] <path-to-slate>" >&2
  exit 2
fi
case "$SLATE" in /*) ;; *) SLATE="$PWD/$SLATE" ;; esac

[ -z "$ONLY" ] && ONLY="slate node go"
[ -z "$MODES" ] && MODES="slowloris idleflood halfclose malformed h2abuse soak"

# A client that opens thousands of sockets needs the room, and so may the server.
ulimit -n 8192 2>/dev/null || true

tmp=$(mktemp -d)
cert="$root/tests/tls/cert.pem"
key="$root/tests/tls/key.pem"
SPID=""
state=0
trap 'stop_server 2>/dev/null; rm -rf "$tmp"' EXIT INT TERM

selected() {
  case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
chosen() {
  case " $MODES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# start_server <name> <port> <tls 0|1>: sets SPID; waits for the "listening" line.
start_server() {
  name=$1; port=$2; tls=$3
  log="$tmp/$name.log"
  : > "$log"
  extra=""
  [ "$tls" = 1 ] && extra="$cert $key"
  case "$name" in
    slate) "$SLATE" "$serve/server.sl" "$port" $extra > "$log" 2>&1 & ;;
    node)  node "$serve/server.js" "$port" $extra > "$log" 2>&1 & ;;
    go)    "$tmp/server-go" "$port" $extra > "$log" 2>&1 & ;;
  esac
  SPID=$!
  tries=0
  until grep -q listening "$log"; do
    tries=$((tries + 1))
    if [ $tries -gt 150 ] || ! kill -0 "$SPID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 0
}

stop_server() {
  [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
  [ -n "$SPID" ] && wait "$SPID" 2>/dev/null
  SPID=""
}

# rss_kb / fds: the server process's resident set (KB) and open file descriptors right now.
rss_kb() { ps -o rss= -p "$SPID" 2>/dev/null | tr -d ' '; }
fds()    { lsof -p "$SPID" 2>/dev/null | wc -l | tr -d ' '; }

# sample a server's peak RSS and peak fds into files while a command runs in the foreground.
sample_start() {
  : > "$tmp/samples"
  (
    while kill -0 "$SPID" 2>/dev/null; do
      r=$(rss_kb); f=$(fds)
      [ -n "$r" ] && [ -n "$f" ] && echo "$r $f" >> "$tmp/samples"
      sleep 0.5
    done
  ) &
  SAMPLER=$!
}

# max <a> <b>: the larger of two whole numbers.
max() { [ "$1" -gt "$2" ] && echo "$1" || echo "$2"; }

# slope: compares the mean RSS of the first and last quarter of the samples. "plateau" unless the
# last quarter is more than 10% and 2 MB above the first, or fds climbed by more than 8.
slope() {
  awk '{ r[NR] = $1; f[NR] = $2 } END {
    q = int(NR / 4); if (q < 1) { print "too-few-samples"; exit }
    for (i = 1; i <= q; i++) { a += r[i]; fa += f[i] }
    for (i = NR - q + 1; i <= NR; i++) { b += r[i]; fb += f[i] }
    a /= q; b /= q; fa /= q; fb /= q
    if (b > a * 1.10 && b - a > 2048) print "CLIMBING rss " int(a / 1024) "->" int(b / 1024) " MB"
    else if (fb - fa > 8) print "CLIMBING fds " int(fa) "->" int(fb)
    else print "plateau rss " int(a / 1024) "->" int(b / 1024) " MB, fds " int(fa) "->" int(fb)
  }' "$tmp/samples"
}
sample_stop() { [ -n "${SAMPLER:-}" ] && kill "$SAMPLER" 2>/dev/null; SAMPLER=""; }

mb() { awk -v k="$1" 'BEGIN { printf "%.0f", k / 1024 }'; }

# one mode against one already-started server; appends a results row.
run_one() {
  name=$1; mode=$2; host=$3; port=$4; tlsarg=$5
  rss0=$(rss_kb); fd0=$(fds)
  sample_start
  line=$("$SLATE" "$here/stress.sl" "$mode" "$host" "$port" $tlsarg 2>>"$tmp/stress.err")
  sample_stop
  if [ "$mode" = soak ]; then
    shape=$(slope)
    case "$shape" in CLIMBING*) line="$line [server $shape]"; line=$(echo "$line" | sed 's/: PASS/: FAIL/') ;; *) line="$line [server $shape]" ;; esac
  fi
  # Settle past every server's idle clock before reading "after", so a socket the server is still
  # closing is not counted as a leak -- what remains after this IS one.
  sleep "${STRESS_SETTLE:-7}"
  rss2=$(rss_kb); fd2=$(fds)
  peakr=$(awk 'BEGIN { m = 0 } { if ($1 > m) m = $1 } END { print m }' "$tmp/samples")
  peakf=$(awk 'BEGIN { m = 0 } { if ($2 > m) m = $2 } END { print m }' "$tmp/samples")
  peakr=$(max "$(max "$peakr" "$rss0")" "$rss2"); peakf=$(max "$(max "$peakf" "$fd0")" "$fd2")
  if [ "$fd2" -gt $((fd0 + 8)) ]; then
    line="$line [server fds $fd0 -> $fd2 after settling: LEAK]"; line=$(echo "$line" | sed 's/: PASS/: FAIL/')
  fi
  verdict=$(echo "$line" | sed -n 's/^[a-z0-9]*: \([A-Z]*\).*/\1/p')
  [ "$name" = slate ] && [ "$verdict" = FAIL ] && state=1
  echo "| $name | $mode | ${verdict:-?} | $(mb "$rss0") | $(mb "$peakr") | $(mb "$rss2") | $fd0 | $peakf | $fd2 |" >> "$tmp/t1"
  echo "| $name | $mode | $(echo "$line" | sed 's/^[a-z0-9]*: [A-Z]* -- //') |" >> "$tmp/t2"
  echo "== $name $mode: $line" >&2
}

if selected go; then
  ( cd "$serve" && go build -o "$tmp/server-go" server.go ) 2>/dev/null || echo "go build failed; skipping go" >&2
fi

export STRESS_SOAK_SECS="$SOAK"
export STRESS_CA="$cert"

for name in slate node go; do
  selected "$name" || continue
  [ "$name" = go ] && [ ! -x "$tmp/server-go" ] && continue

  # the TCP modes on a plain HTTP/1.1 server
  if chosen slowloris || chosen idleflood || chosen halfclose || chosen malformed || chosen soak; then
    if start_server "$name" 0 0; then
      port=$(sed -n 's/^listening //p' "$tmp/$name.log" | head -1)
      for m in slowloris idleflood halfclose malformed soak; do
        chosen "$m" && run_one "$name" "$m" 127.0.0.1 "$port" ""
      done
      stop_server
    else
      echo "$name: failed to start (plain)" >&2; cat "$tmp/$name.log" >&2; state=1
    fi
  fi

  # h2abuse on a TLS server (localhost, to match the certificate's name)
  if chosen h2abuse; then
    if start_server "$name" 0 1; then
      tport=$(sed -n 's/^listening //p' "$tmp/$name.log" | head -1)
      run_one "$name" h2abuse localhost "$tport" tls
      stop_server
    else
      echo "$name: failed to start (TLS)" >&2; cat "$tmp/$name.log" >&2; state=1
    fi
  fi
done

report() {
  echo "# Server stress: correctness under abuse"
  echo
  echo "Taken with \`bench/stress/run.sh ./slate\` under \`caffeinate -dimsu\`. The slate client surface"
  echo "(\`slate:net\`, TLS, \`slate:nghttp2\`, native \`fetch\`) is pointed at each server to try to make it"
  echo "misbehave. PASS/FAIL is the client's verdict; RSS and fd columns are the server process's."
  echo
  echo "Machine: $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.ncpu) cores, $(sw_vers -productName) $(sw_vers -productVersion), $(date +%Y-%m-%d)."
  echo
  echo "## Verdict, and server RSS (MB) / open fds, before / peak / after"
  echo
  echo "| server | mode | verdict | rss before | rss peak | rss after | fd before | fd peak | fd after |"
  echo "|---|---|---|---:|---:|---:|---:|---:|---:|"
  cat "$tmp/t1" 2>/dev/null
  echo
  echo "## What each mode saw"
  echo
  echo "| server | mode | detail |"
  echo "|---|---|---|"
  cat "$tmp/t2" 2>/dev/null
}

report > "$tmp/report"
cat "$tmp/report"
[ -n "$OUT" ] && cp "$tmp/report" "$OUT"
exit $state
