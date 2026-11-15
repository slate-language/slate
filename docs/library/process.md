---
title: "slate:process"
weight: 70
---

# `slate:process`

Another program, this program's own environment, and being asked to stop.

```slate
import { env, args } from slate:process

print(args, env("PATH") is string, env("NO_SUCH_VARIABLE_HERE"))
```

```output
[] true null
```

## `stderr`

**`print` is the answer a program produces and `stderr` is what it says about producing it**, which is
the division every shell already makes: `slate app.sl > answers.txt` keeps the answers in the file and
lets the complaints through to the terminal.

```slate
import { stderr } from slate:process

stderr("could not reach the database, retrying\n")
```

- **It takes as many values as `print` does** and separates them the same way, and answers nothing.
- **The newline is yours**, as node's `process.stderr.write` leaves it: a program writing a JSON object
  per line and one drawing a progress bar want different answers, and only one of them can be the
  default.
- **It writes straight to the descriptor and does not wait.** A complaint is the one thing a program may
  need to have said before the next line runs — a crash after an `await` would lose it — so this is
  synchronous, exactly as `print` is.

## `args` and `exit`

```slate
#!/usr/bin/env slate

import { args, exit } from slate:process

if args.length == 0
    print("usage: greet <name>...")
    exit(2)

for name in args
    print("Hello, " + name + "!")
```

- **`args` is a value, not a call**, and it holds only what came after the program's name — so `args[0]` is
  the first thing a person typed. That is where slate parts from C, node and Python, all three of which
  hand a program its whole command line and begin by skipping past themselves.
- **`exit(status)` stops the program and tells the shell what it came to.** Everything printed before it is
  still printed, a `try` between it and the top cannot swallow it, and **a status outside 0–255 is refused
  rather than truncated** — a shell keeps the low eight bits, so an unexamined `exit(256)` is a program
  that says it failed and is recorded as having succeeded.
- **slate reads no argument of its own after the program's name**, so a script's own options are safe to
  invent.
- Without an `exit`, a program that ran answers `0` and one that faulted answers `1`. `slate` itself
  answers `2` when it could not work out what it was being asked to do.

## `env`

`env(name)` answers `string | null`. `?? ""` is what a program writes.

## `environment`

`environment()` answers every variable in this program's own environment as an object, name to string —
for a program that has to see the ones it was not told the names of.

```slate
import { env, environment } from slate:process

val all = environment()

print(all["PATH"] == env("PATH"), has(all, "NO_SUCH_VARIABLE_HERE"))

all.NO_SUCH_VARIABLE_HERE = "added"

print(env("NO_SUCH_VARIABLE_HERE"), has(environment(), "NO_SUCH_VARIABLE_HERE"))
```

```output
true false
null false
```

- **Every call answers a new object**, so changing it changes nothing: not the environment, not `env`, and
  not the next call. Like `env`, it is reading only.
- **A browser has no environment and `environment()` answers an empty object**, as `env` answers every
  name unset.

## `pid`

`pid()` answers this process's own process id, the number the operating system knows it by —
`child.pid`'s own question, asked of the program itself rather than of a child it started.

```slate
import { pid } from slate:process

print(pid() > 0)
```

```output
true
```

**A browser has no process id and `pid()` answers `null` there.**

## `run`

```slate
val r = await run(cmd, args, options)       // { status, signal, out, err } or an error
```

Options are `{ cwd, env, timeout }`.

- **A child that ran and failed is a success with a non-zero status; an error means there was no child.**
  That is what lets a caller tell "the program said no" from "there is no such program".
- **A signal is `null`, never `0`**, since 0 is a status a program can exit with.
- **Settling waits for three things**: the child exiting and *both* pipes reaching end of file. A child can
  exit with output still in the pipe, so settling on the exit alone hands back a truncated answer that
  looks whole.
- **The child's stdin is closed, not inherited.** An inherited descriptor has the child competing with
  slate for the terminal, and a child waiting on input nobody will type is a hang with nothing on screen.
- **`env` replaces the child's environment.** A program that wants to add a variable reads it with
  `env(name)` and passes it through; one that wants an empty environment has no other way to say so.
- **A timeout sends `SIGKILL`**, a timeout being the caller saying they will not wait any longer and a
  signal the child may ignore leaving the promise pending exactly as it was.
- **Output that is not text fails the call** rather than being replaced or mangled.

## `spawn`

**`run` is one question with one answer and `spawn` is a conversation.** `run` starts a program, waits
for it and hands back what it printed; a *worker* — something started once, told things over its
lifetime, and watched for the moment it dies — has nothing to wait on and no single answer to be
given. So `spawn` answers at once, with a child the program keeps.

```slate
import { spawn } from slate:process

async main()
    val started = spawn("/bin/sh", ["-c", "read line <&3; printf '%s\\n' \"$line\" >&3"],
        { ipc: true })
    val worker = started.value

    worker.onMessage(m ->
        print("the worker sent back job", m.job))

    worker.send({ job: 7 })

    val gone = await worker.exited

    print("it left with", gone.value.status)

main()
```

```output
the worker sent back job 7
it left with 0
```

