# slate embedded in C

`hello.c` is a C program with a `main` of its own that links slate as a static archive, runs slate
programs through it, and calls a slate function with values it made. The archive and its header come
from `sysl build-c`; the C API is `dev/slatelang/slate/embed.sysl`, `embed_values.sysl` and
`embed_loop.sysl`, and the header they produce declares:

```c
uint8_t * slate_version(void);
slate_vm * slate_new(uint64_t heap_bytes);
void slate_free(slate_vm * h);
int32_t slate_eval(slate_vm * h, uint8_t * text, uint64_t len, uint8_t * name, uint64_t name_len);
uint8_t * slate_error(slate_vm * h);
uint64_t slate_error_len(slate_vm * h);
```

and, for values and calls:

```c
typedef uint64_t slate_value;

slate_value slate_int(slate_vm * h, int64_t n);
slate_value slate_real(slate_vm * h, double x);
slate_value slate_bool(slate_vm * h, int32_t b);
slate_value slate_null(slate_vm * h);
slate_value slate_string(slate_vm * h, uint8_t * p, uint64_t len);
slate_value slate_array(slate_vm * h);
int32_t slate_push(slate_vm * h, slate_value array, slate_value v);
slate_value slate_object(slate_vm * h);
int32_t slate_set(slate_vm * h, slate_value object, uint8_t * key, uint64_t key_len, slate_value v);
void slate_release(slate_vm * h, slate_value v);

int32_t slate_kind(slate_vm * h, slate_value v);
int64_t slate_to_int(slate_vm * h, slate_value v);
double slate_to_real(slate_vm * h, slate_value v);
int32_t slate_to_bool(slate_vm * h, slate_value v);
uint8_t * slate_string_ptr(slate_vm * h, slate_value v);
uint64_t slate_string_len(slate_vm * h, slate_value v);
uint64_t slate_len(slate_vm * h, slate_value array);
slate_value slate_at(slate_vm * h, slate_value array, uint64_t i);
slate_value slate_get(slate_vm * h, slate_value object, uint8_t * key, uint64_t key_len);
uint8_t * slate_show(slate_vm * h, slate_value v);
uint64_t slate_show_len(slate_vm * h);

slate_value slate_global(slate_vm * h, uint8_t * name, uint64_t name_len);
int32_t slate_call(slate_vm * h, slate_value f, slate_value * argv, uint64_t argc, slate_value * out);
```

and, for the traffic going the other way — a C function programs call, and where they print:

```c
int32_t slate_register(slate_vm * h, uint8_t * name, uint64_t name_len, slate_value (*f)(slate_vm *, slate_value *, uint64_t, uint8_t *), uint8_t * user);
void slate_on_output(slate_vm * h, void (*f)(uint8_t *, uint64_t, uint8_t *), uint8_t * user);
```

The header spells the two callbacks as raw function-pointer types; named, they are

