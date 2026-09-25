#!/bin/zsh
#
# The C surface, proven end to end: `sysl build-c` on this tree, a C `main` linked against the archive
# with exactly the libraries build-c named, run, and its output compared.
#
#     scripts/embed-check.sh
#
# `tests_embed.sysl` drives the same functions in process; what it cannot see is the archive, the
# header, and whether a C compiler accepts them and a C linker resolves them, which is what this is
# for. It is a minute of compiling, so it is a release step rather than part of `sysl test .`.

set -e

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/slate-embed-XXXXXX")

cd "$root"

sysl build-c . -o "$work/libslate.a" 2> "$work/build-c.log"
cat "$work/build-c.log"

# The link line is what build-c said and nothing else: `-l` for each `@link` name, and the
# pkg-config modules' flags. A library it did not name is a defect in build-c, not something to add here.
links=$(grep '^sysl: link this against:' "$work/build-c.log" | sed 's/^sysl: link this against: //' | tr -d ',' | sed 's/\([^ ][^ ]*\)/-l\1/g')
# Not `modules`: in zsh that is a read-only special parameter, and assigning to it kills the script.
pkgs=$(grep -o 'pkg-config --libs .*' "$work/build-c.log" | sed 's/^pkg-config --libs //')

clang examples/embed/hello.c -I"$work" "$work/libslate.a" ${=links} $(pkg-config --libs ${=pkgs}) -o "$work/hello"

"$work/hello" > "$work/out.txt" 2> "$work/err.txt"

expected="slate $(./slate --version 2>/dev/null | sed 's/^slate //' || true)"

cat > "$work/want.txt" <<EOF
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
EOF

if ! diff <(grep -v '^slate ' "$work/out.txt") "$work/want.txt"; then
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
grep -hE '(typedef|struct).*slate_vm' "$work"/*.h || true

echo "embed-check: OK"
rm -rf "$work"
