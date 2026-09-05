// `slate:ws`, on both back ends.
//
// **What is here is everything about a WebSocket that does not need a socket**, which is most of the
// protocol: the framing, the masking, the accept value, and every way a url can be wrong. All of it
// is written in slate and runs identically wherever slate runs.
//
// **What is NOT here is the traffic, and it cannot be.** A corpus file is one program run twice, and
// a client needs a server somewhere; the interpreter can listen and a browser cannot. So the live
// half is pinned in `tests_ws.sysl` instead -- slate's own server with the interpreter's client
// against it, and the same server with a client compiled to JavaScript and run under node's own
// `WebSocket`. That is the one arrangement that exercises both implementations of `open` against one
// server, which is what says they are two implementations of one thing.
//
// **A url is read before either client sees it**, and that is what makes the refusals below the same
// sentence on both hosts. Left to the host, `open("http://x")` would answer slate's words in the
// interpreter and the browser's in a browser, over a mistake neither host has anything to do with.

import { accepting, framed, maskedFrame, unframed, open } from slate:ws

// RFC 6455's own example, which is the one value every implementation is checked against.
print(accepting("dGhlIHNhbXBsZSBub25jZQ=="))

// -- the framing ---------------------------------------------------------------------------------

// A server's frame is unmasked and a client's is masked, and each reads the other's back whole.
val hello = toBytes("hello")
val server = framed(1, hello)
val client = maskedFrame(1, hello)

print(server[0], server[1], len(server))
print(client[0], client[1] >> 7, len(client))

val readServer = unframed(server, 0)
val readClient = unframed(client, 0)

print(readServer.masked, readServer.fin, readServer.opcode, fromBytes(readServer.payload).value)
print(readClient.masked, readClient.fin, readClient.opcode, fromBytes(readClient.payload).value)

// **The mask is four random bytes, so a masked frame is not the same bytes twice** -- and both come
// back as the same message, which is the whole of what masking has to be.
val again = maskedFrame(1, hello)

print(len(again) == len(client), fromBytes(unframed(again, 0).payload).value)

// The three lengths a frame is written in, from either end.
long(n)
    var bs = []

    for i in 0..<n
        push(bs, 65)

    val m = unframed(maskedFrame(2, bs), 0)

    print(n, len(maskedFrame(2, bs)), m.size, len(m.payload))

long(125)
long(126)
long(65535)
long(65536)

// A frame that has not all arrived is not a frame yet, from either end.
print(unframed(client[0..<(len(client) - 1)], 0))
print(unframed([], 0))

// -- what a url may be ---------------------------------------------------------------------------

async says(url)
    val made = await open(url)

    print(made.ok, made.error ?? "")

async urls()
    await says("http://example.com/")
    await says("example.com")
    await says("ws://")
    await says("ws://host:/")
    await says("ws://host:notaport/")
    await says("ws://host:70000/")
    await says("wss://[::1/")

urls()
