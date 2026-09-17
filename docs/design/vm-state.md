---
title: The runtime's state
weight: 20
---

# The runtime's state

slate's interpreter keeps its state in a `Vm` struct, and `current()` answers the one the running line
of execution belongs to. This page says why, what is in it, what is deliberately not, and how to move
the next file.

**The struct is now whole and it owns its heap.** Every module-level `var` that was per-VM state has
moved into `Vm`, the arena moved in with it, and what is still process-wide is marked as such and
stays where it is. A second VM runs a program of its own in the same process today, which is what
`A_SECOND_VM_RUNS_A_PROGRAM_OF_ITS_OWN_IN_THE_SAME_PROCESS` in `tests_vm_state.sysl` says. It is here
rather than under `reference/` because what it is *for* is the actors design.

## Why

A module-level `var` is per-process storage. The runtime had 473 of them across fifty files, which is
**one interpreter to a process by construction**: two of them would have written over each other's
machine, heap roots, event loop, compiler tables and output. That forecloses two things at once —

- an **actor** on its own OS thread, which [the actors chapter](actors.md) describes as one `Machine`,
  one heap, one libuv loop and one collector per thread;
- an **embeddable** slate, a VM a sysl program holds as a value, which nobody has today because there
  is nothing to hold.

Gathering the state into a struct a thread owns is what makes both possible. It is also, on its own,
the piece of work that has to happen first, whichever of the two comes second.

## The struct and the accessor

`dev/slatelang/slate/vm_state.sysl` holds `struct Vm`, `new_vm()` and `current()`.

```
val v = current()

v.output.push(line)
```

`current()` answers a `*Vm`, so a caller writes through it. A function reaching one subsystem many
times takes a pointer to that subsystem once, which is why converting the instruction loop changed one
line and not a hundred and sixteen:

```
run_frames(u: *Unit, ...) -> Step
    val vm = machine()      // &current().machine
```

Every `vm.stack`, `vm.frames`, `vm.scope` below it is unchanged. `machine()` in `execute.sysl` and
`running_unit()` in `vm.sysl` are the two accessors of that shape; add one where a subsystem earns it.

**`the_vm` in `vm_state.sysl` is the one module-level `var` that remains by design**, and it is a
`*Vm` rather than a `Vm`: the thing `current()` answers is a pointer somebody can move. It becomes a
thread-local the day sysl has one, and because every other file goes through `current()`, that change
is a single declaration.

## Running a second VM

**`new_vm(ceiling)`, `enter`, `leave`, `dispose_vm` — and that is the whole of the surface.**

```
var second = new_vm(4194304)
val was = enter(&second)
val said = out("print(6 * 7)")

leave(was)
dispose_vm(&second)
```

- **`new_vm(ceiling)` `malloc`s a block of `ceiling` bytes and lays the VM's `gc.Heap` over it.**
  `gc.heap(base, cap)` has always taken the block it works over, so a second VM is a second `base`
  and nothing else. `malloc` rather than `calloc`, because `gc.alloc` zeroes each payload itself and
  untouched pages should stay uncommitted — which is the bargain the 256 MiB BSS array it replaced
  was making. The program's own VM asks for `HeapBytes`, so nothing about the default changed.
- **`dispose_vm` runs every outstanding finalizer and frees the block.** The finalizers touch no VM
  state — each gives back a sysl `string`, a `Buf` or a `Map` its object held — so a VM that is not
  the current one can be disposed safely.
- **`heap_ceiling` is the block and `heap_limit` is the setting.** `set_heap_limit` clamps to the
  VM's own ceiling, so a VM spawned with a megabyte runs out of *its* megabyte with the ordinary
  *"this program has run out of memory"* and the process's own VM never hears about it.

**`the_vm` IS `@thread_local`, so the pointer is per thread and two VMs run at once.** Every thread
reads its own copy, which is what makes `current()` answer the VM the *line of execution* belongs to
rather than the one the process last entered. `enter`/`leave` swap this thread's copy and are
otherwise untouched: the previous VM travels back through the caller rather than through a stack
here, so nesting on one thread works exactly as it did, and every `enter` still owes a `leave` on
every way out — which is why the runtime itself never calls these and a test or an embedder does.

**The initializer is `null` and `current()` reads that as the program's own VM.** A thread-local's
copies are stamped from one image in the object file rather than by code that runs per thread, so
the value has to be one the compiler can write down and the address of a module `var` is not one it
takes. `null` says the right thing anyway: a thread that has entered nothing belongs to the VM the
process runs its program on.

