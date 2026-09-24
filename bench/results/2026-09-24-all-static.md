# 2026-09-24 — sysl 0.0.134: every library with an archive is linked statically

**sysl 0.0.134 changed what `link = "static"` means, and slate now uses it.** In 0.0.133 the word
meant "every library, or refuse", and `/usr/lib`'s SQLite has no archive, so the build was refused.
From 0.0.134 it means "every library that has an archive, and the rest dynamically", with a
`--verbose` trace line for each one. A name in a `link` list whose feature is off is also skipped
now, but slate does not need that: `"static"` names nothing, so it cannot name a library that a
build leaves out. `package.hocon` says `link = "static"`. The floor moves to **0.0.134**, because an
older compiler reads the same key and refuses the build, and both `SYSL_VERSION` pins move with it.

This is the measurement `2026-09-24-sysl-0-0-133.md` took and could not land. Against dev with three
libraries static, the geometric mean moves **−6.53%**. `startup` is **−35.9%**, `strindex`
**−29.5%** and `strwalk` **−25.3%**. `startup` and `strindex` are now level with qjs.

## `"static"` rather than a list of names

An explicit list would have to name ten libraries: `libuv`, `libssl`, `libcrypto`, `lmdb`,
`libnghttp2`, `hiredis`, `libbrotlidec`, `libbrotlienc`, `libwebp` and `libzstd`. Someone would have
to keep that list in step with the `pkg_config` names by hand. A list also
cannot follow `--features webview`, or a library a future dependency brings in. `"static"` is right
in every build shape and on both platforms. Its one cost is that it says nothing about which
libraries stay dynamic. `sysl build . --verbose` answers that, one line per library:

```
sysl: static: -luv is /opt/homebrew/Cellar/libuv/1.52.1/lib/libuv.a
sysl: static: -lssl is /opt/homebrew/Cellar/openssl@3/3.6.4/lib/libssl.a
sysl: static: 'sqlite3' has no 'libsqlite3.a', so -lsqlite3 is linked dynamically — looked in /usr/lib
```

The build also takes brotli's `libbrotlicommon.a` and webp's `libsharpyuv.a`. Those two come in
through their `.pc` files, and a list would have had to name them too.

## The census

`otool -L` on the binary that `bench/pgo.sh` builds:

| binary | lines | Homebrew dylibs | size |
|---|---|---|---|
| control (dev `8b59501`, three static) | 9 | lmdb, libnghttp2, libbrotlidec, libbrotlienc, hiredis, libwebp, libzstd | 10,297,528 bytes |
| branch (`link = "static"`) | 2 | **none** | 11,980,104 bytes |

The two lines left are `/usr/lib/libSystem.B.dylib` and `/usr/lib/libsqlite3.dylib`. **The
formula's `depends_on` lines for brotli, hiredis, libnghttp2, lmdb, webp and zstd all go at the next
release**, so no Homebrew runtime dependency is left. The size matches the "all eight" figure that
0.0.133 measured with `--link`, to the byte.

**Linux should look the same.** `scripts/linux-deps.sh` builds hiredis, libuv, lmdb, nghttp2 and
zstd as archives only. Debian's `libssl-dev`, `libsqlite3-dev`, `libbrotli-dev` and `libwebp-dev`
all ship `.a` files beside their shared objects. So on Linux, `"static"` should take SQLite as well,
and `ldd` on the tarball should list only glibc: `libc`, `libm`, and the loader. That is not proved
until CI's first run on this commit. The compat job's `ldd` step is where to read it.

## PGO against PGO: `bench/alternate.pl 9`, control (dev `8b59501`) vs branch

Both binaries were built by `bench/pgo.sh` with sysl 0.0.134. The run waited until the box was more
than 85% idle, and `pgrep -x java` was empty. Everything ran under `caffeinate -dimsu`.

| program | control (ms) | branch (ms) | change |
|---|---|---|---|
| startup | 3.853 | 2.469 | **−35.9%** |
| strindex | 4.238 | 2.987 | **−29.5%** |
| strwalk | 5.132 | 3.832 | **−25.3%** |
| strings | 9.545 | 8.404 | **−12.0%** |
| arith | 81.390 | 77.618 | −4.6% |
| loops | 91.477 | 87.939 | −3.9% |
| options | 154.194 | 149.558 | −3.0% |
| globals | 50.332 | 48.908 | −2.8% |
| csv | 105.050 | 102.512 | −2.4% |
| nested | 152.611 | 149.052 | −2.3% |
| mapset | 40.263 | 39.409 | −2.1% |
| (the other twelve) | | | +0.1% to −1.9% |
| **geometric mean** | | | **−6.53%** |

The largest gains are again on the programs whose whole run takes a few milliseconds. There, dyld
mapping and binding seven more dylibs was the biggest single cost. The 0.0.133 write-up measured
−8.80% for all-static against a fully dynamic control. The two results agree: −3.69% came from the
first three libraries and −6.53% comes from the rest, which compounds to −9.98%.

## Against qjs: one quiet `bench/run.sh -n 5 pgo/slate startup strindex strwalk`

| program | slate | qjs | lua | slate/qjs | slate/lua |
|---|---|---|---|---|---|
| startup | 2.3 | 2.2 | 1.8 | 1.1x | 1.3x |
| strindex | 2.8 | 2.9 | 2.3 | 1.0x | 1.2x |
| strwalk | 3.8 | 2.8 | 151.2 | 1.4x | (not a yardstick) |

`startup` appears twice in the run's output, at 2.5 and 2.3 ms against qjs's 2.1 and 2.2. The table
takes the second row.

## Tests

No test reads the built binary. sysl gives a test no way to name the executable it built, so the
census is recorded here and not in the suite. The floor has no test of its own. All three gate
shapes passed on this commit: `sysl test .`, `--features profile`, and `--no-default-features`. The
last is the shape that refused a list naming a feature-gated library under 0.0.133.
