---
title: The runtime's state
weight: 20
---

# The runtime's state

slate's interpreter keeps its state in a `Vm` struct, and `current()` answers the one the running line
of execution belongs to. This page says why, what is in it, what is deliberately not, and how to move
the next file.

**The struct is now whole.** Every module-level `var` that was per-VM state has moved into `Vm`; what
is still process-wide is marked as such and stays where it is, and what is still missing is the
per-actor heap. It is here rather than under `reference/` because what it is *for* is the actors
design, and a VM with a heap of its own is the next piece of that work rather than a description of
the language.

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

**`the_vm` in `vm_state.sysl` is the one module-level `var` that remains by design.** Stage two makes
it a thread-local and `new_vm()` the thing an actor calls on its own thread; because every other file
goes through `current()`, that change lands in one file.

## What a module-level `var` is now

Four things, and `tests_vm_state.sysl` counts each of them:

| class | what it is | how it is recognised | count |
|---|---|---|---|
| the VM | `the_vm` in `vm_state.sysl` | by name | 1 |
| **B**, a native's id | `var n_<name>: NativeFn = 0` | by shape | 367 |
| **B/C**, process-wide | marked `process-wide:` in the comment above it | by the marker | 14 |
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

### Class C — genuinely shared, and it is the arena

- **`storage` and `slate_heap` in `obj.sysl`.** `storage` is a 256 MiB BSS array and `slate_heap` is
  the heap over it. The collector's root function needs an address, so the arena is module storage;
  a per-VM heap is `heap(base, cap)` taking a *different* block, which is exactly what the actors
  chapter asks for and is not this stage's work. **The heap's roots are already per-VM** —
  `root_values`, `root_envs`, the spares, the counters and `heap_limit` are all `Vm` fields — so the
  day a VM is spawned with a block of its own, the only thing left to move is the heap handle itself.

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
