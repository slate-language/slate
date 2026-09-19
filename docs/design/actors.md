---
title: Actors
weight: 10
---

# Actors

**Built: the native back end.** `slate:actor` and the `actor` declaration are in the interpreter; the
JavaScript half below is not, and a program that declares an actor is refused by `slate js` where it is
written. [`docs/library/actor.md`](../library/actor.md) is the page a program is written against and
carries the runnable programs; the blocks here stay untagged, this page being the argument rather than
the surface.

**An actor is a thread with a whole slate runtime on it**: its own machine, its own heap, its own
event loop and its own collector. Nothing is shared. Two actors cannot see one object between them,
so there is no lock to take, no value to tear, and no rule about which thread may touch what. What
crosses between them is messages, and a message is **copied**.

The program's own body is the first actor. `spawn` makes another, `send` posts a message nobody waits
for, and `ask` posts one and answers a promise — the same promise every other part of slate answers,
awaited in the same `await`.

This is not JavaScript's arrangement and does not try to be. A browser worker is a second *program*
in a second file, reached by a string-keyed `postMessage` and `onmessage`; here a worker is a
declaration in this file, its messages are named, and the answer comes back where it was asked for.

```
import { spawn, send, ask } from slate:actor

actor Counter
    var n = 0

    on bump(self, by = 1)
        self.n += by

    on total(self) = self.n

val c = spawn(Counter)

send(c.bump, 2)
send(c.bump)

print(await ask(c.total))       // 3
```

Four workers, asked at once, gathered with the `all` every other promise is gathered with:

```
actor Squarer
    on square(self, n) = n * n

val workers = [spawn(Squarer), spawn(Squarer), spawn(Squarer), spawn(Squarer)]
val answers = await all(workers.map((w, i) -> ask(w.square, i + 1)))

print(answers)                  // [1, 4, 9, 16]
```

That is the whole surface. The rest of this page is what each word means.

## Declaring one

**An `actor` body is a [class](../reference/classes.md) body with `on` in front of the handlers**, and
that similarity is deliberate: state is `val` and `var` fields, a handler is written in the ordinary
definition syntax, and the generated constructor takes every field — so `spawn(Worker, 7)` is
`Worker.new(7)` run on the new thread.

```
actor Ledger
    var name
    var entries = []

    on record(self, amount, note)
        self.entries.push({ amount: amount, note: note })

    on total(self) = self.entries.reduce((sum, e) -> sum + e.amount, 0)

    on report(self) = s"${self.name}: ${self.entries.length} entries"
end Ledger

val l = spawn(Ledger, "petty cash")
```

**A handler takes `self` exactly as a method does**, because that is how slate spells a receiver
everywhere else, and one rule read twice is cheaper than two rules. The caller never passes it:
`send(l.record, 5, "stamps")` binds `amount` and `note`.

**A handler may be `async`**, and then the answer to an `ask` is what its promise settles to. It may
`await`, `spawn` actors of its own, `send` to them, and reach its own state — it is an ordinary slate
function running on an ordinary slate loop, which happens to be nobody else's.

**An actor is declared at the top level of a file**, as a class and a `type` are. That is not a
restriction invented here; it is what makes the whole design sound. A body written at the top level
closes over nothing, so there is nothing of the spawner's for it to reach.

**The alternative was `spawn(fn)` with a `receive` inside it**, which is Erlang's shape and reads
shorter. It is refused for the sentence above: a lambda handed to `spawn` would capture its enclosing
scope, and those names live on another heap. Every such program would have to be refused anyway —
*a function handed to `spawn` may not capture `total`, which belongs to another actor's heap* — so
the declaration form is the one that never has to say it.

**`self` is taken by the receiver, so an actor's own handle is `me()`**, answered inside a handler and
nowhere else. It is how an actor hands its address to somebody:

```
actor Worker
    on start(self, boss)
        send(boss.enrol, me())
```

## Spawning, sending, asking, stopping

**`spawn`, `send`, `ask`, `done`, `stop`, `detach`, `me` and `transfer` are functions of
`slate:actor`, not methods of a handle.** A handle's field namespace belongs entirely to the program:
`a.stop` is the handler the program wrote called `stop`, and nothing built in can collide with a name
somebody chose.

**Reading a handler off a handle answers a `message`, which is a value.** `c.total` sends nothing and
asks nothing; it names an actor and one of its handlers. `send` and `ask` are the two things that can
be done with one — and because a message is an ordinary value, it can itself be sent, which is how a
reply address travels.

