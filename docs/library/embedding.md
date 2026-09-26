---
title: Embedding
weight: 230
---

# Embedding

slate inside a C program: the interpreter as a static archive with a header, so a program with a
`main` of its own can run slate programs, call the functions they define, and hand them C functions
to call back.

## The archive and the header

One command builds both, from a clone of slate:

```sh
sysl build-c . -o libslate.a
```

It writes `libslate.a` and, beside it, the header `libslate.a.h` (`--header <path>` puts the header
somewhere else). It also prints, on standard error, the
libraries the archive still needs — the ones an `@link` names, and the ones slate's packages find
through pkg-config:

```text
sysl: link this against: uv, lmdb, nghttp2, ssl, crypto, sqlite3, m
sysl: and against what the packages require, which pkg-config answers for: pkg-config --libs libbrotlidec libbrotlienc hiredis libuv libwebp lmdb libnghttp2 libcrypto libssl sqlite3 libzstd
```

Link against exactly those, each `@link` name as a `-l` and the pkg-config modules through
`pkg-config`:

```sh
clang main.c -I. libslate.a -luv -llmdb -lnghttp2 -lssl -lcrypto -lsqlite3 -lm $(pkg-config --libs libbrotlidec libbrotlienc hiredis libuv libwebp lmdb libnghttp2 libcrypto libssl sqlite3 libzstd) -o main
```

The lists above are those of a build with every default feature on; read them off your own build
rather than off this page, since a build with fewer features names fewer libraries.

