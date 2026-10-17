#!/bin/sh
# The server benchmark: the same three-endpoint HTTP server in slate (interpreted, and compiled by
# `slate js` to run under node), node, Bun and Go, loaded by
# existing generators (oha, wrk, h2load) and reported as one markdown results table.
#
#     bench/serve/run.sh [-d secs] [-c conns] [-w warmup-secs] [-q rate] [-o file] [--only name]
#                        [--check] <path-to-slate>
#
#   -d  seconds each load run lasts                       (default 8)
#   -c  connections each load run holds open              (default 64)
#   -w  warm-up seconds per server, spread over endpoints (default 3)
#   -n  repeat every oha load N times and report median and min-max (default 1, which keeps the
#       original tables with wrk, h2load and the fixed-rate run; above 1 only the oha table is made)
#   -q  requests per second for the fixed-rate latency run (default 5000)
#   -o  also write the tables to this file
#   --only  one of slate, slatejs (slate's `slate js` output under node), node, bun, go (repeatable)
#   --check start each server, verify its answers, and stop: the quick smoke, no load is applied
#
# **Run it under `caffeinate -dimsu` on a quiet box**, as `bench/run.sh` is run -- the sleep that
# hits an unprotected run lands in whatever load run is under way and reads as a latency tail.
#
# **A SERVER'S ANSWERS ARE CHECKED BEFORE IT IS LOADED, AND A SERVER THAT FAILS THE CHECK IS
# REPORTED AS FAILED AND NEVER MEASURED.** A load generator is perfectly happy to time a server that
# answers 404 to everything, and the number it prints is a very good one. The check is also what
# proves a TLS server negotiated h2 rather than falling back to HTTP/1.1.
#
# wrk2 is not in Homebrew, so fixed-rate latency comes from `oha -q` with `--latency-correction`,
# which measures from each request's scheduled start rather than from when it was sent -- the same
# correction wrk2 makes for coordinated omission. `wrk` supplies throughput and p50/p99 only; p99.9
# comes from `oha`.

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
DUR=8
CONNS=64
N=1
WARM=3
RATE=5000
OUT=""
ONLY=""
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    -d) DUR=$2; shift 2 ;;
    -c) CONNS=$2; shift 2 ;;
    -w) WARM=$2; shift 2 ;;
    -n) N=$2; shift 2 ;;
    -q) RATE=$2; shift 2 ;;
    -o) OUT=$2; shift 2 ;;
    --only) ONLY="$ONLY $2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    *) break ;;
  esac
done

SLATE=${1:-}
if [ -z "$SLATE" ]; then
  echo "usage: bench/serve/run.sh [options] <path-to-slate>" >&2
  exit 2
