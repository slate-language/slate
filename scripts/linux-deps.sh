#!/usr/bin/env bash
#
# Everything a Debian-family machine needs before it can build slate.
#
# **This is one file so that the container and the runner cannot drift.** The GitHub workflow runs it
# with `sudo`, `scripts/linux-shell.sh` bakes it into an image, and a person setting up their own box
# runs it directly -- so a library added to `package.hocon` is added here once and all three follow.
# Two lists that have to agree is how a Linux build breaks for the person who is not looking.
#
# Run as root, or under `sudo`.
set -euo pipefail

# **The LLVM is pinned, because sysl emits IR in one LLVM's spelling.** An older clang does not
# recognise the overloaded intrinsic names sysl writes and reports them as undefined symbols at the
# link -- a version disagreement wearing a linker error. Ubuntu 22.04's own clang is 14, far below
# what the compiler needs, so it comes from apt.llvm.org rather than from the distribution.
LLVM_VERSION="${LLVM_VERSION:-20}"

# **node is a hard requirement of the SUITE, not of the language.** `slate test --js` shells out to it
# and the differential corpus is the whole check that the two back ends agree, so a machine without
# node runs about half of slate's tests and reports the rest as `node could not be started`. 24 is
# what the development machine has and what `crypto.argon2` and `node:sqlite` need.
NODE_MAJOR="${NODE_MAJOR:-24}"

# **Six libraries are newer than any distribution has, so they are built here from source and
# linked STATICALLY.** Each is pinned to a release whose headers carry a symbol a binding names:
#
#   hiredis  1.0.0+  the RESP3 reply kinds -- `REDIS_REPLY_DOUBLE`, `MAP`, `SET`, `PUSH`, `VERB`,
#                    `BIGNUM`, `BOOL`, `ATTR`. Ubuntu 22.04 has 0.14.1, which predates RESP3.
#   libuv    1.49.0+ `UV_TCP_REUSEPORT`, and 1.45.0+ for `UV_CLOCK_MONOTONIC` / `UV_CLOCK_REALTIME`.
#                    22.04 has 1.43.0 and even 24.04 has only 1.48.0, so no LTS is new enough.
#   lmdb     1.0.0+  `MDB_PROBLEM`. Every distribution is still on the 0.9 series, 24.04 and
#                    Debian 13 included, so this one is not a question of choosing a newer image.
#   nghttp2  1.61.0+ `nghttp2_data_provider2`, the 64-bit-length rewrite of the data provider.
#                    22.04 has 1.43.0 and 24.04 has 1.59.0, so again no LTS carries it.
#   zstd     1.5.6+  the `ZSTD_error_*` enum, which only reached `zstd.h` through `zstd_errors.h`
#                    in that release; the binding includes `zstd.h` alone. 22.04 has 1.4.8.
#   pcre2    10.43+  a BOUNDED variable-length lookbehind -- `(?<=ab?)c` -- which earlier releases
#                    refuse outright as "not fixed length". slate documents that PCRE2 takes a
#                    bounded one and refuses only an unbounded one, and that is true from 10.43.
#                    22.04 has 10.39.
#
# **Static is the answer rather than a shared build, and it is what makes the tarball portable.**
# A shared build here would put a soname in the binary that the machine installing it does not have
# -- 22.04 carries `libhiredis.so.0.14` and 24.04 `libhiredis.so.1.1.0`, so a binary linked against
# either fails to start on the other. Linked in, there is nothing to disagree about: these six
# disappear from `ldd` entirely and the tarball runs on every distribution the glibc floor allows.
HIREDIS_VERSION="${HIREDIS_VERSION:-1.4.0}"
LIBUV_VERSION="${LIBUV_VERSION:-1.51.0}"
LMDB_VERSION="${LMDB_VERSION:-1.0.1}"
NGHTTP2_VERSION="${NGHTTP2_VERSION:-1.67.0}"
ZSTD_VERSION="${ZSTD_VERSION:-1.5.7}"
PCRE2_VERSION="${PCRE2_VERSION:-10.48}"

export DEBIAN_FRONTEND=noninteractive