**A THREAD SETS UP ONE THING BESIDE ITS VM, AND IT IS A LOOP.** libuv's default loop belongs to the
process and may be turned by one thread at a time, so a VM that is going to run on a thread of its
own is built over a loop of its own:

```
val lp = libuv.new_loop().expect("a loop of this thread's own")
var mine = new_vm(4194304, lp)
val was = enter(&mine)

val said = out("setTimeout(() -> print(\"hello\"), 1)")

leave(was)
dispose_vm(&mine)
lp.close().expect("the thread's loop closes")
```

`Vm.uv_loop` is the field, `new_vm`'s second parameter defaults to `libuv.default_loop()` so the
program's own VM keeps the loop every handle in the process was already on, and `event_loop()` in
`event.sysl` is the accessor every site that starts a handle or turns the loop reads — timers, the
drain, TCP, pipes, signals and a spawned process. What still reaches `default_loop()` directly is
`sh.sysl.libuv`'s own synchronous file-system calls and the two calls whose loop parameter sits
behind other defaults, `resolve` and `queue`; a thread doing file, DNS or thread-pool work owes that
routing before it can be trusted.

Everything else in the tree learns nothing, because it already goes through `current()`.

## What a module-level `var` is now

Four things, and `tests_vm_state.sysl` counts each of them:

| class | what it is | how it is recognised | count |
|---|---|---|---|
| the VM | `the_vm` in `vm_state.sysl`, a `*Vm` | by name | 1 |
| **B**, a native's id | `var n_<name>: NativeFn = 0` | by shape | 367 |
| **B/C**, process-wide | marked `process-wide:` in the comment above it | by the marker | 13 |
| **A**, still owed | anything else | by elimination | 0 |

**A new global is none of the first three**, so it lands in the fourth and fails the census until its
file's number is raised — which is a decision somebody makes rather than an accident. The fourth is
zero now, and stays zero unless a file grows one back.

### Class B — process-wide, and why each one qualifies

- **The 367 `n_<name>: NativeFn` ids.** `register(name, go)` is append-only and answers the *first* id
  for a name it already holds, so an id never moves once handed out. Two VMs in one process would
  register the same names and agree on every id. `natives` and `native_ids` in `native_fn.sysl`, and
  `named_natives`/`named_natives_built` in `natives.sysl`, are the same fact: the table those ids index
  is immutable in the only sense that matters, which is that an existing entry never changes.
- **The eight `gc.Kind` tables in `obj.sysl`.** Each is a set of function addresses built at startup
  and never written again; a `Kind`'s address must not move, and a per-VM copy would hold the same
  eight function pointers.

### Class C — empty, and the arena is why

**There is no class C any more.** It held exactly two things — `storage`, a 256 MiB BSS array in
`obj.sysl`, and `slate_heap`, the one `gc.Heap` over it — and both are gone: `region`, `heap_ceiling`
and `heap` are `Vm` fields, and `slate_heap()` is a `*gc.Heap` accessor of the `machine()` shape, so
every allocation site reads `slate_heap()` where it read `&slate_heap` and nothing else moved.

**What the arena was doing in module storage was giving the collector's root function an address**,
and that is still the requirement: `roots` is a top-level function because a hook is reached by
address. It simply reaches the heap through `current()` now, so one function serves any number of
heaps — `gc.collect` hands it the heap it is collecting, which is `current().heap` because that is
what the caller asked for.

**The one thing that replaced them is `main_vm`**, the storage for the *program's own* VM, marked
process-wide for the plain reason that a process has one and it has to outlive everything, including
a `main` that has returned into a libuv callback. A second VM is an ordinary local somebody owns.

### Class A — none owed, and the two shapes the 49 turned out to be

Every file that owed a move -- `async.sysl`, `generator.sysl`, `runtime.sysl`, `check.sysl`,
`window.sysl`, `process.sysl`, `lmdb.sysl`, `nghttp2.sysl`, `sqlite.sysl`, `signals.sysl`,
`channel.sysl`, `spawn.sysl`, `define.sysl`, `regex.sysl`, `ast.sysl`, `gzip.sysl`, `argon2.sysl`,
`client.sysl`, `combine.sysl`, `http_parse.sysl`, `packages.sysl`, `pattern.sysl`, `redis_parse.sysl`,
`shape.sysl` and `tls.sysl` -- has made its move. `tests_vm_state.sysl`'s `StateOwed` is empty and
`StateOwedTotal` is `0`.

