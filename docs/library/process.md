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

if args.len() == 0
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