apt-get update

# `build-essential` is here for the system linker and the C headers clang compiles against, not for
# gcc: sysl drives clang, and clang still needs `ld` and libc's headers to finish a link.
#
# `time` is GNU time, `/usr/bin/time`, which is not the shell's `time` keyword and is not installed
# by default. `scripts/linux-measure.sh` reports the build's memory through it.
apt-get install -y --no-install-recommends \
  build-essential ca-certificates cmake curl git gnupg lsb-release make pkg-config \
  software-properties-common tar time wget

# **The libraries the bound packages link, in Debian's spelling of the Homebrew formula's list.**
# brotli, openssl and webp are found through pkg-config and none is vendored; SQLite is the machine's
# own copy, which every distribution ships. hiredis, libuv, lmdb, nghttp2, zstd and pcre2 are
# deliberately absent -- they are built below, and installing the distribution's headers beside them
# would only give pkg-config two answers to the same question.
#
# **`tzdata` is not optional and its absence does not read as a missing package.** The interpreter's
# calendar reads `/usr/share/zoneinfo`, so on an image without it `zone("America/Toronto")` answers
# that a field is not there -- seven calendar tests failing over a database nobody mentioned. A real
# installation has it; a minimal container image does not.
#
# `libgc` and `libunwind` are the sysl *compiler's* own -- it is a Scala Native binary and links
# both -- so they are needed to run `sysl` at all, not to build slate.
apt-get install -y --no-install-recommends \
  libbrotli-dev \
  libgc-dev \
  libsqlite3-dev \
  libssl-dev \
  libunwind-dev \
  libwebp-dev \
  tzdata

wget -qO /tmp/llvm.sh https://apt.llvm.org/llvm.sh
chmod +x /tmp/llvm.sh
/tmp/llvm.sh "$LLVM_VERSION"
apt-get install -y "llvm-$LLVM_VERSION" "lld-$LLVM_VERSION"
rm -f /tmp/llvm.sh

curl -fsSL "https://deb.nodesource.com/setup_$NODE_MAJOR.x" -o /tmp/nodesource.sh
bash /tmp/nodesource.sh
apt-get install -y nodejs
rm -f /tmp/nodesource.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "building hiredis $HIREDIS_VERSION (static)"
curl -fsSL "https://github.com/redis/hiredis/archive/refs/tags/v$HIREDIS_VERSION.tar.gz" \
  | tar -xz -C "$work"
make -C "$work/hiredis-$HIREDIS_VERSION" static -j"$(nproc)"
make -C "$work/hiredis-$HIREDIS_VERSION" install PREFIX=/usr/local
# `make install` copies the shared library too even after a `static` build. Leaving it would let the
# linker prefer it and put a soname back in the binary, which is the whole thing being avoided.
rm -f /usr/local/lib/libhiredis.so*

echo "building libuv $LIBUV_VERSION (static)"
curl -fsSL "https://github.com/libuv/libuv/archive/refs/tags/v$LIBUV_VERSION.tar.gz" \
  | tar -xz -C "$work"
cmake -S "$work/libuv-$LIBUV_VERSION" -B "$work/libuv-build" \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DLIBUV_BUILD_SHARED=OFF \
  -DLIBUV_BUILD_TESTS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build "$work/libuv-build" -j"$(nproc)"
cmake --install "$work/libuv-build"
# A static libuv install writes `libuv-static.pc` and no `libuv.pc`; the binding asks pkg-config for
# `libuv`, which is the name the shared build would have left.
cp /usr/local/lib/pkgconfig/libuv-static.pc /usr/local/lib/pkgconfig/libuv.pc

echo "building lmdb $LMDB_VERSION (static)"
curl -fsSL "https://github.com/LMDB/lmdb/archive/refs/tags/LMDB_$LMDB_VERSION.tar.gz" \
  | tar -xz -C "$work"