The archive is native objects, so any C toolchain links it: gcc or clang, with GNU ld, lld or the
macOS linker, and nothing added to the line above. A host that links with clang and lld and wants
link-time optimisation across the boundary can ask for the bitcode form with
`sysl build-c . --lto thin -o libslate.a` (or `--lto full`); `build-c` then also prints
`sysl: this archive is LLVM bitcode: link it with clang and lld (-fuse-ld=lld), or with a linker that carries LLVM's plugin`,
and that link takes `-fuse-ld=lld` (Apple's clang links it without).
`examples/embed/` in the repository is a whole program built this way, and
`scripts/embed-check.sh` builds, links and runs it.

## The smallest program

```c
#include <stdio.h>
#include <string.h>

#include "libslate.a.h"

int main(void) {
    slate_vm *vm = slate_new(0);
    const char *program = "print(\"hello\")";

    int32_t status = slate_eval(vm, (uint8_t *)program, strlen(program), (uint8_t *)"hello.sl", 8);

    if (slate_error_len(vm) > 0)
        fprintf(stderr, "%s\n", slate_error(vm));

    slate_free(vm);
    return status;
}
```

The program it runs is an ordinary slate program, and prints what it would print from a file:

```slate
print("hello")
```

```output
hello
```

```c
uint8_t * slate_version(void);
slate_vm * slate_new(uint64_t heap_bytes);
void slate_free(slate_vm * h);
int32_t slate_eval(slate_vm * h, uint8_t * text, uint64_t len, uint8_t * name, uint64_t name_len);
uint8_t * slate_error(slate_vm * h);
uint64_t slate_error_len(slate_vm * h);
```

- `slate_version` is what `slate --version` answers, NUL-terminated, good for the life of the process.
- `slate_new` makes an interpreter with a heap and an event loop of its own. `heap_bytes` of `0`
  takes the size `slate` itself uses. It answers null where 64 handles are already live.
- `slate_free` gives everything back — the heap, with every finalizer run, and the loop. A pointer
  it never handed out, or one already freed, is ignored.
- `slate_eval` takes the program as a pointer and a length, and `name` is what a diagnostic quotes as
  the file. It answers `0` where the program ran to the end, what it passed to `exit`, or `1` where
  slate refused it or it faulted.

## The session

**Every `slate_eval` on one handle runs in one session**, as a REPL does, or Lua's `luaL_dostring`
on one state: what an earlier call bound at its top level — a function, a `val`, a class, an import —
a later call can use, and what the later call binds joins it. So a C program that evaluates

```slate
double(n) = n * 2
```

and then, in a second call,

```slate
print(double(21))
```

gets the same answer the two written as one file get:

```slate
double(n) = n * 2
print(double(21))
```

```output
42
```

- **A call slate refuses changes nothing.** Its diagnostic is in `slate_error`, and the session is as
  it was before the call.
- **A call that faults keeps what it bound before the fault.**
- **Two handles share nothing.** A name bound on one is not defined on the other.
- **`slate_error` is the last call's diagnostic**, NUL-terminated, and `slate_error_len` its length.
  It is empty where the call ran, and the pointer is good until the next call on the handle.
  Diagnostics never go anywhere else.
- **What a program prints goes to standard output as it prints it**, exactly as `slate <file>` would
  — unless the handle has an output function (below). A C program that also prints should `fflush`
  its own output before each call, or the two come out of order.

## Values

A value C holds is a **handle**: a `slate_value`, a typedef of `uint64_t`; 0 is never a handle. It
names a slot in a table the interpreter keeps. The collector walks that table, so a value stays alive
for exactly as long as C holds its handle, across any number of calls that collect, and C can read
`0` as "none".

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
```

```c
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
```

- **Every handle is yours until `slate_release`**, including the new ones `slate_at`, `slate_get`,
  `slate_global` and `slate_call` answer. A released slot is taken by the next value made, so a host
  that releases what it is done with holds a table no bigger than it ever needed. `slate_free` gives
  the whole table back.
- **A handle belongs to the `slate_vm` that made it.** Handed to another, it names whatever that one
  keeps at the same slot, and nothing can tell the difference — as with a pointer.
- `slate_string` copies its bytes. `slate_string_ptr` points at the string's own UTF-8 bytes, **not
  terminated**, `slate_string_len` of them, good for as long as the handle is held: a slate string
  never changes and the heap never moves an object. Anything that is not a string answers an empty one.
- `slate_to_int` truncates a real toward zero and answers `0` for anything else; `slate_to_real`
  converts an integer and answers `0.0` for anything else; `slate_to_bool` is slate's truthiness, so
  `0`, `""` and `null` are `0`.
- `slate_push` and `slate_set` answer `0`, or `1` where the target is not an array or an object, is
  frozen, or the value is not a live handle.
- `slate_get` answers `0` for a key the object does not have.
- `slate_show` is the value as `print` writes it, NUL-terminated, in one buffer per handle that the
  next `slate_show` replaces; `slate_show_len` is its length.

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
| `7` | a function — a builtin and a host function included |
| `8` | anything else |
| `-1` | `0`, or a handle already released |

## Calling slate from C

```c
slate_value slate_global(slate_vm * h, uint8_t * name, uint64_t name_len);
int32_t slate_call(slate_vm * h, slate_value f, slate_value * argv, uint64_t argc, slate_value * out);
```

`slate_global` answers a handle to what a top-level name of the session holds — something a
`slate_eval` defined, or a builtin — and `0` where nothing by that name is defined.

`slate_call` calls `f` with `argc` handles from `argv`, writes a handle to the answer at `out`, and
answers `0`. Where the call faults, or `f` is not something that can be called, it answers `1`,
leaves `*out` as `0`, and `slate_error` has the diagnostic, naming the file and line the fault
happened at.

```c
slate_value twice = slate_global(vm, (uint8_t *)"double", 6);
slate_value args[] = { slate_int(vm, 21) };
slate_value answer = 0;

if (slate_call(vm, twice, args, 1, &answer) == 0)
    printf("%lld\n", (long long)slate_to_int(vm, answer));

slate_release(vm, answer);
slate_release(vm, args[0]);
slate_release(vm, twice);
```

**An `async` function is run to its answer.** In the default loop mode `slate_call` goes through
every `await`, then drains the loop as it is drained after a program, so what C reads at `out` is the
value the function returned and never a promise.

## Calling C from slate

```c
int32_t slate_register(slate_vm * h, uint8_t * name, uint64_t name_len, slate_value (*f)(slate_vm *, slate_value *, uint64_t, uint8_t *), uint8_t * user);
void slate_on_output(slate_vm * h, void (*f)(uint8_t *, uint64_t, uint8_t *), uint8_t * user);
```

The header spells the two callbacks as raw function-pointer types. Named, they are

```c
typedef slate_value (*slate_host_fn)(slate_vm *vm, slate_value *argv, uint64_t argc, uint8_t *user);
typedef void (*slate_output_fn)(uint8_t *bytes, uint64_t len, uint8_t *user);
```

`slate_register` binds `name` at the session's top level to a C function, so every later program on
that handle — and no other — can call it like any function. It answers `0`, or `1` with `slate_error`
set where `name` is not a name a program could write, or `f` is null.

```c
static slate_value host_add(slate_vm *vm, slate_value *argv, uint64_t argc, uint8_t *user) {
    int64_t sum = 0;

    for (uint64_t i = 0; i < argc; i++)
        sum += slate_to_int(vm, argv[i]);

    return slate_int(vm, sum);
}

slate_register(vm, (uint8_t *)"host_add", 8, host_add, NULL);
```

after which a program on `vm` may write `print(host_add(40, 2))`.

- **It is handed a handle per argument, as many as the call wrote.** A C function declares no count
  and slate's calls are JavaScript's, so nothing is refused for being too few or too many. The
  argument handles are slate's: read them, and do not release them.
- **It answers a handle, or `0` for `null`.** slate takes the handle over, reads the value and
  releases the slot, so answer one you just made or one of the arguments. A handle already released
  faults in the calling program, with a sentence naming the host function.
- **Registering a name again replaces it**, as Lua's `lua_register` does; a value a program already
  took keeps calling the function it was.
- **It may call back into slate.** `slate_call` from inside a host function runs on the machine
  already running, so C → slate → C → slate works to any depth. `slate_eval` there is refused, a
  program being a whole run of its own, and so is `slate_pump`.
- A host function prints as `<host name>`, and `slate_kind` calls it `7`. `user` is whatever was
  handed to `slate_register`, untouched.

`slate_on_output` sends every line a program on that handle prints to `f`, without the newline,
with the `user` pointer beside it — from `slate_eval` and from a function `slate_call` runs alike —
instead of to standard output. The bytes are good for the length of the call. `f` null puts standard
output back.

## The event loop

```c
void slate_set_manual_loop(slate_vm * h, int32_t manual);
int32_t slate_pump(slate_vm * h);
int32_t slate_run_until_idle(slate_vm * h);
int32_t slate_loop_fd(slate_vm * h);
int32_t slate_loop_timeout(slate_vm * h);
```

Every handle has an event loop of its own, and there are two ways to turn it.

- **slate turns it — the default, and right for a script host.** `slate_eval` and `slate_call` drain
  the loop before they return, so every timer a program armed has fired, every socket has closed and
  every `await` has settled by the time C sees the status.
- **The host turns it — right for a GUI or a server with a main loop of its own.** After
  `slate_set_manual_loop(vm, 1)`, `slate_eval` and `slate_call` run to the first suspension and
  return with the rest still pending. `slate_eval` answers the status it always does; `slate_call`
  answers the value where it has one, and for an `async` function still waiting, the promise itself —
  a handle `slate_kind` calls `8`. `slate_set_manual_loop(vm, 0)` puts the default back. The change
  takes effect at the next call, and what is already pending stays pending.

`slate_pump` runs one turn of the loop without waiting: the callbacks already due, then what they
resumed. It answers `1` while work is still outstanding, `0` once the loop is idle, and `-1` where a
callback faulted or a promise was rejected with nothing awaiting it, with `slate_error` saying so —
each reported once, the next pump carrying on. It works in either mode. `slate_run_until_idle` is the
whole drain in one call, as `slate_eval` would have done it, and answers `0` or `-1` the same way.

A host with a `poll`, `kqueue` or `epoll` loop adds `slate_loop_fd` to it, waits at most
`slate_loop_timeout` milliseconds, then pumps. The timeout is `-1` where only the descriptor can wake
the loop, as with a listening socket and no timer, and `0` where something is due now — and also where
nothing at all is pending, which `slate_pump` answering `0` tells apart.

```c
slate_set_manual_loop(vm, 1);
slate_eval(vm, (uint8_t *)program, strlen(program), (uint8_t *)"timer.sl", 8);

while (slate_pump(vm) == 1)
    usleep(2000);
```

Here a short sleep stands in for the `poll`.

- **Two handles never share a loop**, so pumping one runs nothing of the other's.
- **`slate_free` closes whatever a manual-mode handle left pending.**
- **A program that `await`s at its own top level is still settled before `slate_eval` returns**, in
  either mode — the rule that gives an imported file's exports before its importer reads them.

## Limits

- **64 handles may be live in one process.** `slate_new` answers null past that; a freed handle's
  slot is taken again.
- **One call at a time on a handle.** Each call enters the handle's interpreter and leaves it, so two
  threads may each drive a handle of their own, but calls on ONE handle from several threads at once
  are not allowed — serialise them in C.
- **Building the archive needs sysl 0.0.141 or later**, the compiler slate 0.1.11 is built with.
