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
  echo 0 > "$tmp/peakrss"; echo 0 > "$tmp/peakfd"
  (
    while kill -0 "$SPID" 2>/dev/null; do
      r=$(rss_kb); f=$(fds)
      [ -n "$r" ] && [ "$r" -gt "$(cat "$tmp/peakrss")" ] && echo "$r" > "$tmp/peakrss"
      [ -n "$f" ] && [ "$f" -gt "$(cat "$tmp/peakfd")" ] && echo "$f" > "$tmp/peakfd"
      sleep 0.3
    done
  ) &
  SAMPLER=$!
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
  rss2=$(rss_kb); fd2=$(fds)
  peakr=$(cat "$tmp/peakrss"); peakf=$(cat "$tmp/peakfd")
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
