#!/bin/zsh
#
# `SLATE_PROFILE` on a program that is still running, proven against the real binary: start a slate
# program that does not end, send it SIGUSR1 twice, and read its stderr for two profile reports while
# the process is still alive.
#
#     scripts/profile-signal-check.sh [path-to-slate]     default ./slate
#
# `tests_profile_dump.sysl` asserts the reset in process, where the report's destination -- stderr --
# cannot be read; this is the half that reads it, and the half that shows the process outliving the
# dump. It is a gate step beside `scripts/embed-check.sh`. The interpreter only: under `slate js`
# there is nothing to dump, node having its own profiler (`node --cpu-prof`).

set -e

root=$(cd "$(dirname "$0")/.." && pwd)
slate=${1:-$root/slate}
work=$(mktemp -d "${TMPDIR:-/tmp}/slate-profsig-XXXXXX")
pid=""

cleanup() {
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT

cat > "$work/loop.sl" <<'EOF'
async main()
    var i = 0

    while i < 2000
        floor(1.5)
        await sleep(10)
        i = i + 1

main()
EOF

reports() {
    grep -c '^slate profile' "$work/err.txt" || true
}

waitfor() {
    local want=$1 tries=0

    while [ "$(reports)" -lt "$want" ]; do
        tries=$((tries + 1))
        if [ $tries -gt 100 ]; then
            echo "profile-signal-check: FAILED, no report number $want after 10 s" >&2
            cat "$work/err.txt" >&2
            exit 1
        fi
        sleep 0.1
    done
}

SLATE_PROFILE=1 "$slate" "$work/loop.sl" > "$work/out.txt" 2> "$work/err.txt" &
pid=$!

sleep 1
kill -USR1 "$pid"
waitfor 1

if ! kill -0 "$pid" 2>/dev/null; then
    echo "profile-signal-check: FAILED, the process ended with its first report" >&2
    exit 1
fi

grep -q 'floor' "$work/err.txt" || { echo "profile-signal-check: FAILED, the report names no builtin" >&2; exit 1; }

kill -USR1 "$pid"
waitfor 2

if ! kill -0 "$pid" 2>/dev/null; then
    echo "profile-signal-check: FAILED, the process ended with its second report" >&2
    exit 1
fi

echo "profile-signal-check: OK"
