#!/bin/sh
# Run every benchmark under slate and under its twins, and report the best wall time of each.
#
#     bench/run.sh [-n <repeats>] [--tsv] <path-to-slate> [name...]
#
# **The BEST of N runs rather than the mean**, because a slow run is always something else on the
# machine and never the program being faster than it is. N is 5; `-n` changes it.
#
# **Process wall time, start to finish, with nothing subtracted** -- fork, exec, start-up, the work,
# and the exit. That is what a person waits for, and it is the only figure eight different runtimes
# can be compared on without one of them being asked to report its own clock. `startup` is the same
# measurement of a program that does nothing, so a reader can see how much of a short run was never
# the program; it is reported and never subtracted.
#
# **The seven yardsticks are `lua`, `node --jitless`, `python3`, `qjs`, `ruby`, `php` and
# `luajit -joff`, every one an interpreter with no compiler behind it.** Lua is the goal. `node
# --jitless` runs V8's Ignition bytecode interpreter with no Sparkplug, Maglev or TurboFan behind it,
# which is the nearest thing to slate's own design that is not a toy. CPython is a stack machine with
# a much larger object model, which is the other direction. **`qjs` (QuickJS-ng) is a JIT-less
# bytecode interpreter for a dynamically typed JS-family language** -- the same design category as
# slate, closer than CPython, Lua or `node --jitless`, none of which interpret JavaScript's own
# object model without a tiering JIT sitting on top somewhere.
#
# **`ruby` is CRuby with YJIT and ZJIT off** (`--disable=yjit,zjit`, which is also the default):
# Ruby is the mainstream language closest to slate in shape -- dynamically typed, garbage collected,
# everything an object, blocks and closures everywhere -- and it ships its JIT opt-in, so the
# interpreter is what most Ruby runs on. **`php` is PHP with its JIT off** (`-d opcache.jit=0 -d
# opcache.jit_buffer_size=0`, which is also the default): the fastest mainstream hand-tuned C
# interpreter, and it too ships with its JIT off. **`luajit -joff` is LuaJIT's interpreter**, a
# hand-written assembly register machine running Lua -- the ceiling for any interpreter rather than a
# peer, on the page to say how far the design space goes. It runs the Lua twins unchanged except
# where a `<name>.luajit.lua` exists, which it prefers (LuaJIT is Lua 5.1 and lacks what that one
# program uses); its numbers are all doubles, which every answer here fits in.
#
# **`node`, `ruby --yjit` and `luajit` WITH their compilers are reported too and are NOT
# yardsticks.** `node` is here because slate's own JavaScript back end runs under exactly that, so
# the column says what `slate js` is aiming at; the other two say what each yardstick's own JIT buys
# it. Nothing an interpreter does gets close to a tiering JIT, which is the whole reason they are
# kept out of the geometric means.
#
# `RUBY`, `PHP` and `LUAJIT` name the three binaries where they are not the defaults below --
# macOS's own `/usr/bin/ruby` is years old, so the default is Homebrew's.
set -e

dir=$(dirname "$0")
reps=5
tsv=0
ruby=${RUBY:-/opt/homebrew/opt/ruby/bin/ruby}
php=${PHP:-php}
luajit=${LUAJIT:-luajit}

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

# The Lua twin LuaJIT runs: the program's own `.luajit.lua` where it has one.
luajit_twin() {
    if [ -f "$dir/$1.luajit.lua" ]; then
        echo "$dir/$1.luajit.lua"
    else
        echo "$dir/$1.lua"
    fi
}

for name in startup $names; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" \
        "$(best "$slate" "$dir/$name.sl")" \
        "$(best lua "$dir/$name.lua")" \
        "$(best node --jitless "$dir/$name.js")" \
        "$(best python3 "$dir/$name.py")" \
        "$(best qjs "$dir/$name.js")" \
        "$(best "$ruby" --disable=yjit,zjit "$dir/$name.rb")" \
        "$(best "$php" -d opcache.jit=0 -d opcache.jit_buffer_size=0 "$dir/$name.php")" \
        "$(best "$luajit" -joff "$(luajit_twin "$name")")" \
        "$(best node "$dir/$name.js")" \
        "$(best "$ruby" --yjit "$dir/$name.rb")" \
        "$(best "$luajit" "$(luajit_twin "$name")")" >> "$rows"
done

if [ "$tsv" = 1 ]; then
    printf 'benchmark\tslate_ms\tlua_ms\tnode_jitless_ms\tpython_ms\tqjs_ms\truby_ms\tphp_ms\tluajit_interp_ms\tnode_jit_ms\truby_yjit_ms\tluajit_jit_ms\tvs_lua\tvs_node_jitless\tvs_python\tvs_qjs\tvs_ruby\tvs_php\tvs_luajit_interp\n'
fi

# Columns 3-9 are the seven yardsticks, 10-12 the three JITs. A ratio is taken only where both
# figures exist, and each yardstick's geometric mean is over the programs it ran, so a runtime that
# is not installed leaves its column empty rather than dragging a mean to zero.
awk -v tsv="$tsv" -F '\t' '
    BEGIN {
        if (tsv == 0) {
            printf "%-10s %8s %8s %8s %8s %8s %8s %8s %8s   %8s %8s %8s   %7s %7s %7s %7s %7s %7s %7s\n",
                "", "slate", "lua", "node-jl", "python", "qjs", "ruby", "php", "luajit-i",
                "node+jit", "ruby+yj", "lj+jit",
                "/lua", "/node", "/py", "/qjs", "/ruby", "/php", "/lj-i"
        }
    }

    {
        name = $1; s = $2 + 0

        for (c = 3; c <= 9; c++) {
            y = $c + 0
            r[c] = (s > 0 && y > 0) ? s / y : 0

            if (name != "startup" && r[c] > 0) {
                sum[c] += log(r[c]); count[c]++
            }
        }

        if (tsv == 1) {
            printf "%s\t%.1f", name, s
            for (c = 3; c <= 12; c++) printf "\t%.1f", $c + 0
            for (c = 3; c <= 9; c++) printf "\t%.2f", r[c]
            printf "\n"
        } else {
            printf "%-10s %8.1f", name, s
            for (c = 3; c <= 9; c++) printf " %8.1f", $c + 0
            printf "  "
            for (c = 10; c <= 12; c++) printf " %8.1f", $c + 0
            printf "  "
            for (c = 3; c <= 9; c++) printf " %6.1fx", r[c]
            printf "\n"
        }
    }

    END {
        for (c = 3; c <= 9; c++) g[c] = (count[c] > 0) ? exp(sum[c] / count[c]) : 0

        if (tsv == 1) {
            printf "geomean\t\t\t\t\t\t\t\t\t\t\t"
            for (c = 3; c <= 9; c++) printf "\t%.2f", g[c]
            printf "\n"
        } else {
            printf "%-10s %8s", "geomean", ""
            for (c = 3; c <= 9; c++) printf " %8s", ""
            printf "  "
            for (c = 10; c <= 12; c++) printf " %8s", ""
            printf "  "
            for (c = 3; c <= 9; c++) printf " %6.1fx", g[c]
            printf "\n"
        }
    }
' "$rows"
