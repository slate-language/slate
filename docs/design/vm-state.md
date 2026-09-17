---
title: The runtime's state
weight: 20
---

# The runtime's state

slate's interpreter keeps its state in a `Vm` struct, and `current()` answers the one the running line
of execution belongs to. This page says why, what is in it, what is deliberately not, and how to move
the next file.

**This one is half built, unlike its neighbours.** The struct, the accessor and the core of the
runtime are on `dev`; the forty-nine declarations listed below are not, and neither is the per-actor
heap. It is here rather than under `reference/` because what it is *for* is the actors design, and the
list of what is left is the next piece of that work rather than a description of the language.

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
| **A**, still owed | anything else | by elimination | 49 |

**A new global is none of the first three**, so it lands in the fourth and fails the census until its
file's number is raised — which is a decision somebody makes rather than an accident.

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

### Class A — the 49 still owed

`tests_vm_state.sysl` carries the list as `file count`. In rough order of how obviously per-VM they
are: `async.sysl` 4 (the ready queue and the rejection list), `generator.sysl` 2, `runtime.sysl` 1
(`current_source`), `check.sysl` 2 (the checker's view of the builtin scope), `window.sysl` 4,
`process.sysl` 4, `lmdb.sysl` 4, `nghttp2.sysl` 3, `sqlite.sysl` 2, `signals.sysl` 2, `channel.sysl` 2,
`define.sysl` 2, `regex.sysl` 2, `ast.sysl` 2, `gzip.sysl` 2, and one each in `argon2.sysl`,
`client.sysl`, `combine.sysl`, `http_parse.sysl`, `packages.sysl`, `pattern.sysl`, `redis_parse.sysl`,
`shape.sysl`, `spawn.sysl`, `time.sysl` and `tls.sysl`.

**`gzip.sysl`'s two are the one shape that needs a decision rather than a move**: they are fixed-size
`u8` arrays of miniz scratch, so whether `Vm` carries them or points at them is a question about how
big a VM is allowed to be, and the answer belongs with the per-actor heap ceiling.

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