lmdb_src="$work/lmdb-LMDB_$LMDB_VERSION/libraries/liblmdb"
make -C "$lmdb_src" -j"$(nproc)" liblmdb.a mdb_stat mdb_copy
install -Dm644 "$lmdb_src/lmdb.h" /usr/local/include/lmdb.h
install -Dm644 "$lmdb_src/liblmdb.a" /usr/local/lib/liblmdb.a
# LMDB ships no pkg-config file of its own -- Debian writes one for its package -- so this is the
# same `lmdb.pc` a distribution would have provided, pointing at the static archive.
mkdir -p /usr/local/lib/pkgconfig
cat > /usr/local/lib/pkgconfig/lmdb.pc <<PC
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: lmdb
Description: Lightning Memory-Mapped Database
Version: $LMDB_VERSION
Libs: -L\${libdir} -l:liblmdb.a -lpthread
Cflags: -I\${includedir}
PC

echo "building nghttp2 $NGHTTP2_VERSION (static)"
curl -fsSL "https://github.com/nghttp2/nghttp2/releases/download/v$NGHTTP2_VERSION/nghttp2-$NGHTTP2_VERSION.tar.gz" \
  | tar -xz -C "$work"
cmake -S "$work/nghttp2-$NGHTTP2_VERSION" -B "$work/nghttp2-build" \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_LIB_ONLY=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_STATIC_LIBS=ON \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build "$work/nghttp2-build" -j"$(nproc)"
cmake --install "$work/nghttp2-build"
# The static archive is installed as `libnghttp2_static.a` and the generated `libnghttp2.pc` names
# `-lnghttp2`, which is the shared library that is not there -- so the archive is given the plain
# name and the file is written out pointing at it, rather than patched.
if [ -f /usr/local/lib/libnghttp2_static.a ]; then
  cp /usr/local/lib/libnghttp2_static.a /usr/local/lib/libnghttp2.a
fi
cat > /usr/local/lib/pkgconfig/libnghttp2.pc <<PC
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libnghttp2
Description: HTTP/2 C library
Version: $NGHTTP2_VERSION
Libs: -L\${libdir} -l:libnghttp2.a
Cflags: -I\${includedir}
PC

echo "building zstd $ZSTD_VERSION (static)"
curl -fsSL "https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/zstd-$ZSTD_VERSION.tar.gz" \
  | tar -xz -C "$work"
cmake -S "$work/zstd-$ZSTD_VERSION/build/cmake" -B "$work/zstd-build" \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DZSTD_BUILD_SHARED=OFF \
  -DZSTD_BUILD_STATIC=ON \
  -DZSTD_BUILD_PROGRAMS=OFF \
  -DZSTD_BUILD_TESTS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build "$work/zstd-build" -j"$(nproc)"
cmake --install "$work/zstd-build"
cat > /usr/local/lib/pkgconfig/libzstd.pc <<PC
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: zstd
Description: fast lossless compression algorithm library
Version: $ZSTD_VERSION
Libs: -L\${libdir} -l:libzstd.a
Cflags: -I\${includedir}
PC

echo "building pcre2 $PCRE2_VERSION (static)"
curl -fsSL "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz" \
  | tar -xz -C "$work"
cmake -S "$work/pcre2-$PCRE2_VERSION" -B "$work/pcre2-build" \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_STATIC_LIBS=ON \
  -DPCRE2_BUILD_PCRE2_8=ON \
  -DPCRE2_SUPPORT_UNICODE=ON \
  -DPCRE2_SUPPORT_JIT=ON \
  -DPCRE2_BUILD_TESTS=OFF \
  -DPCRE2_BUILD_PCRE2GREP=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build "$work/pcre2-build" -j"$(nproc)"
cmake --install "$work/pcre2-build"
cat > /usr/local/lib/pkgconfig/libpcre2-8.pc <<PC
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libpcre2-8
Description: Perl compatible regular expressions library with 8 bit character support
Version: $PCRE2_VERSION
Libs: -L\${libdir} -l:libpcre2-8.a
Cflags: -I\${includedir}
PC

ldconfig

echo "toolchain is on /usr/lib/llvm-$LLVM_VERSION/bin"
node --version
pkg-config --modversion hiredis libuv lmdb libnghttp2 libzstd libpcre2-8