| | |
|---|---|
| `spawn(A, args…)` | start an actor, answer its handle |
| `spawn(A, args…, options)` | …with `{ heap, mailbox, name }` |
| `send(m, args…)` | post; answers nothing; never waits |
| `ask(m, args…)` | post; answer a promise of what the handler answers |
| `done(a)` | a promise that settles when the actor has stopped |
| `stop(a)` | ask it to stop once its mailbox is empty |
| `detach(a)` | this actor is no longer waited for at the end of the program |
| `me()` | inside a handler: this actor's own handle |

**A handler's return value *is* the answer to an `ask`.** A synchronous handler answers it, an `async`
one resolves it. A `send` runs the same handler and throws the answer away, which is why one handler
serves both and there is no second declaration for a message that happens to answer.

**`ask` is a promise like any other.** It composes with `all`, `race`, `any` and `allSettled`, it can be
held and awaited three lines later, and a fault inside the handler arrives as a rejection at the
`await`, following the [asynchrony](../reference/asynchrony.md) rules exactly.

### Identity and addressing

**A handle is a value and compares by identity**, as a promise, a function and a socket already do.
Copying it — into an array, into an object, into a message to a third actor — copies a reference to
one actor, and `==` is true of every copy. There is no registry and no name service: an actor is
reachable by whoever was given its handle.

**A dead actor's handle is still a value.** It prints, it compares, it can be stored. What it cannot
do is deliver: `ask` on it rejects and `send` on it is dropped.

### Ordering and delivery

**Per sender, in order. Between senders, no order at all.** Two `send`s from one actor arrive in the
order they were written; a `send` from A and a `send` from B race, and nothing about the arrangement
could make them not.

**At most once, in process.** A message is either put in the mailbox or its `ask` is rejected; nothing
is retried and nothing is duplicated. Delivery over a network is a different problem with different
answers, and is not what this is.

## What crosses, and how

**A message is serialised out of the sender's heap and rebuilt in the receiver's.** The sender's
values are untouched, and the receiver's are new. Mutating what arrived changes nothing anywhere else,
which is the whole bargain: no shared object means no rule about sharing one.

| what was sent | what arrives |
|---|---|
| integer, real, boolean, `null` | itself |
| string | a copy, in the receiver's heap |
| array | a new array, its elements copied by these rules |
| object | a new object, keys in the same order |
| a class instance | an instance of the same class, its fields copied |
| a data variant | the same variant, its fields copied |
| `Set`, `Map` | rebuilt, insertion order kept |
| a date, time, duration, zone or period | itself; a zone travels as its IANA name |
| a regex | rebuilt from its pattern and flags |
| an actor handle, a message | itself — it names an actor, not memory |
| a shared structure | shared structure: two fields holding one object arrive holding one object |
| a cycle | a cycle |

**A class instance crosses as an instance and not as a plain object**, because both actors are running
the same program: a class is identified by the file that declares it and the name it was declared
under, and the receiver looks it up and rebuilds. This is the one place the design leans on actors
being copies of one program, and it is what makes a domain type usable as a message rather than
something to flatten by hand at every boundary.

**`undefined` raises no question**, slate [refusing to store it anywhere](../reference/values.md): it
cannot be in an array, a field or a variable, so it cannot be in a message.

### What does not cross

**Anything holding a resource the other thread has no business touching is refused, and the refusal
names the field it found.** Not the message, not the type — the field, because a message ten fields
deep is exactly where this happens.

```
a message may not carry a function: `handlers.onDone` is a function, and a
function belongs to the heap it was made on
```

The set is functions and lambdas, promises, generators, sockets, servers, child processes, channels,
external values, weak maps and weak references, LMDB handles, and windows. Each has its own sentence
naming what it is. A **promise** is the one worth saying twice: it is not a value in flight, it is a
suspended call on one machine's parked list, and there is nothing to copy.

**Bytes have something to transfer now.** A [`bytes`](../library/bytes.md) buffer is a run of raw bytes
that holds no values at all, so it is the one container whose storage can move between heaps whole:
`transfer(b)` detaches the sender's buffer and hands the receiver the storage itself, at no copy.
Without a byte-buffer kind there was nothing to move — a megabyte of bytes was a megabyte of separate
values, and every one of them had to be copied.

## Failure

**An actor that faults dies.** There is no supervisor built in and no restart: a fault that reaches
the top of a handler stops that actor, exactly as an unhandled fault stops a program.

When it dies, all at once:

- **every pending `ask` rejects with the fault**, so a caller awaiting an answer learns what happened
  rather than waiting for ever;
- **`done(a)` settles with the fault**, which is how a third party watching learns;
- **every later `send` is dropped**, and every later `ask` rejects at once with *the actor is not
  running*.

**The fault crosses as a value the same way a message does**, so the file, the line and the message
survive; what does not survive is a fault carrying an unsendable field, which arrives with that field
replaced and a note saying so.

