---
title: "slate:cluster"
weight: 75
---

# `slate:cluster`

A worker cluster on one machine, so that a server uses every core the machine has.

One process cannot use two cores, and a slate server is one event loop on one thread — so a sixteen-core
box running one slate program is using a sixteenth of what it has. A cluster is the answer every runtime
with a single-threaded loop arrives at: run the program N times, spread the connections over the copies,
and put one process in front to keep the others alive.

```slate
import { cluster } from slate:cluster

await cluster({ workers: 4 }, w ->
    await w.serve(8080, req -> "answered by worker " + string(w.workerId)))
```

**`cluster` is the one call a program makes, and it is called on BOTH sides of the fork.** The
supervisor spawns the workers and answers a promise that settles when the cluster is down; a worker
calls the function it was given and answers a promise that settles when that worker has drained. There
is no second program to write and no second file: the workers are copies of this one.

## Which half a process is

**Which half a process is, is settled before a statement of the program runs** — a worker is a program
that was started with a channel — so `isPrimary` and `isWorker` are values rather than questions.
`workerId()` is a call, because which worker a process is arrives from the supervisor over that channel
a moment later, and is `0` in the supervisor.

```slate
import { isPrimary, isWorker, workerId } from slate:cluster

print(isPrimary, isWorker, workerId())
```

```output
true false 0
```

node spells the same three `cluster.isPrimary`, `cluster.isWorker` and `cluster.worker.id`.

## `w.serve(port, handler)`

**What [`serve`](http.md) in `slate:http` is to a program with no cluster.** It answers a promise of
`{ port, close }` rather than a server, because under the default scheduling the listening socket
belongs to the supervisor: a worker asking for port `0` learns which port the kernel chose only when the
supervisor says so.

```slate
import { cluster } from slate:cluster

await cluster({}, async w ->
    val app = await w.serve(0, req -> "hello from " + string(w.workerId))

    print("worker " + string(w.workerId) + " is serving " + string(app.port)))
```

- **The handler is [`slate:http`](http.md)'s handler**, with the same request and the same answers — the
  module `adopt`s it and hands it connections rather than opening a socket of its own.
- **A third argument is the WebSocket upgrade**, exactly as `serve`'s is, so
  [`slate:ws`](ws.md) works inside a cluster with nothing added.
- **`app.close()` stops this worker serving that port** and leaves the others alone.
- **Every worker asks for the same port and one of them creates it.** The supervisor listens once and
  remembers which port a request of `0` turned into, so all four workers are handed connections from one
  socket.

## Spreading the connections: two schedulings

**Round-robin is the default on every platform.** The supervisor is the only process listening, and it
hands each accepted connection to the next worker over that worker's channel — a real descriptor
crossing a real process boundary, which is what [`slate:process`](process.md)'s
`channel().send(value, socket)` is for. It works everywhere, and it is what node's cluster does by
default.

```slate
import { cluster } from slate:cluster

await cluster({ workers: 4, scheduling: "reusePort" }, async w ->
    await w.serve(3000, req -> "hello"))
```

**`{ scheduling: "reusePort" }` is the other one**: every worker listens on the port itself with
`reusePort: true` and the kernel spreads the connections. It is faster — a connection never crosses a
process boundary — and **it exists on Linux and the BSDs and not on macOS**, where the attempt fails
with the `ENOTSUP` sentence [`slate:net`](net.md) gives it. So a program that asks for it on a Mac is
refused at `serve`, and the default is the one that runs everywhere. node calls the pair `SCHED_RR` and
`SCHED_NONE`.

## The supervisor is the message bus

Every worker is already talking to the supervisor over a channel, so a message from one worker to the
others has a route through a process that is by definition alive and by definition on this machine.

```slate
import { cluster } from slate:cluster

await cluster({ workers: 3 }, w ->
    w.subscribe("cache:drop", key -> print("worker " + string(w.workerId) + " forgets " + key))

    w.publish("cache:drop", "user:42"))
```

- **A publisher does not hear itself.** `w.publish(topic, value)` goes up to the supervisor and is fanned
  out to every *other* worker's `w.subscribe(topic, fn)` — the rule a bus with one process in the middle
  can actually keep, and the one an invalidation wants.
