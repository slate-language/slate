# slate embedded in C

`hello.c` is a C program with a `main` of its own that links slate as a static archive, runs slate
programs through it, and calls a slate function with values it made. The archive and its header come
from `sysl build-c`; the C API is `dev/slatelang/slate/embed.sysl` and `embed_values.sysl`, and the
header they produce declares:

```c
uint8_t *slate_version(void);
slate_vm *slate_new(uint64_t heap_bytes);
void slate_free(slate_vm *vm);
int32_t slate_eval(slate_vm *vm, uint8_t *text, uint64_t len, uint8_t *name, uint64_t name_len);
uint8_t *slate_error(slate_vm *vm);
uint64_t slate_error_len(slate_vm *vm);
```

and, for values and calls:

```c
uint64_t slate_int(slate_vm *vm, int64_t n);
uint64_t slate_real(slate_vm *vm, double x);
uint64_t slate_bool(slate_vm *vm, int32_t b);
uint64_t slate_null(slate_vm *vm);
uint64_t slate_string(slate_vm *vm, uint8_t *p, uint64_t len);
uint64_t slate_array(slate_vm *vm);
int32_t slate_push(slate_vm *vm, uint64_t array, uint64_t v);
uint64_t slate_object(slate_vm *vm);
int32_t slate_set(slate_vm *vm, uint64_t object, uint8_t *key, uint64_t key_len, uint64_t v);
void slate_release(slate_vm *vm, uint64_t v);

int32_t slate_kind(slate_vm *vm, uint64_t v);
int64_t slate_to_int(slate_vm *vm, uint64_t v);
double slate_to_real(slate_vm *vm, uint64_t v);
int32_t slate_to_bool(slate_vm *vm, uint64_t v);
uint8_t *slate_string_ptr(slate_vm *vm, uint64_t v);
uint64_t slate_string_len(slate_vm *vm, uint64_t v);
uint64_t slate_len(slate_vm *vm, uint64_t array);
uint64_t slate_at(slate_vm *vm, uint64_t array, uint64_t i);
uint64_t slate_get(slate_vm *vm, uint64_t object, uint8_t *key, uint64_t key_len);
uint8_t *slate_show(slate_vm *vm, uint64_t v);
uint64_t slate_show_len(slate_vm *vm);

uint64_t slate_global(slate_vm *vm, uint8_t *name, uint64_t name_len);
int32_t slate_call(slate_vm *vm, uint64_t f, uint64_t *argv, uint64_t argc, uint64_t *out);
```

and, for the traffic going the other way — a C function programs call, and where they print:

```c
int32_t slate_register(slate_vm *vm, uint8_t *name, uint64_t name_len,
                       uint64_t (*f)(slate_vm *, uint64_t *, uint64_t, uint8_t *), uint8_t *user);
void slate_on_output(slate_vm *vm, void (*f)(uint8_t *, uint64_t, uint8_t *), uint8_t *user);
```

The header spells the two callbacks as raw function-pointer types; named, they are

```c
typedef uint64_t (*slate_host_fn)(slate_vm *vm, uint64_t *argv, uint64_t argc, uint8_t *user);
typedef void (*slate_output_fn)(uint8_t *bytes, uint64_t len, uint8_t *user);
```

`slate_new` makes an interpreter with a heap of its own (`0` takes the size `slate` itself uses);
`slate_eval` runs a program on it and answers its status: `0` where it ran to the end, what it passed
to `exit`, or `1` where slate refused it, in which case `slate_error` is the diagnostic. What a
program prints goes to stdout as it prints it.

Every `slate_eval` on one `slate_vm` runs in one session, the way a REPL or Lua's `luaL_dostring` on
one state does: what an earlier call bound at its top level -- a function, a `val`, a class, an
import -- a later call can use, and what the later call binds joins it. A call slate refuses changes
nothing; one that faults keeps whatever it bound before the fault. Two handles share nothing.

## Values and calls

**A value C holds is a handle**: a `uint64_t` naming a slot in a table the `slate_vm` keeps, and that
table is walked by the collector, so a value stays alive for exactly as long as C holds its handle —
across any number of calls that collect. **`0` is never a handle**, so C can read it as "none".

- **Every handle is yours until `slate_release`**, including the new ones `slate_at`, `slate_get`,
  `slate_global` and `slate_call` answer. A released slot is reused by the next value made, so a host
  that releases what it is done with holds a table no bigger than it ever needed. `slate_free` gives
  the whole table back with the heap.
- **A handle belongs to the `slate_vm` that made it.**
- `slate_string` copies its bytes; `slate_string_ptr` points at the string's own UTF-8 bytes, not
  terminated, `slate_string_len` of them, and stays valid while the handle is held — slate strings
  never change and slate's heap never moves an object.
- `slate_show` is the value as `print` writes it, NUL-terminated, in one buffer per `slate_vm` that
  the next `slate_show` replaces.
- `slate_push` and `slate_set` answer `0`, or `1` where the target is not an array or an object, is
  frozen, or the value is not a live handle.

`slate_kind` answers:

| kind | value |
|---|---|
| `0` | `null` |
| `1` | a bool |
| `2` | an integer |
| `3` | a real |
| `4` | a string |
| `5` | an array |
| `6` | an object, a class instance included |
| `7` | a function, a builtin included |
| `8` | anything else |
| `-1` | `0`, or a handle already released |

`slate_global` answers a handle to what a top-level name of the session holds — what a `slate_eval`
defined, or a builtin — and `0` where nothing by that name is defined. `slate_call` calls a function
with `argc` handles from `argv`, runs it to its answer — through every `await`, then the loop drained
as it is after a program — writes a handle to the answer at `out`, and answers `0`. Where the call
faults, or `f` is not something that can be called, it answers `1`, leaves `*out` `0`, and
`slate_error` has the diagnostic, naming the file and line the fault happened at.

## Host functions and output

`slate_register` binds `name` at the session's top level to a C function, so every later program on
that `slate_vm` — and no other — can call it like any function. It answers `0`, or `1` with
`slate_error` set where `name` is not a name a program can write bare or `f` is null. **Registering
a name again replaces it**, as Lua's `lua_register` does; a value a program already took keeps
calling the function it was. A host function prints as `<host name>` and `slate_kind` calls it `7`.

- **It is handed a handle per argument, `argc` of them — exactly as many as the call wrote**, since a
  C function declares no count and slate's calls are JavaScript's: nothing is refused for being too
  few or too many. The argument handles are slate's; read them, and do not release them.
- **It answers a handle, or `0` for `null`.** The handle it answers is taken over by slate, which
  reads the value and releases the slot — so answer one you just made, or one of the arguments. A
  handle that names nothing by then (one already released) faults in the calling program with a
  sentence naming the host function.
- **It may call back into slate**: `slate_call` from inside a host function runs on the machine
  already running, as a callback from a builtin does, so C → slate → C → slate works to any depth.
  `slate_eval` is refused there, a program being a whole run of its own. The `user` pointer is
  whatever was handed to `slate_register`, untouched.

`slate_on_output` sends every line a program prints on that `slate_vm` to `f`, without the newline,
with the `user` pointer beside it — from `slate_eval` and from a function `slate_call` runs alike —
instead of to stdout; `f` null puts stdout back. The bytes are good for the length of the call.
Diagnostics still go to `slate_error`, never to the output function.

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