**`gzip.sysl`'s two needed a decision rather than a plain move, and it was decided this way**: the
compressor's `miniz.DEFLATE_BYTES` and the decompressor's `miniz.INFLATE_BYTES` (each a `sizeof` plus
its alignment, around 168 KB and 8 KB) are each a heap-allocated `Buf[u8]` (`current().deflate_state`,
`current().inflate_state`), not an inline array on `Vm` -- a struct field that size would be copied
every time a `Vm` is, and `new_vm()` allocates each once instead. Passed to
`miniz.deflate`/`miniz.inflate` as `.view()`, which is the slice the binding actually wants.

**`buf_with_capacity(n, fill)` was the wrong tool here and cost a red gate finding it out.** Its own
doc comment says why: *"a buffer that has already been given room for `n` elements"* is CAPACITY, not
LENGTH -- `count` starts at zero, matching `Vec::with_capacity`'s rule rather than a fill. miniz's
`deflate`/`inflate` check `storage.len < N`, so a capacity-only buffer answers `NoRoom` on the very
first call: `.len()` is 0 regardless of how large `n` was. `zeroed_scratch(n)` in `vm_state.sysl`
pushes `n` zero bytes one at a time instead, which is the one place `buf_with_capacity`'s name invites
exactly the mistake it does not do.

**Two things cost a rebuild each and are worth knowing before the next VM field:**

- **A type a new `Vm` field names must be at least as visible as the field.** `Vm` is public, so a
  field of type `Buf[Slot]` or `Buf[Option[&Argon2Job]]` forces `Slot`/`Argon2Job` (and anything
  *they* name, transitively -- `Slot.arrived: &Arrived` dragged `Arrived`, and `Arrived` dragged
  `Held` and `Piece`) out of `private`. The compiler catches every one of these by name --
  *"a declaration may not be more visible than the types it names"* -- so it costs a rebuild rather
  than a silent gap, but expect to walk a small tree of types outward from the field you are adding.
- **Type names are module-wide even where the declaration is `private`.** Two files each had their
  own `private struct Slot` (`http_parse.sysl`, `shape.sysl`) and a third had one too
  (`tls.sysl`'s table, then renamed): fine as long as both stay private, but the first one a field
  drags public collides with the compiler's *"type 'Slot' is already declared"* the moment a second
  file's `Slot` needs to travel the same way. `shape.sysl`'s became `ShapeSlot` and `tls.sysl`'s
  table field became `tls_slots` for this reason -- rename on the way out rather than after the
  collision.

**A field behind a feature is gated in `Vm` exactly as its file is.** `window.sysl` (`webview`),
`lmdb.sysl` (`lmdb`), `nghttp2.sysl` (`http2`) and `redis_parse.sysl` (`redis`) each declare types
that do not exist without their feature, so the corresponding `Vm` fields, the matching slice of
`new_vm()`'s constructor call, and any import those types need are each wrapped in the same
`#if feature_x` / `#endif` the source file uses -- `#if` gates a struct's field list and a
constructor's argument list exactly as it gates any other run of lines. Built and checked under both
`sysl build .` (all features) and `sysl build . --no-default-features`.

## How to move a file

1. Take the `var` out of its file. Leave a sentence in its place saying where it went — `x` is now
   `current().x` — because the prose beside a declaration is usually the best thing about it.
2. Put it in `Vm` under the group that names its subsystem, with the same comment.
3. Add it to `new_vm()`, **in field order**: the constructor is positional, so a field added in the
   middle of the struct goes in the middle of the call or the compiler says which type stopped
   matching.
4. Replace each read and write with `current().x`, or take `val v = current()` at the top of a function
   that touches several. Where a *subsystem* is reached many times, a `*T` accessor beside it —
   `machine()`, `running_unit()` — keeps the sites unchanged.
5. Lower the file's number in `tests_vm_state.sysl` by what you moved, and `StateOwedTotal` with it.

Two things the compiler will not tell you:

- **A local may shadow an accessor.** `val machine = park()` in `generator.sysl` had to be renamed
  before `machine()` could be called in the same function. Pick names that do not collide, and check
  before adding an accessor rather than after.
- **`unit` is a type in sysl**, which is why the unit accessor is `running_unit()` and not `unit()` —
  the refusal is *"a 'unit' conversion takes exactly one value"*, which does not read like a name
  collision.
