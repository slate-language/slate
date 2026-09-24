#!/bin/sh
# What each benchmark computes, which is what says a faster run is still a correct one -- and, since
# every benchmark has its twins, that all the programs are doing the same work.
#
#     bench/check.sh <path-to-slate>
#
# **Every implementation is checked against ONE written-down file.** A twin that drifted from its
# slate program -- a loop bound edited on one side, a 1-based index off by one, an integer that
# stopped being exact in a double -- shows up here as a differing line rather than as a benchmark
# that quietly measures something else. `expected.txt` is what the slate programs answer.
#
# The rows are the runtimes `run.sh` times, each run the way `run.sh` runs it: `luajit` takes a
# program's `.luajit.lua` where it has one, and `RUBY`, `PHP` and `LUAJIT` name the binaries as
# they do there. The JIT columns run the same files as their interpreters and are not checked twice.
set -e

slate=${1:?usage: bench/check.sh <path-to-slate>}
dir=$(dirname "$0")
ruby=${RUBY:-/opt/homebrew/opt/ruby/bin/ruby}
php=${PHP:-php}
luajit=${LUAJIT:-luajit}

names="arith reals globals funcs fib calls methods closures nested loops options
       fields alloc arrays mapset dispatch strings strindex strwalk sorting csv branches"

failed=0

for runtime in slate lua node python3 ruby php luajit; do
    answers=$(mktemp)

    for name in $names; do
        case $runtime in
            slate) "$slate" "$dir/$name.sl" >> "$answers" ;;
            lua) lua "$dir/$name.lua" >> "$answers" ;;
            node) node --jitless "$dir/$name.js" >> "$answers" ;;
            python3) python3 "$dir/$name.py" >> "$answers" ;;
            ruby) "$ruby" --disable=yjit,zjit "$dir/$name.rb" >> "$answers" ;;
            php) "$php" -d opcache.jit=0 -d opcache.jit_buffer_size=0 "$dir/$name.php" >> "$answers" ;;
            luajit)
                twin="$dir/$name.lua"
                if [ -f "$dir/$name.luajit.lua" ]; then twin="$dir/$name.luajit.lua"; fi
                "$luajit" -joff "$twin" >> "$answers"
                ;;
        esac
    done

    if diff -u "$dir/expected.txt" "$answers" > /dev/null; then
        echo "$runtime: answers unchanged"
    else
        echo "$runtime: ANSWERS DIFFER"
        diff -u "$dir/expected.txt" "$answers" || true
        failed=1
    fi

    rm -f "$answers"
done

exit "$failed"
