#!/bin/zsh
#
# The C surface, proven end to end: `sysl build-c` on this tree, a C `main` linked against the archive
# with exactly the libraries build-c named, run, and its output compared.
#
#     scripts/embed-check.sh                  build into a scratch directory, check, throw it away
#     scripts/embed-check.sh --stage <dir>    build into <dir> as an install prefix, check, keep it
#     scripts/embed-check.sh --prefix <dir>   build nothing: check a prefix a `--stage` made
#
# A prefix is what the `libslate` tarball holds: `lib/libslate.a`, `include/slate.h`, `LINK.txt` (the
# two lines of advice build-c printed, verbatim), and `example/` -- `hello.c`, its README, and
# `expected.txt`, what `hello` prints. `--prefix` is the release's check on a machine that did not
# build the archive: it reads the link line out of `LINK.txt` and the answer out of `expected.txt`, so
# both are the ones this script wrote and there is one copy of each.
#
# `tests_embed.sysl` drives the same functions in process; what it cannot see is the archive, the
# header, and whether a C compiler accepts them and a C linker resolves them, which is what this is
# for. It is a full compile of the tree, so it is a release and CI step rather than part of
# `sysl test .`. It is zsh on Linux too: the runners install it for this.

set -e

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/slate-embed-XXXXXX")

case "${1:-}" in
    "")       prefix="$work/prefix"; build=yes ;;
    --stage)  prefix="${2:?--stage names a directory}"; build=yes ;;
    --prefix) prefix="${2:?--prefix names a directory}"; build=no ;;
    *)        echo "usage: scripts/embed-check.sh [--stage <dir> | --prefix <dir>]" >&2; exit 2 ;;
esac

mkdir -p "$prefix"
prefix=$(cd "$prefix" && pwd)

if [[ $build == yes ]]; then
    mkdir -p "$prefix/lib" "$prefix/include" "$prefix/example"
    cd "$root"

    sysl build-c . -o "$prefix/lib/libslate.a" --header "$prefix/include/slate.h" 2> "$work/build-c.log"
    cat "$work/build-c.log"

    # The link line is what build-c said and nothing else: `-l` for each `@link` name, and the
    # pkg-config modules' flags. A library it did not name is a defect in build-c, not something to add here.
    grep -E '^sysl: link this against:|pkg-config --libs ' "$work/build-c.log" > "$prefix/LINK.txt"

    cp examples/embed/hello.c examples/embed/README.md "$prefix/example/"

    cat > "$prefix/example/expected.txt" <<EOF
hello from C
first run: 0
define: 0
42
use: 0
second run: 1
third run: 3
double(21) from C: 42
listed(3) from C: [3, 6, "done"] (3 elements)
[slate] 42
[slate] from slate
host: 0
6
[loop] armed
armed: 0
pending: 1
descriptor: yes, wait: yes
[loop] tick
idle: 0
EOF
fi

links=$(grep '^sysl: link this against:' "$prefix/LINK.txt" | sed 's/^sysl: link this against: //' | tr -d ',' | sed 's/\([^ ][^ ]*\)/-l\1/g')
# Not `modules`: in zsh that is a read-only special parameter, and assigning to it kills the script.
pkgs=$(grep -o 'pkg-config --libs .*' "$prefix/LINK.txt" | sed 's/^pkg-config --libs //')

# **The archive's main object is LLVM bitcode, not machine code**: the manifest's `lto = "thin"`
# reaches `build-c` too, so the link is where it is compiled. macOS's linker reads bitcode on its own;
# GNU ld does not, so on Linux the link goes through lld, which does -- and gcc cannot link it at all.
linker=()
[[ $(uname) == Linux ]] && linker=(-fuse-ld=lld)

clang "$prefix/example/hello.c" -I"$prefix/include" "$prefix/lib/libslate.a" ${=links} $(pkg-config --libs ${=pkgs}) $linker -o "$work/hello"

"$work/hello" > "$work/out.txt" 2> "$work/err.txt"

if ! diff <(grep -v '^slate ' "$work/out.txt") "$prefix/example/expected.txt"; then
    echo "embed-check: hello printed something else (see $work/out.txt)" >&2
    exit 1
fi

if ! grep -q 'broken.sl' "$work/err.txt"; then
    echo "embed-check: the refused program's diagnostic did not name broken.sl" >&2
    cat "$work/err.txt" >&2
    exit 1
fi

# The handle's declaration as the header wrote it: a bare `typedef struct slate_vm slate_vm;` is what a
# C caller can hold, and a field list here would name sysl types clang has never heard of.
grep -hE '(typedef|struct).*slate_vm' "$prefix/include/slate.h" || true

# The two host callbacks as the header spells them: a function-pointer parameter is `R (*name)(A)`,
# which is the one spelling clang accepts.
grep -hE 'slate_register|slate_on_output' "$prefix/include/slate.h" || true

# The loop a host owns: the mode, the turn, the blocking drain, and the two things a `poll` reads.
grep -hE 'slate_set_manual_loop|slate_pump|slate_run_until_idle|slate_loop_fd|slate_loop_timeout' "$prefix/include/slate.h" || true

echo "embed-check: OK"
rm -rf "$work"
