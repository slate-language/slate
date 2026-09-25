# slate embedded in C

`hello.c` is a C program with a `main` of its own that links slate as a static archive and runs
five slate programs through it. The archive and its header come from `sysl build-c`; the C API is
`dev/slatelang/slate/embed.sysl`, and the header it produces declares:

```c
uint8_t *slate_version(void);
slate_vm *slate_new(uint64_t heap_bytes);
void slate_free(slate_vm *vm);
int32_t slate_eval(slate_vm *vm, uint8_t *text, uint64_t len, uint8_t *name, uint64_t name_len);
uint8_t *slate_error(slate_vm *vm);
uint64_t slate_error_len(slate_vm *vm);
```

`slate_new` makes an interpreter with a heap of its own (`0` takes the size `slate` itself uses);
`slate_eval` runs a program on it and answers its status: `0` where it ran to the end, what it passed
to `exit`, or `1` where slate refused it, in which case `slate_error` is the diagnostic. What a
program prints goes to stdout as it prints it.

Every `slate_eval` on one `slate_vm` runs in one session, the way a REPL or Lua's `luaL_dostring` on
one state does: what an earlier call bound at its top level -- a function, a `val`, a class, an
import -- a later call can use, and what the later call binds joins it. A call slate refuses changes
nothing; one that faults keeps whatever it bound before the fault. Two handles share nothing.

## Building it

From the repository root, build the archive and the header:

```
sysl build-c . -o examples/embed/libslate.a
```

`build-c` prints the libraries the archive still needs — the ones `@link` named, and the packages'
`pkg_config` modules as a `pkg-config --libs …` line. Link `hello.c` with both:

```
cd examples/embed
clang hello.c -I. libslate.a -luv -llmdb -lnghttp2 -lssl -lcrypto -lsqlite3 -lm $(pkg-config --libs libbrotlidec libbrotlienc hiredis libuv libwebp lmdb libnghttp2 libcrypto libssl sqlite3 libzstd) -o hello
./hello
```

`scripts/embed-check.sh` does all of that and checks what `hello` prints; the release runs it.
