# Embedding slate in a C program

`sysl build-c` compiles the interpreter into a static archive and a header declaring what
`dev/slatelang/slate/embed.sysl` exports: `slate_version_major` and `slate_run_source`, which runs a
buffer of slate source exactly as `slate <file>` runs a file and answers its exit status. There is
no init call to make: the archive fills its module storage from a constructor the platform runs
before the C program's `main`.

From the project root:

```
sysl build-c . -o examples/embed/libslate.a
cd examples/embed
clang hello.c -I. libslate.a $(pkg-config --libs --static libuv lmdb libnghttp2 openssl libbrotlienc libbrotlidec libwebp libzstd hiredis) -lsqlite3 -o hello
./hello
```

It prints:

```
slate major version: 0
hello from C
slate_run_source returned 0
error: `nope` is not defined
 --> <embedded>:1:1
  |
1 | nope()
  | ^^^^

second run returned 1
```

`build-c` announces `link this against: uv, lmdb, nghttp2, ssl, crypto, sqlite3, m`, and that list
is short: brotli, libwebp, zstd and hiredis are needed as well, and the link fails without them.
The build takes about a minute and a half and the archive is about 24 MB. The libraries are linked
dynamically here; `package.hocon`'s `link = "static"` governs `sysl build`, not a C link line.
