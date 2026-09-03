# `slate:redis`

A Redis client on the event loop.

```
import { redis } from slate:redis

val r = (await redis("127.0.0.1", 6379)).value

await r.command("SET", "greeting", "hello")
print((await r.command("GET", "greeting")).value)

r.onPush(m -> print("pushed:", m))

r.close()
```

**One export, because a connection is one object** and everything else is a method on it. That is
[`slate:regex`](regex.md)'s shape. `redis` is also what `connect` had to become, [`slate:net`](net.md)
exporting that name and a program with a Redis client in it having sockets in it.

## The transport is slate's

**Only the reply parser is bound.** The reader is fed bytes and answers replies and never opens, reads or
writes a socket — so the transport stays on the same loop that is answering HTTP, and **a Redis client in a
server cannot stop the server.** Binding a blocking `redisCommand` would have made that impossible rather
than merely difficult.

## There is no `get` and no `set`

Redis has some 240 commands and grows more each release, so a client that named them would be a list to keep
current and a wall between a program and anything new.

**`command` gathers its words** — `r.command(...parts)` for a computed one — and **every argument crosses as
a counted string**, so a value holding CRLF or what looks like a whole second command is still one argument
and there is nothing to escape.

## The rules

- **A command answers a result and a closed client throws.** `-ERR` is the server refusing and a connection
  that has gone is an outside condition; calling `command` after `close` is the program's own mistake.
- **Every waiting promise is settled when the connection goes**, with a result rather than a failure — a
  program awaiting an answer it will never get would otherwise wait for the rest of the run, which in a
  server is a request that never finishes.
- **A push is never matched against a waiting command.** A pub/sub message arrives *between* replies to your
  own commands, so a client that assumed every reply was its own would hand a subscriber's message back as
  the answer to a `GET` — silently, both being good replies. `r.onPush(f)` is where they go.
- **Pipelining is what happens when you do not await.** RESP has no request ids because answers come back in
  the order the commands were written, so issuing several and awaiting them afterwards costs one round trip.
- **A protocol failure ends the connection** rather than being stepped over. The two ends disagree about
  where a reply begins, so nothing after it can be trusted.
