#!/usr/bin/env bash
#
# Run one command and say what it actually cost in memory.
#
# **`Maximum resident set size` does not answer "how much did it need", and on this build that is
# the whole question.** A page that has been swapped out is not resident, so a process whose heap
# has grown past RAM reports an RSS of about RAM however far past it went -- which reads as a
# comfortable fit and is a machine on its knees. So two numbers are printed: GNU time's per-process
# figures, which say what one process held in RAM and how much of it it had to fault back in, and
# the machine's own memory-plus-swap high-water mark, sampled while the command runs, which is the
# number that says whether the ceiling was anywhere near right.
#
# The command is also given a deadline. `sysl` prints a stack trace when its collector cannot grow
# the heap and then does not exit -- so without one, a build that has already failed holds the runner
# for as long as the job is allowed to live.

set -uo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: linux-measure.sh <label> <command> [args...]" >&2
  exit 2
fi

label=$1
shift

limit=${SLATE_STEP_TIMEOUT:-60m}

used_kb() {
  awk '/^MemTotal:/     {t=$2}
       /^MemAvailable:/ {a=$2}
       /^SwapTotal:/    {st=$2}
       /^SwapFree:/     {sf=$2}
       END              {print (t-a)+(st-sf)}' /proc/meminfo
}

baseline=$(used_kb)
peak_file=$(mktemp)
echo "$baseline" > "$peak_file"

(
  peak=$baseline
  while :; do
    now=$(used_kb)
    if [ "$now" -gt "$peak" ]; then
      peak=$now
      echo "$peak" > "$peak_file"
    fi
    sleep 5
  done
) &
sampler=$!
trap 'kill "$sampler" 2>/dev/null' EXIT

report=$(mktemp)
/usr/bin/time -v -o "$report" timeout "$limit" "$@"
state=$?

kill "$sampler" 2>/dev/null
wait "$sampler" 2>/dev/null

peak=$(cat "$peak_file")

echo "--- what '$label' cost ---"
grep -E 'Maximum resident set size|Elapsed \(wall clock\) time|Major \(requiring I/O\) page faults|Swaps' "$report" \
  || cat "$report"
awk -v p="$peak" -v b="$baseline" 'BEGIN {
        printf "\tPeak memory and swap in use, whole machine (GB): %.1f\n", p / 1048576
        printf "\tPeak above the idle baseline (GB):               %.1f\n", (p - b) / 1048576
     }'
free -g

if [ "$state" -eq 124 ]; then
  echo "'$label' was still running after $limit and was killed" >&2
fi

exit "$state"