fi
case "$SLATE" in /*) ;; *) SLATE="$PWD/$SLATE" ;; esac

tmp=$(mktemp -d)
cert="$root/tests/tls/cert.pem"
key="$root/tests/tls/key.pem"
SPID=""
SAMPLER=""
trap 'stop_server 2>/dev/null; rm -rf "$tmp"' EXIT INT TERM

selected() {
  [ -z "$ONLY" ] && return 0
  case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# start_server <name> <port> <tls 0|1>: sets SPID, starts the max-RSS sampler.
start_server() {
  name=$1; port=$2; tls=$3
  log="$tmp/$name.log"
  : > "$log"
  extra=""
  [ "$tls" = 1 ] && extra="$cert $key"
  case "$name" in
    slate) "$SLATE" "$here/server.sl" "$port" $extra > "$log" 2>&1 & ;;
    slatejs) node "$tmp/server-slatejs.js" "$port" $extra > "$log" 2>&1 & ;;
    node) node "$here/server.js" "$port" $extra > "$log" 2>&1 & ;;
    bun) bun "$here/server.bun.js" "$port" $extra > "$log" 2>&1 & ;;
    go) "$tmp/server-go" "$port" $extra > "$log" 2>&1 & ;;
  esac
  SPID=$!
  tries=0
  until grep -q listening "$log"; do
    tries=$((tries + 1))
    if [ $tries -gt 150 ] || ! kill -0 "$SPID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  echo 0 > "$tmp/rss"
  (
    peak=0
    while kill -0 "$SPID" 2>/dev/null; do
      now=$(ps -o rss= -p "$SPID" 2>/dev/null | tr -d ' ')
      [ -n "$now" ] && [ "$now" -gt "$peak" ] && peak=$now && echo "$peak" > "$tmp/rss"
      sleep 0.25
    done
  ) &
  SAMPLER=$!
  return 0
}

stop_server() {
  [ -n "$SAMPLER" ] && kill "$SAMPLER" 2>/dev/null
  [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
  [ -n "$SPID" ] && wait "$SPID" 2>/dev/null
  SPID=""
  SAMPLER=""
}

peak_mb() {
  awk '{ printf "%.0f", $1 / 1024 }' "$tmp/rss"
}

# check_server <base-url> <curl options...>: the answers every server owes.
check_server() {
  base=$1; shift
  [ "$(curl -s "$@" "$base/plain")" = "hello" ] || { echo "/plain did not answer hello"; return 1; }
  curl -s "$@" "$base/json" | jq -e '.ok == true and .items == [1, 2, 3] and (.seq | type) == "number"' > /dev/null \
    || { echo "/json did not answer the expected object"; return 1; }
  [ "$(curl -s "$@" -d 'ping body' "$base/echo")" = "ping body" ] || { echo "/echo did not return the body"; return 1; }
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$@" "$base/nope")" = "404" ] || { echo "/nope was not a 404"; return 1; }
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$@" "$base/echo")" = "405" ] || { echo "GET /echo was not a 405"; return 1; }
  return 0
}

# oha_row <oha args...>: "rps | p50 | p99 | p99.9", latencies in ms; a trailing ! marks a run
# in which some request did not succeed.
oha_row() {
  oha -z "${DUR}s" -c "$CONNS" --no-tui --output-format json "$@" 2> /dev/null | jq -r '
    def ms: (. * 1000 * 1000 | round) / 1000;
    "\(.summary.requestsPerSec | floor)\(if .summary.successRate < 0.999 then "!" else "" end) | \(.latencyPercentiles.p50 | ms) | \(.latencyPercentiles.p99 | ms) | \(.latencyPercentiles["p99.9"] | ms)"'
}

# wrk_row <url>: "rps | p50 | p99", latencies in ms.
wrk_row() {
  wrk -t2 -c "$CONNS" -d "${DUR}s" --latency "$1" 2> /dev/null | awk '
    function ms(v,   n, u) { n = v + 0; u = v; sub(/^[0-9.]+/, "", u); if (u == "us") return n / 1000; if (u == "s") return n * 1000; return n }
    /^ +50%/ { p50 = ms($2) }
    /^ +99%/ { p99 = ms($2) }
    /^Requests\/sec/ { rps = $2 }
    END { printf "%d | %.3f | %.3f", rps, p50, p99 }'
}

# h2load_row <url>: requests per second, flagged when any request failed.
h2load_row() {
  h2load -c "$CONNS" -m 10 -t 2 -D "${DUR}s" "$1" 2> /dev/null | awk '
    /^finished in/ { rps = $4; sub(/,/, "", rps); for (i = 1; i <= NF; i++) if ($i == "req/s,") rps = $(i - 1) }
    /^requests:/ { for (i = 1; i <= NF; i++) if ($i == "failed,") failed = $(i - 1) }
    END { printf "%d%s", rps, (failed + 0 > 0 ? "!" : "") }'
}

warm() { # warm <url-base> <extra oha args>
  base=$1; shift
  each=$((WARM / 3))
  [ $each -lt 1 ] && each=1
  for p in /plain /json; do
    oha -z "${each}s" -c "$CONNS" --no-tui --output-format json "$@" "$base$p" > /dev/null 2>&1
  done
  oha -z "${each}s" -c "$CONNS" --no-tui --output-format json -m POST -d 'warm' "$@" "$base/echo" > /dev/null 2>&1
}

if selected go; then
  (cd "$here" && go build -o "$tmp/server-go" server.go) || { echo "go build failed" >&2; exit 1; }
fi

# The same server.sl, compiled once to JavaScript and run under node.
if selected slatejs; then
  "$SLATE" js "$here/server.sl" -o "$tmp/server-slatejs.js" || { echo "slate js failed" >&2; exit 1; }
fi

: > "$tmp/t1"; : > "$tmp/t2"; : > "$tmp/t3"; : > "$tmp/t4"; : > "$tmp/raw"; : > "$tmp/gatewaits"

# sample <key> <load function> <args...>: N runs of one load, each appended to the raw table as
# "key | rps | p50 | p99 | p99.9".
sample() {
  skey=$1; shift
  i=0
  while [ $i -lt $N ]; do
    i=$((i + 1))
    # A `sysl test` gate on the box skews every figure: wait it out before each repeat, and
    # count the waits so the report can say whether every repeat ran with no gate running.
    while ps -eo command | grep -q '[s]ysl test'; do
      echo "gate running; waiting before $skey repeat $i" >&2
      echo x >> "$tmp/gatewaits"
      sleep 30
    done
    echo "$skey | $("$@")" >> "$tmp/raw"
  done
}
status=0
base_port=18100
idx=0

for name in slate slatejs node bun go; do
  selected "$name" || continue
  idx=$((idx + 1))
  port=$((base_port + idx * 10))
  tport=$((port + 1))

  if ! start_server "$name" "$port" 0; then
    echo "$name: failed to start (plain)" >&2; cat "$tmp/$name.log" >&2; status=1
    echo "| $name | failed to start | | | |" >> "$tmp/t1"
    stop_server; continue
  fi
  url="http://127.0.0.1:$port"
  if ! reason=$(check_server "$url"); then
    echo "$name: FAILED CHECK (plain): $reason" >&2; status=1
    echo "| $name | FAILED CHECK: $reason | | | |" >> "$tmp/t1"
    stop_server; continue
  fi
  if [ $CHECK = 0 ] && [ $N -gt 1 ]; then
    echo "== $name: plain HTTP/1.1, $N repeats ==" >&2
    warm "$url"
    sample "$name h1 /plain" oha_row "$url/plain"
    sample "$name h1 /json" oha_row "$url/json"
    sample "$name h1 /echo" oha_row -m POST -d 'ping body' "$url/echo"
  elif [ $CHECK = 0 ]; then
    echo "== $name: plain HTTP/1.1 ==" >&2
    warm "$url"
    echo "| $name | /plain | $(oha_row "$url/plain") | $(wrk_row "$url/plain") |" >> "$tmp/t1"
    echo "| $name | /json | $(oha_row "$url/json") | $(wrk_row "$url/json") |" >> "$tmp/t1"
    echo "| $name | /echo (POST) | $(oha_row -m POST -d 'ping body' "$url/echo") | - | - | - |" >> "$tmp/t1"
    echo "| $name | /plain | $RATE | $(oha_row -q "$RATE" --latency-correction "$url/plain") |" >> "$tmp/t2"
    echo "| $name | /json | $RATE | $(oha_row -q "$RATE" --latency-correction "$url/json") |" >> "$tmp/t2"
  fi
  h1rss=$(peak_mb)
  stop_server

  if ! start_server "$name" "$tport" 1; then
    echo "$name: failed to start (TLS)" >&2; cat "$tmp/$name.log" >&2; status=1
    echo "| $name | failed to start | | | |" >> "$tmp/t3"
    stop_server; continue
  fi
  turl="https://127.0.0.1:$tport"
  if ! reason=$(check_server "$turl" -k --http2); then
    echo "$name: FAILED CHECK (TLS): $reason" >&2; status=1
    echo "| $name | FAILED CHECK: $reason | | | |" >> "$tmp/t3"
    stop_server; continue
  fi
  ver=$(curl -sk --http2 -o /dev/null -w '%{http_version}' "$turl/plain")
  if [ "$ver" != "2" ]; then
    echo "$name: TLS server negotiated HTTP/$ver, not h2" >&2
    # Bun.serve speaks no HTTP/2 (measured with Bun 1.4.3): that is a fact about Bun, reported as
    # one rather than as a failure. Any other server that misses h2 is a defect here.
    [ "$name" != bun ] && status=1
    echo "| $name | not measured: negotiated HTTP/$ver, no h2 | | | |" >> "$tmp/t3"
    stop_server
    echo "| $name | $h1rss | - |" >> "$tmp/t4"
    continue
  fi
  if [ $CHECK = 0 ] && [ $N -gt 1 ]; then
    echo "== $name: HTTPS + h2, $N repeats ==" >&2
    warm "$turl" --http2 --insecure
    sample "$name h2 /plain" oha_row --http2 --insecure "$turl/plain"
    sample "$name h2 /json" oha_row --http2 --insecure "$turl/json"
  elif [ $CHECK = 0 ]; then
    echo "== $name: HTTPS + h2 ==" >&2
    warm "$turl" --http2 --insecure
    echo "| $name | /plain | $(oha_row --http2 --insecure "$turl/plain") | $(h2load_row "$turl/plain") |" >> "$tmp/t3"
    echo "| $name | /json | $(oha_row --http2 --insecure "$turl/json") | $(h2load_row "$turl/json") |" >> "$tmp/t3"
  fi
  h2rss=$(peak_mb)
  stop_server
  echo "| $name | $h1rss | $h2rss |" >> "$tmp/t4"
  [ $CHECK = 1 ] && echo "$name: ok (h1 and h2 answers verified)" >&2
done

[ $CHECK = 1 ] && exit $status

report() {
  echo "Machine: $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.ncpu) cores, $(sw_vers -productName) $(sw_vers -productVersion), $(date +%Y-%m-%d)."
  echo
  echo "Settings: ${DUR} s per run, ${CONNS} connections, ${WARM} s warm-up per server, fixed rate ${RATE} req/s. Servers and load generators share this machine, on loopback."
  echo
  echo "Tools: $(oha --version), $(wrk --version 2>&1 | head -1), $(h2load --version), node $(node --version), bun $(bun --version), $(go version | cut -d' ' -f3), slate $("$SLATE" --version 2>&1 | head -1)."
  echo
  echo "### HTTP/1.1, plain, throughput and latency"
  echo
  echo "oha columns are req/s, then p50, p99 and p99.9 in ms; wrk columns are req/s, p50, p99 (wrk has no p99.9). A trailing ! on a figure means some requests failed."
  echo
  echo "| server | endpoint | oha req/s | oha p50 | oha p99 | oha p99.9 | wrk req/s | wrk p50 | wrk p99 |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---:|"
  cat "$tmp/t1"
  echo
  echo "### HTTP/1.1, plain, fixed rate (oha -q, latency-corrected; stands in for wrk2)"
  echo
  echo "| server | endpoint | target req/s | achieved req/s | p50 | p99 | p99.9 |"
  echo "|---|---|---:|---:|---:|---:|---:|"
  cat "$tmp/t2"
  echo
  echo "### HTTPS + h2, throughput"
  echo
  echo "| server | endpoint | oha req/s | oha p50 | oha p99 | oha p99.9 | h2load req/s |"
  echo "|---|---|---:|---:|---:|---:|---:|"
  cat "$tmp/t3"
  echo
  echo "### Peak RSS of the server over its runs (MB)"
  echo
  echo "| server | plain HTTP/1.1 | HTTPS + h2 |"
  echo "|---|---:|---:|"
  cat "$tmp/t4"
}

# report_repeats: with -n above 1, the oha figures as median (min-max) over the repeats. The
# req/s column is the median with the range beside it; latencies are medians. A trailing ! on any
# sample marks the row, since a repeat in which some request failed is not a clean figure.
report_repeats() {
  echo "Machine: $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.ncpu) cores, $(sw_vers -productName) $(sw_vers -productVersion), $(date +%Y-%m-%d)."
  echo
  echo "Settings: ${N} repeats of ${DUR} s each, ${CONNS} connections, ${WARM} s warm-up per server. Servers and load generators share this machine, on loopback."
  echo
  echo "Tools: $(oha --version), node $(node --version), bun $(bun --version), $(go version | cut -d' ' -f3), slate $("$SLATE" --version 2>&1 | head -1)."
  echo
  echo "Gate check: no \`sysl test\` was running at the start of any repeat ($(wc -l < "$tmp/gatewaits" | tr -d ' ') waits for one were needed)."
  echo
  echo "### oha: median (min-max) over ${N} repeats"
  echo
  echo "| server | proto | endpoint | req/s median | req/s min-max | p50 ms | p99 ms | p99.9 ms |"
  echo "|---|---|---|---:|---:|---:|---:|---:|"
  awk -F' [|] ' '
    function med(a, n,   i, j, t) {
      for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] + 0 > t + 0; j--) a[j + 1] = a[j]; a[j + 1] = t }
      return (n % 2) ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
    }
    {
      key = $1; if (!(key in seen)) { seen[key] = 1; order[++k] = key }
      n[key]++
      r = $2; if (r ~ /!$/) { bad[key] = "!"; sub(/!$/, "", r) }
      rps[key, n[key]] = r; p50[key, n[key]] = $3; p99[key, n[key]] = $4; p999[key, n[key]] = $5
    }
    END {
      for (q = 1; q <= k; q++) {
        key = order[q]; c = n[key]
        for (i = 1; i <= c; i++) { a1[i] = rps[key, i]; a2[i] = p50[key, i]; a3[i] = p99[key, i]; a4[i] = p999[key, i] }
        lo = a1[1]; hi = a1[1]
        for (i = 2; i <= c; i++) { if (a1[i] + 0 < lo + 0) lo = a1[i]; if (a1[i] + 0 > hi + 0) hi = a1[i] }
        split(key, f, " ")
        printf "| %s | %s | %s | %d%s | %d-%d | %.3f | %.3f | %.3f |\n", f[1], f[2], f[3], med(a1, c), bad[key], lo, hi, med(a2, c), med(a3, c), med(a4, c)
      }
    }' "$tmp/raw"
  echo
  echo "### Peak RSS of the server over its runs (MB)"
  echo
  echo "| server | plain HTTP/1.1 | HTTPS + h2 |"
  echo "|---|---:|---:|"
  cat "$tmp/t4"
}

if [ $N -gt 1 ]; then
  report_repeats > "$tmp/report"
else
  report > "$tmp/report"
fi
cat "$tmp/report"
[ -n "$OUT" ] && cp "$tmp/report" "$OUT"
exit $status
