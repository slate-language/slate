# `slate:nghttp2`

HTTP/2: the framing layer, and HPACK on its own.

```slate
import { h2Client, h2Server, h2Receive, h2Send, h2Next, h2Request, h2Respond, h2Close } from slate:nghttp2
```

**Nothing here touches a socket.** Bytes that arrived go in at `h2Receive`, bytes to write come out of
`h2Send`, and what happened in between is read off with `h2Next`. HTTP/2 is a *transformation*, so how
bytes reach the wire stays your program's business — which is why the whole protocol can be driven
between two sessions in memory, with no port and nothing that can hang:

```slate
import { h2Client, h2Server, h2Receive, h2Send, h2Next, h2Request, h2Respond, h2Close } from slate:nghttp2

val c = h2Client()
val s = h2Server()

// Whatever one end wants to write, handed to the other.
pump(from, to)
    val bytes = h2Send(from)

    if len(bytes) > 0 then h2Receive(to, bytes)

// Everything the peer did since last time.
seen(who)
    var out = []

    loop
        val e = h2Next(who)

        if e == null then break

        push(out, e)

    out

val stream = h2Request(c, { ":method": "GET", ":scheme": "https", ":authority": "example.test", ":path": "/things" })

pump(c, s)

for e in seen(s)
    if e.kind == "headers" then print("asked for", e.headers[3])

h2Respond(s, stream, { ":status": "200", "content-type": "text/plain" }, "hello from h2")

pump(s, c)

for e in seen(c)
    if e.kind == "data" then print(fromBytes(e.bytes).value)

h2Close(c)
h2Close(s)
```

```output
asked for [":path", "/things"]
hello from h2
```

| | |
|---|---|
| `h2Client(options?)` / `h2Server(options?)` | a session |
| `h2Receive(session, bytes)` | `null`, or `{ error }` where the peer spoke nonsense |
| `h2Send(session)` | the bytes to write, as an array |
| `h2Next(session)` | the next event, or `null` |
| `h2Request(session, headers, body?)` | a client's; answers the stream number |
| `h2Respond(session, stream, headers, body?)` | a server's |
| `h2Settings(session, { … })` | |
| `h2Goaway(session, lastStream, code?)` / `h2Reset(session, stream, code)` | giving up |
| `h2WindowUpdate(session, stream, by)` / `h2Consume(session, stream, bytes)` | flow control |
| `h2Ping(session)` | |
| `h2Wants(session)` | `{ read, write }` |
| `h2Close(session)` | |
| `hpackDeflater(maxTable?)` / `hpackInflater()` | HPACK on its own |
| `hpackDeflate(encoder, headers)` / `hpackInflate(decoder, bytes)` | |
| `hpackClose(x)` | |

## Which version a connection is

**HTTP/2 over TLS is chosen by ALPN and by nothing else** — no upgrade handshake, no version header.
That half is [`slate:net`](net.md)'s: a listener offers a list, a client offers one, and
`alpnProtocol(conn)` says what the two settled on. A server taking both versions on one port asks it
and hands the connection to whichever it is:

```slate
val server = listen({ port: 8443, cert: pem, key: keyPem, alpn: ["h2", "http/1.1"] }, conn ->
    if alpnProtocol(conn) == "h2"
        speakHttp2(conn)
    else
        speakHttp1(conn))
```

**`h2c` — HTTP/2 with no TLS at all — needs nothing extra**, a session neither knowing nor caring
where its bytes come from. What is not here is the HTTP/1.1 `Upgrade:` dance that converts an existing
connection; prior-knowledge `h2c`, which is what one speaks to a service one controls, is the ordinary
case and works today.

## Events

`h2Next` answers one at a time, in the order they happened, and `null` when there are no more. Every
event has a `kind`, and the rest of its fields depend on it:

| `kind` | |
|---|---|
| `headers` | `stream`, `headers`, and `of` — `"request"`, `"response"` or `"trailer"` |
| `data` | `stream`, `bytes` — **one event per DATA frame**, not one per stream |
| `streamEnd` | `stream` — the peer will send no more, and may still be reading |
| `streamClose` | `stream`, `code` — finished at both ends |
| `settings` | the peer's settings arrived and are in force |
| `goaway` | `lastStream`, `code` |
| `rstStream` | `stream`, `code` |
| `windowUpdate` | `stream`, `increment` — `stream` is 0 for the connection |
| `ping` | `ack` |

**Events rather than callbacks**, and that is the design decision this module turns on: nghttp2 calls
back from inside `receive`, which is a place your code has no business running — it cannot submit
frames there without reentering the library, and a closure it registered would have to be kept alive
by the session. What you write instead is a loop.

## Headers