- **`spawn(command, args)` and `spawn(command, args, options)` answer `{ ok: true, value: child }` or
  `{ ok: false, error }`, and they answer it AT ONCE.** The child has already been started by the time
  the call comes back, so "there is no such program" is known there rather than one turn later.
- **The options are `cwd`, `env`, `ipc`, `stdout` and `stderr`.** `env` replaces the child's
  environment exactly as `run`'s does; `ipc: true` opens the message channel; `stdout` and `stderr`
  are each `"inherit"`, `"pipe"` or `"ignore"`. **Any other key, or a value of the wrong kind, faults
  at the call**, naming the option — a misspelt `stdot: "pipe"` is a mistake in the program, not
  something to pass over.
- **stdin is closed, and stdout and stderr are INHERITED unless the options say otherwise**, which is
  the pair a worker wants: a child waiting on input nobody will type is a hang with nothing on screen,
  and a worker's own log lines belong wherever its supervisor's do. `"ignore"` sends a stream nowhere;
  `"pipe"` hands it to the program, below.
- **A live child keeps the program alive**, exactly as a socket does. A supervisor that has started a
  worker and reached its last statement is not finished.

### What a child answers to

| | |
|---|---|
| `child.pid` | the number the operating system knows it by, readable after it has died |
| `child.exited` | a promise of `{ status, signal }`, settled once — `await` it to learn a worker died |
| `child.stdout`, `child.stderr` | the stream where the options piped it, and `null` where they did not |
| `child.onExit(fn)` | the callback form of the same answer |
| `child.send(value)` | one message, as JSON and a newline — `{ ok, error }` |
| `child.send(value, socket)` | the same message with a connection travelling beside it |
| `child.onMessage(fn)` | what to call for every message the child sends |
| `child.kill()`, `child.kill(signal)` | ask it to stop; `SIGTERM` where no signal is named |

- **`exited` and `onExit` are both there because a supervisor wants each in a different place.**
  `await child.exited` is what one worker's own line of execution waits on; `onExit` is what a
  supervisor watching several of them registers, having no line of execution to give to any one.
- **A signal is `null` and never `0`**, which is `run`'s rule and for its reason: zero is a status a
  program can exit with, so "killed by signal 0" — which is not a thing — has to be distinguishable
  from "not killed". A child stopped by `kill()` answers `15`.
- **`send` answers a RESULT and refuses a value that is not a message.** A worker dying while its
  supervisor was writing to it is the ordinary shape of a process ending, so that is
  `{ ok: false, error }`; a value `toJSON` cannot render is a defect in the program and faults, in
  `toJSON`'s own words. That is slate's two-channel rule read twice in one call.
- **A child started without `ipc` is refused a message** rather than answering a failure: the program
  asked for a child with no channel and then wrote to the channel.

### Reading what a child prints

**`stdout: "pipe"` and `stderr: "pipe"` hand a stream to the program**, as `child.stdout` and
`child.stderr`. A stream is an asynchronous source of [`bytes`](bytes.md) — the same kind a
[streamed `fetch`](globals.md) body is — so `for await` reads it chunk by chunk as the child writes,
and `text()` waits for the whole of it:

```slate
import { spawn } from slate:process

async main()
    val child = spawn("/bin/sh", ["-c", "printf 'one\\nthree'; printf two >&2; head -c 100000 /dev/zero"],
        { stdout: "pipe", stderr: "pipe" }).value

    var total = 0

    for await chunk in child.stdout
        total = total + chunk.length

    print(total, "bytes on stdout")
    print("and on stderr:", (await child.stderr.text()).value)
    print("it left with", (await child.exited).value.status)

main()
```

```output
100009 bytes on stdout
and on stderr: two
it left with 0
```

| | |
|---|---|
| `stream.next()` | a promise of `{ value, done }`: the next chunk, as bytes, or `done` once the child has closed it |
| `stream.text()` | a promise of everything still to come as one string — `{ ok: true, value }`, or `{ ok: false, error }` where it is not UTF-8 |
| `stream.close()`, `stream.dispose()` | stop reading it; what the child writes after that is thrown away |

- **A chunk is whatever has arrived** since the last one was asked for. `text()` hands over everything
  not yet taken, so it can follow a few `next()`s.
- **A piped stream is read from the moment the child starts, whether the program asks or not.** What
  arrives waits for the program, so a child writing more than a pipe holds is never left blocked on a
  supervisor that has not got round to reading — `await child.exited` first and `text()` afterwards
  is fine. The price is that a stream nobody reads is held in memory until the child ends.
- **`exited` waits for the piped streams to end**, as it waits for the channel: by the time it settles,
  everything the child wrote has arrived, and a stream read afterwards hands all of it over.
