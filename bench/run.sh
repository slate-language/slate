#!/bin/sh
# Run every benchmark with the binary named as the first argument, three times each, and print the
# best of the three -- the best rather than the mean, because a slow run is always something else on
# the machine and never the program being faster than it is.
set -e

slate=${1:?usage: bench/run.sh <path-to-slate>}
dir=$(dirname "$0")

for b in arith calls strings globals; do
    best=""

    for _ in 1 2 3; do
        ms=$("$slate" "$dir/$b.sl" | tail -1)

        if [ -z "$best" ] || [ "$ms" -lt "$best" ]; then best=$ms; fi
    done

    echo "$b $best ms"
done
