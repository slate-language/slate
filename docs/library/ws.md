# `slate:ws`

WebSockets, written in slate over the [`slate:http`](http.md) upgrade seam.

```
import { serve } from slate:http
import { accept } from slate:ws

serve(port, handler, (req, socket, head) ->
    val ws = accept(req, socket, head).value

    ws.onMessage((m) -> ws.send("echo:" + m)))
```

| | |
|---|---|
| `accept(req, socket, head)` | a **result** holding the connection |
| `accepting(req)` | whether this request is a WebSocket handshake |
| `framed(payload, opcode)` | a frame, for a program doing its own writing |
| `unframed(bytes)` | the other direction |

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
