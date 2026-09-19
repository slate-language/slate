---
title: "slate:actor"
weight: 76
---

# `slate:actor`

An actor is a thread with a whole slate runtime on it, and a message between two of them is copied.

Its own machine, its own heap, its own event loop and its own collector. Nothing is shared, so there is
no lock to take, no value to tear and no rule about which thread may touch what. Reach for one when the
work is **CPU** — a computation to fan out, a long job that must not stall the loop, a component that
owns a piece of state and answers questions about it. An actor for a job that is entirely I/O buys a
thread, a heap and a copy per message in exchange for nothing; that is what [`async`](../reference/asynchrony.md)
is for.

**It runs on both back ends.** Under the interpreter an actor is an OS thread with a whole slate
runtime on it; under `slate js` it is a worker, and [*Under JavaScript*](#under-javascript) below is
what differs.

```slate
import { spawn, send, ask } from slate:actor

actor Counter
    var n = 0

    on bump(self, by = 1)
        self.n += by

    on total(self) = self.n

val c = spawn(Counter)

send(c.bump, 2)
send(c.bump)

print(await ask(c.total))
```

```output
3
```

Four workers, asked at once, gathered with the `all` every other promise is gathered with:

```slate
import { spawn, ask } from slate:actor

actor Squarer
    on square(self, n) = n * n

val workers = [spawn(Squarer), spawn(Squarer), spawn(Squarer), spawn(Squarer)]

print(await all(workers.map((w, i) -> ask(w.square, i + 1))))
```

```output
[1, 4, 9, 16]
```

## Declaring one

**An `actor` body is a [class](../reference/classes.md) body with `on` in front of the handlers.** State
is `val` and `var` fields, a handler is written in the ordinary definition syntax, and the generated
constructor takes every field — so `spawn(Worker, 7)` is `Worker.new(7)` run on the new thread.

**A handler takes `self` exactly as a method does.** The caller never passes it: `send(l.record, 5,
"stamps")` binds the two parameters after it. **A handler may be `async`**, and then the answer to an
`ask` is what its promise settles to.

```slate
import { spawn, send, ask } from slate:actor

actor Ledger
    var name
    var entries = []

    on record(self, amount, note)
        self.entries.push({ amount: amount, note: note })

    on total(self) = self.entries.reduce((sum, e) -> sum + e.amount, 0)

    on report(self) = s"${self.name}: ${self.entries.length} entries"

val l = spawn(Ledger, "petty cash")

send(l.record, 5, "stamps")
send(l.record, 12, "coffee")

print(await ask(l.total))
print(await ask(l.report))
```

```output
17
petty cash: 2 entries
```

**A member written without `on` is an ordinary method and is not reachable from outside.** A handler
may call one; a message naming one is refused where it arrives.

**An `async` handler is re-entrant, and that is worth knowing before you write one.** While it waits,
the actor takes its next message and starts it — so two `ask`s posted together are both *started*
before either ends, and state a handler read before an `await` may have been changed by another
message by the time it comes back. A handler that is not `async` runs to its last line before the next
message is looked at, and needs no such care.

```slate
import { spawn, ask } from slate:actor

actor Slow
    var seen = []

    async on work(self, label)
        self.seen.push("start " + label)

        await sleep(30)

        self.seen.push("end " + label)

    on log(self) = self.seen

val s = spawn(Slow)

await all([ask(s.work, "a"), ask(s.work, "b")])

print(await ask(s.log))
```

```output
["start a", "start b", "end a", "end b"]
```

**An actor is declared at the top level of a file**, as a class and a `type` are. That is not a
restriction invented here; it is what makes the whole design sound. A body written at the top level
closes over nothing, so there is nothing of the spawner's for it to reach — which is also why there is
no `spawn(fn)`: a lambda handed to `spawn` would capture its enclosing scope, and those names live on
another heap.

## A module is instantiated once per actor

**Starting an actor runs every module the program imports, in the new VM, exactly as importing it runs
it in the main program.** A module's constants are bound there, its tables are built there and
whatever its top level prints is printed there — so an ordinary library works in a handler, with
nothing written for actors.

**What that means is that each actor has its OWN copy of every module.** Module-level state is per
actor: a table the main program filled is empty inside an actor until that actor fills its own, and
nothing either of them does is seen by the other. It is the same bargain as everything else here —
one heap each, nothing shared — and it is what a JavaScript worker does with its imports.

**So state that is meant to be shared does not belong at a module's top level at all.** Put it in
**one** actor that owns it and answers questions about it; that is what actors are for, and a
module-level `Map` is a copy per thread wearing the look of one table.

```slate
import { spawn, ask } from slate:actor
import { Limit, record, count } from "./registry.sl"

record("main", 1)

actor Counter
    on limit(self) = Limit

    on seen(self) = count()

    on fill(self)
        record("actor", 2)

        count()

val c = spawn(Counter)

print(await ask(c.limit))
print(count())
print(await ask(c.seen))
print(await ask(c.fill))
print(count())
```

```output
512
1
0
1
1
```

`Limit` reads the same on both sides, because the module was run on both. `count()` is the trap: the
main program put one entry in **its** copy, the actor's copy started empty, and filling the actor's
left the main program's alone.

**The ENTRY file is the one file an actor does not run.** Its top level is what spawns the actors and
prints the program's output, and running it again on every thread would spawn and print again. So only
its *declarations* are made there — a definition, a `class`, a `data`, a `type`, an `external` and an
`import`, which is the split
[`docs/reference/modules.md`](../reference/modules.md) states — and a **top-level `val` of the entry
file is not bound** inside an actor. A handler that names one says where the value belongs:

```slate
import { spawn, ask } from slate:actor

val maxItems = 512

actor Guard
    on cap(self) = maxItems

print(await ask(spawn(Guard).cap))
```

```error
the entry file's top level is not run inside an actor
```

Move it into a module the actor imports, or into the actor's own fields — which is what the
declaration form already says.

**A `spawn` written at a module's top level is refused**, naming the module. An actor's VM runs that
module, so it would start an actor whose VM ran it again, without end. Spawn from a definition the
program calls.

## Spawning, sending, asking, stopping

**These eight are functions, not methods of a handle.** A handle's field namespace belongs entirely to
the program: `a.stop` is the handler somebody wrote called `stop`, and nothing built in can collide
with a name they chose.

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
| `transfer(b)` | hand a buffer's storage over rather than copying it |

**The options are the last argument only where there is one more than the constructor takes**, which
is what keeps `spawn(A, args…, options)` unambiguous — an actor whose own constructor wants an object
still gets it.

**Reading a handler off a handle answers a `message`, which is a value.** `c.total` sends nothing and
asks nothing; it names an actor and one of its handlers. Because a message is an ordinary value it can
itself be sent, which is how a reply address travels. `send(c, "total")` is the same thing with the
name as text, for a program that builds one.

**A handler's return value *is* the answer to an `ask`**, and a `send` runs the same handler and throws
the answer away — which is why one handler serves both. **`ask` is a promise like any other**: it
composes with `all`, `race`, `any` and `allSettled`, and a fault inside the handler arrives as a
rejection at the `await`.

**A handle is a value and compares by identity**, as a promise, a function and a socket already do.
There is no registry and no name service: an actor is reachable by whoever was given its handle. **A
dead actor's handle is still a value** — it prints, it compares, it can be stored; what it cannot do is
deliver.

**Per sender, in order. Between senders, no order at all.** Two `send`s from one actor arrive in the
order they were written; a `send` from A and a `send` from B race.

```slate
import { spawn, send, ask, me } from slate:actor

actor Worker
    on introduce(self, boss)
        send(boss.enrol, me())

actor Boss
    var seen = []

    on enrol(self, who)
        self.seen.push(who)

    on count(self) = self.seen.length

val b = spawn(Boss)
val w = spawn(Worker)

send(w.introduce, b)

await sleep(50)
print(await ask(b.count))
```

```output
1
```

## What crosses, and how

A message is serialised out of the sender's heap and rebuilt in the receiver's. The sender's values are
untouched and the receiver's are new.

| what was sent | what arrives |
|---|---|
| integer, real, boolean, `null` | itself |
| string | a copy, in the receiver's heap |
| array | a new array, its elements copied by these rules |
| object | a new object, keys in the same order |
| a class instance | an instance of the same class, its fields copied |
| a data variant | the same variant, its fields copied |
| `Set`, `Map` | rebuilt, insertion order kept |
| `bytes` | a copy — or the storage itself, with `transfer` |
| a date, time, duration, zone or period | itself; a zone travels as its IANA name |
| a regex | rebuilt from its pattern and flags |
| an actor handle, a message | itself — it names an actor, not memory |
| a range | itself |
| a shared structure | shared structure: two fields holding one object arrive holding one object |
| a cycle | a cycle |

**A class instance crosses as an instance and not as a plain object**, because both actors are running
the same program: a class is identified by the name it was declared under, and the receiver looks it up
and rebuilds. It does not have to be exported.

```slate
import { spawn, ask } from slate:actor

class Point
    var x
    var y

actor Mover
    on shift(self, p, by) = Point.new(p.x + by, p.y + by)

val m = spawn(Mover)
val moved = await ask(m.shift, Point.new(1, 2), 10)

print(moved is Point, moved.x, moved.y)
```

```output
true 11 12
```

**Bytes have something to transfer.** A [`bytes`](bytes.md) buffer holds no values at all, so it is the
one container whose storage can move between heaps whole: `transfer(b)` detaches the sender's buffer
and hands the receiver the storage itself. The sender's buffer is left empty.

```slate
import { spawn, ask, transfer } from slate:actor

actor Sizer
    on size(self, b) = b.length

val s = spawn(Sizer)
val copied = toBytes("hello")
val moved = toBytes("goodbye")

print(await ask(s.size, copied), copied.length)
print(await ask(s.size, transfer(moved)), moved.length)
```

```output
5 5
7 0
```

### What does not cross

**Anything holding a resource the other thread has no business touching is refused, and the refusal
names the field it found** — not the message, not the type, because a message ten fields deep is
exactly where this happens.

```slate
import { spawn, send } from slate:actor

actor Sink
    on take(self, v) = 1

val s = spawn(Sink)

send(s.take, { handlers: { onDone: () -> 1 } })
```

```error
a message may not carry a function: `handlers.onDone` is a function
```

The set is functions and lambdas, promises, generators, sockets, child processes, channels, externals,
weak maps, weak references and declared types — and a `class` or `data` name itself, the receiver
having its own. A **promise** is the one worth saying twice: it is not a value in flight, it is a
suspended call on one machine's parked list, so await it and send what it answers.

**A handle that slate represents as a plain number crosses as that number and means nothing on the
other side.** An LMDB environment and a window are the two, and neither is a value another thread can
use; what is listed above is every kind slate can tell apart.

**`undefined` raises no question**, slate [refusing to store it anywhere](../reference/values.md): it
cannot be in an array, a field or a variable, so it cannot be in a message.

## Failure

**An actor that faults dies.** There is no supervisor built in and no restart: a fault that reaches the
top of a handler stops that actor, exactly as an unhandled fault stops a program. When it dies, all at
once: **every pending `ask` rejects with the fault**, **`done(a)` settles with it**, **every later
`send` is dropped** and **every later `ask` rejects at once** with *the actor is not running*.

```slate
import { spawn, ask, done } from slate:actor

actor Brittle
    on burst(self)
        throw "it broke"

val b = spawn(Brittle)
val ended = done(b)

try
    await ask(b.burst)
catch e
    print("asked: " + e.message)

try
    await ended
catch e
    print("done: " + e.message)
```

```output
asked: it broke
done: it broke
```

**Supervision is a library on top of `done`**, and deliberately not part of this: a supervisor is a loop
that awaits `done`, decides whether to spawn again, and counts restarts against a window — a page of
slate, with policy in it that nobody should have to take from the language.

**`stop(a)` is orderly**: the actor takes no new messages, drains the ones it has, runs its loop down,
and settles `done` with `null`. A message in flight when an actor stops is dropped, and its `ask`
rejects with *the actor stopped before it answered this*.

**The program ends when its own loop has drained and every actor it spawned has stopped.** A drained
program has nothing left to say to an actor, so each is asked to stop — orderly, which is what makes a
`send` written on the last line still served — and then waited for. `detach(a)` opts one out of that
wait, for a logger or a metrics sink.

## Under JavaScript

**An actor is a worker and a message is `postMessage`.** node's `worker_threads` and a browser's
`Worker` agree on the part that matters — one thread, one heap, one message queue between them — so
every program above runs under `slate js` and says the same thing.

**The worker runs the same file.** `slate js` emits one bundle that plays both roles: started as a
worker it runs every module the program imports, in full and once, and then the *declarations* of the
entry file — every definition, `class`, `data`, `type` and `import` — and then serves messages. It
runs not one line of what the entry file *does*. That is the same rule the interpreter follows, module
state being per worker exactly as it is per thread, and it is what lets a class instance cross: the
receiver looks the class up by the name it was declared under, and it is there because the file that
declared it was run.

- **node** starts the worker from the file the bundle was read from. A bundle that was never a file —
  one piped into `node -e`, say — cannot start one, and says so.
- **a browser** starts it from the `<script>` the bundle came in: its `src` where it has one, and its
  own text through a blob where it was written inline.

**A message is encoded by slate and not by the host.** Structured clone drops a prototype, so a class
instance would arrive as a plain object; it refuses a function with a sentence naming nothing a reader
wrote; and it takes some things slate refuses. So the copy rules above are slate's own on both back
ends — the same refusals, naming the same field, and shared structure and cycles kept — and what the
host clones is the encoded form. `transfer(b)` is the one thing handed over as itself, riding
`postMessage`'s transfer list.

**Four differences, and each is a host limit rather than a gap:**

- **`heap` does nothing in a browser.** Under node it is the worker's
  `maxOldGenerationSizeMb`, which is the nearest thing a JavaScript host has to a per-actor heap; a
  page offers no such knob at all, and the option is accepted and ignored there.
- **A message from one actor to another goes by way of the main thread.** A worker has one port, to
  whoever started it, so worker-to-worker traffic is relayed. Ordering is unaffected — one sender's
  messages still arrive in the order they were written — and the cost is a hop.
- **An actor spawned *by an actor* reports a worker that will not start as having died**, rather than
  as a fault where `spawn` was written: `spawn` answers a handle on the spot, and the worker is built
  a moment later on the main thread. Everything `spawn` can refuse about its *arguments* is still
  refused where it was written, on both threads.
- **A page has no end.** The program ends when its loop has drained and every actor it spawned has
  stopped, which is what node's `beforeExit` means; a page's script has no such moment and each actor
  there runs until it is stopped.

## Limits

- **A heap ceiling per actor**, passed at spawn and 64 MiB where nobody says. An actor that outgrows it
  faults; it does not take the process with it. Under `slate js` this is node's own ceiling and a page
  has none. The ceiling counts what the actor's values **hold** as well as how many of them there are —
  a string's bytes, an array's storage, a buffer's — so a handler that builds a hundred megabytes of
  text is bounded by it whether or not it made a hundred megabytes of objects.
- **A mailbox soft limit**, 65,536 where nobody says. Past it an `ask` rejects and a `send` faults in
  the sender — a refusal, never a wait, because a server that stalls its own loop waiting for a slow
  actor has stopped serving everybody else.
- **A thread per actor means tens to thousands, not millions**, and this process holds at most 1,024 at
  a time. A thread costs a stack and a scheduler slot; a program spawning a million of them is asking
  the wrong question.
- **An actor compiles the program when it starts and runs every module it imports**, which is what
  makes a class instance able to cross and what makes an imported library usable. That is milliseconds
  per actor and it grows with what the program imports, so an actor is something a program makes tens
  of and keeps, not something it makes per request.

## What actors are not for

**They are not [`slate:cluster`](cluster.md)**, and the two solve different halves of one problem. A
cluster is *processes*: one copy of the program per core, a supervisor in front, and a worker that dies
taking nothing with it — the answer for a **server**, where the work is already separated by connection.
Actors are threads inside one process, for work that is one program's. A server may well use both.
