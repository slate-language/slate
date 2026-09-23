#!/bin/sh
# Build slate profile-guided: instrument, train on `bench/`, merge, rebuild against the profile.
#
#     bench/pgo.sh [out-dir]
#
# **This is how the release binary is built.** `package.hocon` already asks for `-O2` and thin LTO,
# which every build gets; a profile is the third lever and is not a manifest key, because it is one
# measurement taken on one machine and a path to it would be wrong for everybody else. So it is this
# script, run from anywhere, and the binary it prints is the one to stage.
#
# **The training set is every program in `bench/`**, each run once by the instrumented binary. They
# were written to stress one part of the interpreter each -- calls, fields, strings, tables, the
# collector -- which is what a profile wants: the paths a real program takes, each taken often. The
# instrumented run is slower than a plain one and that is expected; its answers are discarded.
#
# **`llvm-profdata` is asked of clang rather than found on the PATH.** A `.profraw` carries a format
# version and the tool must be the compiler's own LLVM -- on a Mac that is Xcode's, which is nowhere
# on the PATH, while Homebrew's LLVM puts a different one there. The mismatch reads as a corrupt
# profile ("raw profile version mismatch") rather than as the wrong tool.
#
# The output directory (default `pgo/` at the project root, which is ignored) is emptied first, so a
# stale counter file from an earlier binary can never be merged into this one's profile.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/pgo}

rm -rf "$out"
mkdir -p "$out/raw"
out=$(cd "$out" && pwd)

cd "$root"

echo "pgo: building the instrumented binary" >&2
sysl build . --lto thin --profile-generate "$out/raw" -o "$out/slate-instrumented"

for program in bench/*.sl; do
    echo "pgo: training on $program" >&2
    "$out/slate-instrumented" "$program" > /dev/null
done

echo "pgo: merging the profile" >&2
profdata=$(clang -print-prog-name=llvm-profdata)
"$profdata" merge -output "$out/slate.profdata" "$out"/raw/*.profraw

echo "pgo: building against the profile" >&2
sysl build . --lto thin --profile-use "$out/slate.profdata" -o "$out/slate"

echo "$out/slate"
