#!/bin/zsh
#
# The C surface, proven end to end: `sysl build-c` on this tree, a C `main` linked against the archive
# with exactly the libraries build-c named, run, and its output compared.
#
#     scripts/embed-check.sh                  build into a scratch directory, check, throw it away
#     scripts/embed-check.sh --stage <dir>    build into <dir> as an install prefix, check, keep it;
#                                             and build the `--lto thin` form in scratch and check it
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
    "")       prefix="$work/prefix"; build=yes; lto=no ;;
    --stage)  prefix="${2:?--stage names a directory}"; build=yes; lto=yes ;;
    --prefix) prefix="${2:?--prefix names a directory}"; build=no; lto=no ;;
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

# The archive is native objects (`build-c` writes them from sysl 0.0.139 on, whatever the manifest's
# `lto` says), so the link is a plain one with the platform's own linker -- GNU ld on Linux, ld64 on
# macOS -- and gcc would do as well as clang.

# Runs `hello`, built at $1, and compares what it prints with `expected.txt`.
run_hello() {
    "$1" > "$work/out.txt" 2> "$work/err.txt"

    if ! diff <(grep -v '^slate ' "$work/out.txt") "$prefix/example/expected.txt"; then
        echo "embed-check: $1 printed something else (see $work/out.txt)" >&2
        exit 1
    fi

    if ! grep -q 'broken.sl' "$work/err.txt"; then
        echo "embed-check: the refused program's diagnostic did not name broken.sl" >&2
        cat "$work/err.txt" >&2
        exit 1
    fi
}

clang "$prefix/example/hello.c" -I"$prefix/include" "$prefix/lib/libslate.a" ${=links} $(pkg-config --libs ${=pkgs}) -o "$work/hello"
run_hello "$work/hello"

# **The LTO form, which a release does not ship but a host may build**: `build-c --lto thin` writes a
# bitcode archive, for a host linking with clang and lld that wants optimisation across the boundary.
# It is built in scratch and never staged -- the tarball carries the native form -- and build-c must
# say, as it writes it, how it links. Apple's clang links bitcode with its own linker, so on macOS the
# link is plain `clang`; on Linux it needs lld built from the same LLVM as sysl, which a runner cannot
# promise, so there the advice line is the whole check. It is a second full compile, so only `--stage`
# -- the release's run -- pays for it.
if [[ $lto == yes ]]; then
    cd "$root"
    mkdir -p "$work/lto"
    sysl build-c . --lto thin -o "$work/lto/libslate.a" --header "$work/lto/slate.h" 2> "$work/build-c-lto.log"
    cat "$work/build-c-lto.log"

    if ! grep -q -- '-fuse-ld=lld' "$work/build-c-lto.log"; then
        echo "embed-check: build-c --lto thin did not say how a bitcode archive links" >&2
        exit 1
    fi

    if [[ $(uname) == Darwin ]]; then
        clang "$prefix/example/hello.c" -I"$work/lto" "$work/lto/libslate.a" ${=links} $(pkg-config --libs ${=pkgs}) -o "$work/hello-lto"
        run_hello "$work/hello-lto"
        echo "embed-check: the --lto thin archive links (Apple clang, no lld needed) and runs"
    else
        echo "embed-check: the --lto thin archive was built; its link is not tried here (it needs sysl's own lld)"
    fi
fi

# The two handles' declarations as the header wrote them: a bare `typedef struct slate_vm slate_vm;` is
# what a C caller can hold, and a field list here would name sysl types clang has never heard of; and
# `typedef uint64_t slate_value;` is the name every value handle goes by.
grep -hE '(typedef|struct).*slate_vm|typedef .* slate_value;' "$prefix/include/slate.h" || true

# The value handle has its own C name, and a handle position says it: a header that has gone back to
# a bare `uint64_t` there still compiles, so only reading it can tell.
for want in 'typedef uint64_t slate_value;' 'slate_value slate_int('; do
    if ! grep -qF "$want" "$prefix/include/slate.h"; then
        echo "embed-check: the header does not declare '$want'" >&2
        exit 1
    fi
done

# The two host callbacks as the header spells them: a function-pointer parameter is `R (*name)(A)`,
# which is the one spelling clang accepts.
grep -hE 'slate_register|slate_on_output' "$prefix/include/slate.h" || true

# The loop a host owns: the mode, the turn, the blocking drain, and the two things a `poll` reads.
grep -hE 'slate_set_manual_loop|slate_pump|slate_run_until_idle|slate_loop_fd|slate_loop_timeout' "$prefix/include/slate.h" || true

echo "embed-check: OK"
rm -rf "$work"
