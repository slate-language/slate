#!/bin/sh
# What each benchmark computes, which is what says a faster run is still a correct one.
set -e

slate=${1:?usage: bench/check.sh <path-to-slate>}
dir=$(dirname "$0")

for b in arith calls strings loops options closures nested globals; do
    "$slate" "$dir/$b.sl" | head -1
done | diff - "$dir/expected.txt" && echo "answers unchanged"