```c
typedef slate_value (*slate_host_fn)(slate_vm *vm, slate_value *argv, uint64_t argc, uint8_t *user);
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

**A value C holds is a handle**: a `slate_value`, a typedef of `uint64_t`; 0 is never a handle. It
names a slot in a table the `slate_vm` keeps, and that table is walked by the collector, so a value
stays alive for exactly as long as C holds its handle — across any number of calls that collect, and C
can read `0` as "none".

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

## A host with a loop of its own

```c
void slate_set_manual_loop(slate_vm * h, int32_t manual);
int32_t slate_pump(slate_vm * h);
int32_t slate_run_until_idle(slate_vm * h);
int32_t slate_loop_fd(slate_vm * h);
int32_t slate_loop_timeout(slate_vm * h);
```

Every `slate_vm` has an event loop of its own, and there are two ways to turn it.

- **Slate turns it (the default)**, which is right for a script host: `slate_eval` and `slate_call`
  drain the loop before they return, so every timer a program armed has fired, every socket has
  closed and every `await` has settled by the time C sees the status.
- **The host turns it**, which is right for a GUI or a server with a main loop of its own:
  after `slate_set_manual_loop(vm, 1)`, `slate_eval` and `slate_call` run the program or the call to
  its first suspension and return with the rest still pending. `slate_eval` answers the status it
  always does. `slate_call` answers the value where it has one; for an `async` function still
  waiting it answers the promise itself, a handle `slate_kind` calls `8`. Read it later through a
  call to an `async` function that `await`s it. `slate_set_manual_loop(vm, 0)` puts the default back.

`slate_pump` runs one turn of the loop without waiting: the callbacks already due run, then what
they resumed. It answers `1` while work is still outstanding and `0` once the loop is idle. It
answers `-1` where a callback faulted or a promise rejected with nothing awaiting it, with
`slate_error` saying so. Each is reported once and the next pump carries on. It works in either
mode. Where C is content to wait, `slate_run_until_idle` does the whole drain in one call, as
`slate_eval` would have done, and answers `0` or `-1` the same way.

A host with a `poll`, `kqueue` or `epoll` loop adds `slate_loop_fd` to it and waits at most
`slate_loop_timeout` milliseconds, then pumps. The timeout is `-1` where only the descriptor can
wake the loop, as with a listening socket and no timer. It is `0` where something is due now, and
also where nothing at all is pending, which `slate_pump` answering `0` tells apart. `hello.c`'s last
section is the simplest form, a short sleep standing in for the poll:

```c
slate_set_manual_loop(vm, 1);
run(vm, "timer.sl", "setTimeout(() -> print(\"tick\"), 20)");

while (slate_pump(vm) == 1)
    usleep(2000);
```

Two handles never share a loop, so pumping one runs nothing of the other's. Pumping from inside a
host function is refused, the run that called the function being the one turning the loop.
`slate_free` closes whatever a manual-mode handle left pending.

A program that `await`s at its own top level is still settled before `slate_eval` returns, in
either mode: that is the rule that gives an imported file's exports before its importer reads
them.

## Building it

From the repository root, build the archive and the header:

```
sysl build-c . -o examples/embed/libslate.a --header examples/embed/slate.h
```

`build-c` prints the libraries the archive still needs — the ones `@link` named, and the packages'
`pkg_config` modules as a `pkg-config --libs …` line. Link `hello.c` with both:

```
cd examples/embed
clang hello.c -I. libslate.a -luv -llmdb -lnghttp2 -lssl -lcrypto -lsqlite3 -lm $(pkg-config --libs libbrotlidec libbrotlienc hiredis libuv libwebp lmdb libnghttp2 libcrypto libssl sqlite3 libzstd) -o hello
./hello
```

The archive is native objects, so any C toolchain links it — gcc or clang, GNU ld, lld or the macOS
linker — with nothing added to that line.

**A host that links with clang and lld and wants link-time optimisation across the boundary** can
build the bitcode form instead, with `sysl build-c . --lto thin -o libslate.a` (or `--lto full`).
`build-c` then adds a line to its advice saying how that archive links:

```
sysl: this archive is LLVM bitcode: link it with clang and lld (-fuse-ld=lld), or with a linker that carries LLVM's plugin
```

On macOS Apple's clang links it as it stands; elsewhere add `-fuse-ld=lld`, with an lld from the same
LLVM as sysl's. The release ships the native form.

**Each Linux release carries this already built**, as `libslate-<version>-linux-<arch>.tar.gz`: a
prefix holding `lib/libslate.a`, `include/slate.h`, `LINK.txt` (the two lines of advice above, as
`build-c` printed them) and `example/` (this file, `hello.c`, and `expected.txt`, what `hello`
prints). The libraries `LINK.txt` names come from the distribution's `-dev` packages.

`scripts/embed-check.sh` does all of that and checks what `hello` prints; the release runs it, and
`scripts/embed-check.sh --prefix <dir>` checks an unpacked tarball the same way.