- **Leaving a `for await` early lets go of the stream**, as [a loop left early](../reference/statements.md#leaving-early-closes-what-the-loop-walked)
  lets go of whatever it walked, and so does `using`. The pipe is not closed under the child: it is
  still read to its end and what arrives is dropped, so a child that goes on writing still exits.
- **One reader at a time.** A second `next()` while one is waiting, or a `text()` beside it, faults.
- **Output that is not text is an answer**, `{ ok: false, error }` from `text()`, the bytes having come
  from outside the program; a chunk from `next()` is bytes and has no such question.

### Passing a connection to a worker

**A supervisor can hand an accepted connection to a child, which is how one port is spread over several
processes.** The supervisor is the only program listening; it accepts every connection itself and gives
each one to a worker over the channel it spawned that worker with. This is what node's cluster module
does by default, and on macOS it is the only way — the kernel refuses `reusePort` there.

```slate
import { spawn } from slate:process
import { listen } from slate:net

var workers = []
var next = 0

for i in 0..<4
    workers.push(spawn("slate", ["worker.sl"], { ipc: true }).value)

listen(8080, conn ->
    workers[next].send({}, conn)
    next = (next + 1) % workers.length)
```

and the worker, which never listens at all:

```slate
import { channel } from slate:process
import { adopt } from slate:http

val app = adopt(req -> "answered by a worker")

channel().onMessage((m, conn) ->
    if conn != null then app.handle(conn))
```

- **The second argument is a connection — what `accept` gives a listener and what `connect` answers.**
  It travels as a duplicate of the descriptor, so **the sending side's copy is closed once the message
  has gone**: two programs reading one connection would each see half of it. That is node's rule too.
- **One message carries at most one connection**, and the message is what says what to do with it —
  which worker, which tenant, which protocol. `{}` is an ordinary payload where there is nothing to say.
- **A socket may only be passed between two programs on the same host**, a descriptor crossing a Unix
  domain socket under the interpreter and node's own channel under `slate js`. Each end says which host
  it is on — the parent in the child's environment, the child in the line its channel opens with — so a
  pair that cannot pass one is refused with a sentence rather than dropping it.
- **So a socket goes to a child that has already said something.** A worker signalling that it is ready
  is what a supervisor waits for anyway; before that, the supervisor has started a command and does not
  yet know what it turned out to be:

```slate
import { spawn } from slate:process
import { listen } from slate:net

val worker = spawn("/bin/sh", ["-c", "sleep 1"], { ipc: true }).value

listen(0, conn -> null)
worker.send({}, listen(0, conn -> null))
```

```error
has not said what it is yet
```

## `channel`

The other end of the same thing, read from inside the child.

```slate
import { channel } from slate:process

val ch = channel()

if ch == null
    print("nobody started me")
else
    ch.onMessage(job ->
        ch.send({ done: job.id }))
```

- **`channel()` answers `{ send, onMessage }` or `null`.** `null` rather than a fault, because the same
  file is a worker under a supervisor and a script somebody typed the name of — and asking which it is
  now is the whole point of the call. Asking twice answers the same channel.
- **An open channel keeps the program alive**, which is what a worker waiting to be told something is.
  It ends when the other end goes, so a worker whose supervisor has finished finishes too.
- **`onMessage` is handed the message and the connection that came with it** — `fn(value, socket)`,
  where `socket` is `null` for an ordinary message. A handler written with one parameter is unchanged, a
  call dropping the arguments a function did not ask for. `channel().send(value, socket)` sends one back
  up, under the same rule as `child.send`.
- **The wire is one JSON value per line on descriptor 3**, and the child finds it through
  `SLATE_CHANNEL_FD` in its environment — which is what node's `NODE_CHANNEL_FD` is for. It is the same
  format on both back ends, so a supervisor running under the interpreter can drive a child running
  under node and the other way round. `SLATE_CHANNEL_HOST` beside it says which host the *parent* is
  running on, and the first line a channel writes says which host the *child* is — the pair that decides
  whether a connection can cross.
- **A message arrives whole or not at all.** A read is a run of bytes and a message is a line, so half
  a message waits for the rest of itself — and a line that is not JSON stops the program naming the
  channel rather than being dropped where nobody would see it.
- **There is no `close`.** A worker ends by ending, and a supervisor closes a channel by letting the
  child go — or by asking it to stop with `kill`.

## Signals

A program that leaves a socket open never exits, so a server ends only from the inside — and every way a
deployment has of asking one to stop is a signal:

```slate
import { onSignal } from slate:process
import { serve, close } from slate:http

val server = serve(8080, req -> "hello")

onSignal("SIGTERM", () ->
    print("shutting down")
    close(server))
```

`SIGTERM` is what a container stopping and a `systemd` unit restarting both send; `SIGINT` is Ctrl-C.

- **The handler is an ordinary function at an ordinary time.** It runs between one turn of the loop and the
  next, so nothing about it is restricted the way a C signal handler is: it may print, allocate, close a
  socket, start a timer, and take as long as the shutdown needs.
- **It is handed nothing, and the registration is what names the signal.** slate checks the count of a
  call's arguments, so a name passed to every handler would be a parameter almost none of them would read;
  a program that wants one function for two signals registers it twice.
- **A watcher does not keep the program alive.** A script that installs a handler and does nothing else
  still ends. What keeps a server running is the server.
- `onSignal` answers an id and `offSignal(id)` stops that handler. Stopping one twice is not an error.
- **`SIGKILL` and `SIGSTOP` are refused by name** — the kernel acts on those itself and nothing a program
  says will run first.