**Write them as an object, or as pairs where order and duplicates matter.** An object is what a
program writes nine times in ten; two `set-cookie` headers are legal and an object has one key.

```slate
h2Respond(s, stream, { ":status": "200", "content-type": "application/json" }, body)

h2Respond(s, stream, [[":status", "200"], ["set-cookie", "a=1"], ["set-cookie", "b=2"]])
```

**They always arrive as pairs.** Two headers of one name are legal, and an object would silently keep
one of them — which is the shape of defect that makes request smuggling possible. A program that wants
an object folds the list itself, knowing what it discarded.

**A third element marks a field never-indexed**, which is a wire decision rather than a comment: an
attacker who can insert requests on a connection learns a secret header's value one character at a
time by watching whether his guess compressed, and keeping it out of the dynamic table is the defence.
`authorization` and `cookie` are the fields that want it.

```slate
h2Request(c, [[":method", "GET"], [":scheme", "https"], [":path", "/"],
    ["authorization", "Bearer …", true]])
```

**A header value is text and a number is refused rather than converted**, because a value is a string
on the wire — and converting silently would make `true` a header value too:

```slate
import { h2Client, h2Request } from slate:nghttp2

h2Request(h2Client(), { ":path": 12 })
```

```error
a header value is text
```

## What a session refuses, and how

**Bytes the peer got wrong are an ANSWER**, because a peer that speaks nonsense is the ordinary thing
a server deals with and a fault would take the server down with the connection:

```slate
import { h2Server, h2Receive } from slate:nghttp2

val s = h2Server()

print(h2Receive(s, toBytes("GET / HTTP/1.1\r\n\r\n")).error != "")
```

```output
true
```

**A handle you have closed is a defect in the program**, exactly as a closed socket is, so that one
faults — and says what was closed rather than naming an integer.

## Flow control, and back-pressure

A session extends its own windows as bytes arrive, which is right for a program that deals with a body
as fast as it reads one. A program that queues bodies, writes them to disk or hands them to something
slower wants the credit returned when the work is **done** — and that is what `h2Consume` is for. It
needs a session made for it, since a session that extends its own windows has nothing to report:

```slate
val s = h2Server({ autoWindowUpdate: false })

// … a body arrives, is written away, and only then:
h2Consume(s, stream, len(bytes))
```

## HPACK on its own

The header-compression tier needs no session, and it is worth having by itself: it is the
security-relevant half of HTTP/2, identical whoever drives the frames, and a decoder that trusts its
input is a decompression bomb waiting for somebody to send it one.

```slate
import { hpackDeflater, hpackInflater, hpackDeflate, hpackInflate, hpackClose } from slate:nghttp2

val enc = hpackDeflater()
val dec = hpackInflater()

val block = hpackDeflate(enc, { ":status": "200", "content-type": "text/plain" })

print(hpackInflate(dec, block))

// The dynamic table is what makes the second block of the same headers a fraction of the first.
val again = hpackDeflate(enc, { ":status": "200", "content-type": "text/plain" })

print(len(again) < len(block))

hpackClose(enc)
hpackClose(dec)
```

```output
[[":status", "200"], ["content-type", "text/plain"]]
true
```

**A deflater and an inflater are each a conversation, not a function.** The dynamic table is built from
every block that has gone through, so blocks must be given to one inflater **in the order they
arrived** — that is HPACK's design, and it is what makes the second request on a connection cost five
bytes where the first cost thirty-eight. A block that will not decode is an answer, `{ error }`, for
the reason a session's refusal is.

## Where this sits

**The module is named for the library and its names for the protocol**, which is
[`slate:llhttp`](llhttp.md)'s arrangement exactly — that one is `llhttp` and exports `httpParser` and
`httpFeed`. What the two have in common is the tier, a door onto somebody else's state machine, and
naming them the same way is what says so. It also leaves HTTP/2's own short name free for whatever a
program eventually wants to import, which is the reason the HTTP server is `slate:http` and not
`slate:llhttp`.

**`slate:nghttp2` is [`slate:llhttp`](llhttp.md)'s sibling**, and it is public for the same reason:
[`slate:http`](http.md) is the server a program wants, and these are the layers under whatever speaks
HTTP next. A server that takes both versions on one port, a client that keeps its connections, a
proxy, a gRPC endpoint — every one of those is an ordinary package rather than a change to slate.

**The protocol itself is [`sh.sysl.nghttp2`](https://github.com/sysl-lang/nghttp2)**, the library
curl, Apache and Envoy use. slate adds no HTTP/2 of its own: what is here converts values at the
boundary and nothing else, which is the same arrangement `slate:redis` and `slate:llhttp` have with
their own bindings.
