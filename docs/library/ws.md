# `slate:ws`

WebSockets, written in slate over the [`slate:http`](http.md) upgrade seam.

```slate
import { serve } from slate:http
import { accept } from slate:ws

serve(port, handler, (req, socket, head) ->
    val ws = accept(req, socket, head).value

    ws.onMessage((m) -> ws.send("echo:" + m)))
```

| | |
|---|---|
| `open(url)` | a **promise** of a result holding the connection — the client |
| `accept(req, socket, head)` | a **result** holding the connection — the server |
| `accepting(req)` | whether this request is a WebSocket handshake |
| `framed(payload, opcode)` | a frame a server writes, for a program doing its own writing |
| `maskedFrame(payload, opcode)` | the same frame a client writes, which is masked |
| `unframed(bytes)` | the other direction |

## `open(url)` — the client

```slate
import { open } from slate:ws

async main()
    val made = await open("wss://example.com/socket")

    if !made.ok then return print(made.error)

    val c = made.value

    c.onMessage((m) -> print("said", m))
    c.onClose((code, why) -> print("gone", code))
    c.send("hello")

main()
```

**A promise of a result and not a promise that fails**, which is `connect`'s shape in
[`slate:net`](net.md): a server that is not there is a condition a client was always going to deal
with. `ws://` and `wss://` are the only two schemes, and a url that is not one is refused in the same
sentence wherever the program runs.

**The connection is the same object `accept` answers** — `onMessage`, `onBinary`, `onClose`, `send`,
`sendBytes`, `ping`, `close` — so a program that speaks WebSocket does not know which end it is.

**A client masks every frame it sends and a server masks none**, which is RFC 6455's rule and not an
implementation detail: masking exists so that a hostile page cannot steer an intermediary into reading
payload bytes as a request of its own, and only the browser's direction has that problem. Each end
fails the connection when the other gets it wrong.

**Under `slate js` the client is the HOST's.** A browser has no socket at all, so the framing here has
nothing to write onto and the work goes to the `WebSocket` object the page already has;
[the JavaScript page](../reference/javascript.md) says what that changes. The one visible difference
is `ping`, which refuses there: a browser writes the protocol's control frames itself and gives a page
no way to.

## The upgrade seam

**`serve` takes a third function**, and so does `serveStream`. A request that says `Connection: upgrade`
reaches it with `(req, conn, leftover)`.

**The leftover bytes matter.** A client may put its first frame in the same packet as the handshake, and
those bytes are already off the socket — so they are handed to `accept`, which seeds the connection's
buffer with them.

**A server with no upgrade function answers 501 rather than going quiet.** The client asked for a protocol
this program does not speak, which it can act on; a socket nothing will ever answer is not.

## What is in the module

**The framing, the masking, the fragment reassembly and base64 are all slate.** `&`, `|`, `^`, `<<` and
`>>` are slate's own on 64-bit integers, and `toBytes`/`fromBytes` are the byte surface.

**SHA-1 is the one thing reached for**, from [`slate:crypto`](crypto.md). This is not a use of SHA-1 that
its weakness touches: nothing is signed, and the protocol wants a value only the other end could have
computed.