**Supervision is a library on top of `done`**, and deliberately not part of this. A supervisor is a
loop that awaits `done`, decides whether to spawn again, and counts restarts against a window — a page
of slate, written in slate, with policy in it that nobody should have to take from the language.

**`stop(a)` is orderly**: the actor takes no new messages, drains the ones it has, runs its loop down,
and settles `done`. **A message in flight when an actor stops is dropped** — its `ask` rejects with
*the actor stopped before it answered this*, which is a sentence a caller can act on, where silence is
not.

**The program ends when the first actor's loop has drained and every actor it spawned, transitively,
has stopped.** An actor is a live handle on the program in the way an open socket is. `detach(a)` opts
one out of that count, for a logger or a metrics sink that would otherwise hold the program open for
ever. Ctrl-C stops all of them.

## The runtime

**One OS thread per actor, and on it a whole runtime.** slate's interpreter is a `Machine`, a heap, a
libuv loop and a collector; an actor is one of each. `sh.sysl.gc`'s `heap(base, cap)` already takes the
block it works over, so a per-actor heap ceiling is the `cap` that actor was spawned with, and a
finalizer is a `Kind`'s `finalize` on that heap, running on that thread.

**The prerequisite is met.** The runtime's state is a `Vm` struct a thread owns, the pointer
`current()` answers is `@thread_local`, and a VM is built over a libuv loop of its own — so two VMs
already run at once on two threads, each on its own heap and its own loop, which
`TWO_VMS_RUN_ON_TWO_THREADS_AT_ONCE_EACH_ON_ITS_OWN_HEAP_AND_LOOP` in `tests_vm_state.sysl` pins.
`docs/design/vm-state.md` is that design and says what a thread sets up. It buys a second thing on
its own: a slate VM that a sysl program can hold is an **embeddable** library, which is a use nobody
had while there was nothing to hold.

**An actor's VM instantiates every module the program imports, and runs the ENTRY file's DECLARATIONS
alone.** An imported module's whole top level runs there, exactly as importing it runs it in the main
program — so an ordinary library works in a handler, and **each actor has its own copy of every
module's state**. A file's top level is declarations and effects — a definition, a `class`, a `data`, a
`type`, an `external` and an `import` are the first, and everything else is the second — and
`compile_module` emits a second chunk holding the declarations alone, which is the chunk the entry file
takes. That is what stops the program's own effects running again on every thread: the entry file is
where the spawning and the printing are written. It is also what makes a class instance able to cross:
the receiver looks the class up by the name it was declared under, and it is there because the file
that declared it was loaded.

**The program a person runs is untouched**, which is the constraint that decided the shape: the module's
own chunk is compiled and run statement for statement as it always was, and the declarations chunk is a
second compilation beside it. Cutting the declarations *out* of the one chunk would have run them ahead
of the file's effects, and two of slate's rules say otherwise — an `import` binds where it is written,
and a class field's initialiser is worked out where the class stands.

The consequence a program can see is that a **top-level `val` of the ENTRY file is not bound in an
actor's VM**. A method that names one is an ordinary program in an ordinary run — the name is looked up
when the method is called — and reaching it inside an actor faults with a sentence saying that the entry
file's top level is not run there and where the value belongs instead. A **declaration that is built out
of** such a name is the sharper case and is refused outright when the declarations are loaded. A
**`spawn` at a module's top level** is refused too, naming the module: the actor it started would run
that module, which would spawn again, without end. An actor's state belongs in its own fields, which is
what the declaration form already says; `docs/reference/modules.md` is where a reader meets the rule.

**The compiled chunks are shared rather than compiled again.** A `Unit` — bytecode, string table,
patterns, the module list — is written once by the compiler and read-only afterwards, so an actor is
handed the pointer. What is per-VM is everything running makes: the scopes, the module values and the
objects on the heap.

**The transport exists already.** `sh.sysl.libuv` 0.1.6 has `thread`, `join`, a `Mutex`, and an
`Async` whose `Waker` is the one libuv call safe from any thread — with a test carrying a hundred
messages through exactly that arrangement. A mailbox is that shape: an unbounded intrusive list of
`&sync` message boxes under a mutex, and a `send` that appends and wakes.

- **`Async.send` coalesces**, so the callback's job is to drain whatever is there rather than to be
  counted. One wake-up, one drain, however many messages arrived.
- **`send` never blocks the sender's loop.** It takes a mutex over a list append and lets it go. There
  is no bounded queue to wait on, because a server that stalls its own event loop waiting for a slow
  actor has stopped serving everybody else.