- **The value is whatever crosses the channel**, which is one JSON value per line: objects, arrays,
  strings, numbers, `null`.
- **So a single-box deployment needs no Redis, and that is the point of the module.** What a second
  machine needs is a bus that crosses machines, and this is deliberately not one —
  [`slate:redis`](redis.md) is.

## When a worker dies, and when the machine asks the cluster to stop

- **A worker that exits is started again**, with a backoff after repeated quick deaths so that a program
  failing at start-up does not spin: the delay doubles from 100 ms and stops at `maxBackoffMillis`, which
  is thirty seconds. node restarts nothing; a supervisor that did not would be a supervisor in name.
- **`SIGTERM` and `SIGINT` drain.** The supervisor stops accepting, tells every worker to shut down, and
  each worker runs what it registered with `onShutdown` before ending. A worker still alive after
  `drainMillis` is killed.
- **`SIGHUP` rolls.** The workers are replaced one at a time, and the replacement is serving before the
  one it replaces is asked to leave, so the port is never unserved — which is what a deployment does to
  pick up new code without dropping a connection.

```slate
import { cluster } from slate:cluster

await cluster({ workers: 2, drainMillis: 5000 }, async w ->
    val app = await w.serve(0, req -> "hello")

    w.onShutdown(async () ->
        print("worker " + string(w.workerId) + " is finishing what it has")))
```

**A shutdown asked for twice is not an error**, and the promise `cluster` answered settles once.

## Options

| option | |
|---|---|
| `workers` | how many processes to run; the number of cores by default |
| `scheduling` | `"roundRobin"` (the default) or `"reusePort"` |
| `drainMillis` | how long a worker gets to finish on the way out, before it is killed; `10000` |
| `maxBackoffMillis` | the ceiling on the restart delay after repeated quick deaths; `30000` |
| `exec` | the command to start a worker with; this program's own interpreter by default |
| `args` | its arguments; this program's own path by default |
| `primary` | a function the supervisor calls with what a supervisor can do |

**A count of zero is refused rather than read as "no workers"** — a cluster of none is a program that
listens to nothing and never ends, which is never what anybody meant by the number.

```slate
import { cluster } from slate:cluster

await cluster({ workers: 0 }, w -> null)
```

```error
a cluster runs at least one worker, and was asked for 0
```

## `options.primary`

**The supervisor is otherwise a process with nothing to do**, and a deployment usually has something for
it: a health endpoint on a port no worker serves, a metric, a log line per restart.

```slate
import { cluster } from slate:cluster

await cluster({ workers: 4, primary: sup ->
    print("supervising " + string(sup.workers) + " workers")

    sup.onWorkerExit(id -> print("worker " + string(id) + " went, starting another"))

    sup.subscribe("hit", n -> null) },
    async w -> await w.serve(0, req -> "hello"))
```

- **`sup.workers`** is how many were asked for.
- **`sup.publish(topic, value)`** reaches every worker — the supervisor is not a worker, so it hears
  nothing back through `subscribe` unless a worker published it.
- **`sup.onWorkerExit(fn)`** is called with the number of a worker that has gone, before its replacement
  starts.
- **`sup.shutdown()`** begins the drain that `SIGTERM` begins.

## What starts a worker

**A supervisor starts another copy of the program it is running inside**, which means knowing what to
run — and [`args`](process.md) deliberately does not carry the program's own name, so nothing an
ordinary program can read says it. The module is given it: `exec` defaults to the interpreter that is
running and `args` to the script it was handed.

**A program whose statements never came from a file has no command line to copy**, and says so rather
than starting something else:

```
slate:cluster does not know what to start — this program was not run from a command line,
so name the worker command with `exec` and `args`
```

Naming both is also how a worker is a *different* program from the supervisor, where a deployment wants
that.

## `cpus`

`cpus()` is in [`slate:process`](process.md), not here — it is what the machine says it can do at once,
which is the number `workers` defaults to.

```slate
import { cpus } from slate:process

print(cpus() >= 1)
```

```output
true
```
