#!/bin/sh
# Run every benchmark under slate and under its three twins, and report the best wall time of each.
#
#     bench/run.sh [-n <repeats>] [--tsv] <path-to-slate> [name...]
#
# **The BEST of N runs rather than the mean**, because a slow run is always something else on the
# machine and never the program being faster than it is. N is 5; `-n` changes it.
#
# **Process wall time, start to finish, with nothing subtracted** -- fork, exec, start-up, the work,
# and the exit. That is what a person waits for, and it is the only figure four different runtimes
# can be compared on without one of them being asked to report its own clock. `startup` is the same
# measurement of a program that does nothing, so a reader can see how much of a short run was never
# the program; it is reported and never subtracted.
#
# **The four yardsticks are `lua`, `node --jitless`, `python3` and `qjs`.** Lua is the goal. `node
# --jitless` runs V8's Ignition bytecode interpreter with no Sparkplug, Maglev or TurboFan behind it,
# which is the nearest thing to slate's own design that is not a toy. CPython is a stack machine with
# a much larger object model, which is the other direction. **`qjs` (QuickJS-ng) is a JIT-less
# bytecode interpreter for a dynamically typed JS-family language** -- the same design category as
# slate, closer than CPython, Lua or `node --jitless`, none of which interpret JavaScript's own
# object model without a tiering JIT sitting on top somewhere.
#
# **`node` WITH its compilers is reported too and is NOT a yardstick.** It is here because slate's
# own JavaScript back end runs under exactly that, so the column says what `slate js` is aiming at --
# and nothing an interpreter does gets close to a tiering JIT, which is the whole reason it is kept
# out of the geometric means.
set -e

dir=$(dirname "$0")
reps=5
tsv=0

while [ $# -gt 0 ]; do
    case $1 in
        -n)
            reps=$2
            shift 2
            ;;
        --tsv)
            tsv=1
            shift
            ;;
        -*)
            echo "usage: bench/run.sh [-n <repeats>] [--tsv] <path-to-slate> [name...]" >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

slate=${1:?usage: bench/run.sh [-n <repeats>] [--tsv] <path-to-slate> [name...]}
shift

names=$*

if [ -z "$names" ]; then
    names="arith reals globals funcs fib calls methods closures nested loops options
           fields alloc arrays mapset dispatch strings strindex strwalk sorting csv branches"
fi

out=$(mktemp)
rows=$(mktemp)

trap 'rm -f "$out" "$rows"' EXIT

# The best of `reps` runs of one command, in milliseconds, or an empty answer where the command is
# not installed.
best() {
    if ! command -v "$1" > /dev/null 2>&1 && [ ! -x "$1" ]; then
        echo ""
        return
    fi

    answer=""
    turn=0

    while [ "$turn" -lt "$reps" ]; do
        took=$(perl "$dir/timeit.pl" "$out" "$@")
        answer=$(awk -v a="$answer" -v n="$took" 'BEGIN { print (a == "" || n + 0 < a + 0) ? n : a }')
        turn=$((turn + 1))
    done

    echo "$answer"
}

for name in startup $names; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" \
        "$(best "$slate" "$dir/$name.sl")" \
        "$(best lua "$dir/$name.lua")" \
        "$(best node --jitless "$dir/$name.js")" \
        "$(best python3 "$dir/$name.py")" \
        "$(best qjs "$dir/$name.js")" \
        "$(best node "$dir/$name.js")" >> "$rows"
done

if [ "$tsv" = 1 ]; then
    printf 'benchmark\tslate_ms\tlua_ms\tnode_jitless_ms\tpython_ms\tqjs_ms\tnode_jit_ms\tvs_lua\tvs_node_jitless\tvs_python\tvs_qjs\n'
fi

awk -v tsv="$tsv" -F '\t' '
    function ratio(a, b) { return (b + 0 > 0) ? a / b : 0 }

    BEGIN {
        if (tsv == 0) {
            printf "%-10s %8s %8s %8s %8s %8s %8s   %7s %7s %7s %7s\n",
                "", "slate", "lua", "node-jl", "python", "qjs", "node+jit", "/lua", "/node", "/py", "/qjs"
        }
    }

    {
        name = $1; s = $2 + 0; l = $3 + 0; n = $4 + 0; p = $5 + 0; q = $6 + 0; j = $7 + 0
        rl = ratio(s, l); rn = ratio(s, n); rp = ratio(s, p); rq = ratio(s, q)

        if (name != "startup" && rl > 0) {
            suml += log(rl); sumn += log(rn); sump += log(rp); sumq += log(rq); count++
        }

        if (tsv == 1) {
            printf "%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.2f\t%.2f\t%.2f\t%.2f\n", name, s, l, n, p, q, j, rl, rn, rp, rq
        } else {
            printf "%-10s %8.1f %8.1f %8.1f %8.1f %8.1f %8.1f   %6.1fx %6.1fx %6.1fx %6.1fx\n", name, s, l, n, p, q, j, rl, rn, rp, rq
        }
    }

    END {
        if (count == 0) exit

        gl = exp(suml / count); gn = exp(sumn / count); gp = exp(sump / count); gq = exp(sumq / count)

        if (tsv == 1) {
            printf "geomean\t\t\t\t\t\t\t%.2f\t%.2f\t%.2f\t%.2f\n", gl, gn, gp, gq
        } else {
            printf "%-10s %8s %8s %8s %8s %8s %8s   %6.1fx %6.1fx %6.1fx %6.1fx\n", "geomean", "", "", "", "", "", "", gl, gn, gp, gq
        }
    }
' "$rows"