- **A soft mailbox limit turns overflow into a refusal, never into a wait**: past it, `ask` rejects
  and `send` faults in the sender. An actor sets its own at spawn.
- **sysl refuses a `Buf` inside a `&sync` struct, and that refusal is right** — a growable collection
  owns its elements through a count that is not atomic. Whether sysl should grow a *sendable* property,
  so that what may cross a thread is a thing the compiler checks rather than a rule this design keeps,
  is a sysl design question and is listed below.

### The JavaScript back end

**Built, and the same programs run on both back ends.** [`docs/library/actor.md`](../library/actor.md)'s
*Under JavaScript* section is what a reader is told; what follows is why it is shaped as it is.

**An actor is a worker and a message is `postMessage`.** A browser's `Worker` and node's
`worker_threads` agree on the part that matters: one thread, one heap, structured clone between them.

- **`slate js` emits one bundle that plays both roles.** The worker file is not a second program: it is
  this program, started with its entry replaced by the handler dispatch, which is what
  `slate:cluster`'s workers already do one layer up.
- **`ask` is a request id and a promise**, kept in a table on the sending side and settled when a
  message carrying that id comes back. That is the same arrangement the interpreter's mailbox uses,
  because it is the only one there is.
- **Buffers are transferables.** `transfer(xs)` maps onto `postMessage`'s transfer list exactly, which
  is the reason to spell it now even though the value it wants does not exist yet.
- **Structured clone's unsendable set is not slate's**, and the difference is documented rather than
  papered over: it takes some things slate refuses and refuses some slate takes. Class instances are
  the sharp case — structured clone drops the prototype and hands over a plain object — so the runtime
  tags and rebuilds them itself rather than leaning on the host, which is what keeps the two back ends
  saying the same thing about a domain type in a message.
- **So a message is ENCODED before it is cloned, and that is the decision the built version turns on.**
  The copy rules above are slate's own on both back ends — the seen table that keeps shared structure
  and cycles, the name a class instance is rebuilt against, and every refusal naming the field it
  found — and what the host clones is the encoded form. A byte buffer is the one value handed to the
  host as itself, `transfer` being the transfer list exactly.
- **A worker has ONE port, to whoever started it, so worker-to-worker traffic relays through the main
  thread.** Direct ports are a `MessageChannel` per pair and a handshake to set each one up; the relay
  costs a hop and keeps every ordering guarantee, since what the design promises is per SENDER.

## What actors are not for

**They are not `slate:cluster`, and the two solve different halves of one problem.** A
[cluster](../library/cluster.md) is *processes*: one copy of the program per core, a supervisor in
front, the connections spread by the supervisor or by `SO_REUSEPORT`, and a worker that dies taking
nothing with it. That is the answer for a **server**, where the work is already separated by
connection and the isolation of a process is worth having. Actors are threads inside one process, for
work that is one program's: a computation to fan out, a long job that must not stall the loop, a
component that owns a piece of state and answers questions about it. A server may well use both.

**They are not a replacement for `async`.** A plain [`async` function](../reference/asynchrony.md) on
one loop is concurrency without parallelism: it interleaves waiting, it costs no copy, and it shares
every object it can see. Reach for an actor when the work is **CPU** — when what you want is a second
core, not a second thing to wait on — and for nothing else. An actor for a job that is entirely I/O
buys a thread, a heap and a copy per message in exchange for nothing.

## Limits

- **A heap ceiling per actor**, passed at spawn. An actor that outgrows it faults; it does not take
  the process with it.
- **A mailbox soft limit**, which becomes a refusal and never a wait.
- **A thread per actor means tens to thousands, not millions.** This is not Erlang: a thread costs a
  stack and a scheduler slot, and a program spawning a million of them is asking the wrong question.
  M:N scheduling — many actors over a pool of threads — is a later change that fits **behind this same
  surface**, because nothing here says an actor *is* a thread except this paragraph.

## Open questions

- **A byte-buffer type.** Bytes are an array of integers today, so `transfer` has nothing to transfer
  and a large payload is a large copy. This is the one question that blocks a piece of the design
  rather than extending it.
- **A `sendable` property in sysl.** `&sync` refuses a `Buf` for a good reason; what is missing is a
  way to *say* what may cross, so that the mailbox's rule is checked rather than kept.
- **`select` over several asks** — waiting for whichever of a set answers first, with the rest still
  outstanding. `race` answers half of it and abandons the others, which is not the same thing.
- **A timeout on `ask`.** Every distributed system grows one; whether it belongs on the call, on the
  actor, or in a library over `race` is a decision to take once.
- **Whether `stop` should be forcible.** Today an actor that will not drain holds the program open,
  and the only honest alternative — killing a thread mid-statement — is one no runtime does safely.
