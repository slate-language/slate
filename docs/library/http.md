# `slate:http`

An HTTP server, written in slate over [`slate:net`](net.md).

```slate
import { serve, close } from slate:http

val server = serve(8080, req -> "hello")
```

| | |
|---|---|
| `serve(port, handler, onUpgrade = null)` | the whole request, body included |
| `serveStream(port, handler, onUpgrade = null)` | the head, then the body in pieces |
| `close(server)` | stop serving, and end the connections |
| `router()` | |
| `files(root, options = {})` | a handler serving a directory |
| `setCookie(name, value, options = {})` | a header value |
| `parseQuery(s)`, `parseForm(body)`, `parseCookies(header)` | |
| `encodeComponent(s)`, `percentDecode(s, plusIsSpace)` | [`slate:url`](url.md)'s, forwarded |

`Request`, `Response` and `Router` are exported as [types](../reference/types.md) too.

**`parseQuery`, `encodeComponent` and `percentDecode` are [`slate:url`](url.md)'s** and are exported
here as well, so nothing written against this module changed. **Import them from `slate:url` in
anything that is not a server** — a browser page importing this module to reach them grows by 239 KB,
which is a file server and an HTTP/2 speaker downloaded to read a query string.

The third argument to either server is for a protocol upgrade — see [`slate:ws`](ws.md).

**HTTPS is `listen` told a certificate**, so `serve` did not have to change: TLS lives one layer down.

## `close(server)`

**Closing a server stops it accepting, closes every idle connection it had accepted at once, and lets a
connection with a request in flight finish that response before closing it.** There is no keep-alive
after `close`: a second request on a connection that was busy is not served, and the connection ends
with the response it was writing.

That is what makes `close` the thing that lets a program exit. A connection is a handle the event loop
waits on, so closing only the listening socket would leave a program that had shut everything down
still waiting — on connections whose clients may already be gone.

**A connection nobody is using is closed by the server anyway, after five seconds**, over either
version. A client may keep a connection and then simply go away, and without that clock the socket
would be held for the life of the server.

## The request

`method`, `path`, `search` (the raw text after the `?`), `query`, `cookies`, `params`, `body` where the
server read one, `keepAlive`, `upgrade`.

- **`search` and `query` are the URL API's two names.** A program wanting the raw text still has it —
  which matters because **a repeated name in `query` is the last one**. That is a decision: an array where
  a name repeats makes the *type* of `q.name` depend on what a client sent, so a program that read it as a
  string works until somebody sends the field twice.
- **`params` and `cookies` are `{}` rather than absent**, because a field that is there only sometimes is
  one every handler must test for.
- **Percent-decoding works over bytes**, `%C3%A9` being two bytes that are one character, and answers its
  input unchanged where the bytes are not text — a query string is something a peer wrote, and a fault
  there would let any peer stop a program.

## The answer

A handler answers a string, an object, or an **array of bytes**:

```slate
serve(3000, req -> "hello")
serve(3000, req -> { status: 201, headers: { "X-Kind": "note" }, body: toJSON(v) })
serve(3000, req -> { headers: { "Content-Type": "image/png" }, body: pngBytes })
```

**An array body is sent as it stands**, which is what serves an image, a font or a pre-compressed asset.
`toJSON(xs)` is what an array of data has to be.

**A header whose value is an array is written once per element**, which is the only way to say
`Set-Cookie` twice: an object has one value per name and HTTP does not. `Link`, `Vary` and `Via` all
repeat.

## `serveStream`

The handler is called as soon as a request's **head** is complete and is given the body as it arrives, so
the memory a request costs stops depending on how big the request is:

```slate
serveStream(3000, async (req) ->
    var total = 0

    for await chunk in req
        total = total + len(chunk)

    "that was " + string(total) + " bytes")
```

**`for await` is the shape to reach for**, and `req.each(fn)` is the same bytes pushed instead of
pulled — it answers a promise for the byte count, which is the one number an upload handler usually
wants:

```slate
serveStream(3000, async (req) ->
    counted(c) = c

    val n = await req.each(counted)

    "that was " + string(n) + " bytes")
```

**Two exports rather than one with an option**, because the two differ by *what the handler is given*
rather than by what the server was told — a streamed request having no `body` and answering `each`
instead. Everything else about the connection is the same server: the same keep-alive rule, the same
order, the same clock.

## A response that arrives in pieces

**A handler may answer a source** — a generator, or anything with a `next()`, which is what
[`for await`](../reference/asynchrony.md) drives — and the server writes it as chunked transfer as
the pieces arrive:

```slate
counting()
    yield "one "
    yield "two "
    yield "three"

app.get("/count", req -> counting())
app.get("/big", req -> { status: 202, headers: { "X-Kind": "report" }, body: rows() })
```

- **No `Content-Length` and no compression.** Both are facts about the last piece, and a server that
  buffered the body to find them out would be undoing what streaming is for.
- **A piece may be text or bytes**, exactly as a whole body may.
- **A source that faults mid-stream ends the response and the fault is put back.** The client sees a
  chunked body with no terminator, which is the only thing HTTP can say once the status line has
  gone, and the defect stops the program as any other does.
- **Both versions carry one.** Over HTTP/1.1 the pieces are chunks and over HTTP/2 they are DATA
  frames, and nothing a handler wrote says which.

### A source is told when its reader has gone

**A source may have a `close`, and the server calls it where the response ends with the source
unexhausted** — the client hung up, the socket was closed under the response, the peer reset the
stream, or the source itself faulted. A source that ran to `done` is told nothing, having finished.

```slate
subscribe(topic)
    val q = queue()

    async pull()
        { done: false, value: await q.take() }

    shut()
        forget(topic, q)

    { next: pull, close: shut }

app.get("/events", req -> sse(subscribe("orders")))
```

**It is optional and is asked for exactly as `next` is**, so every source already written keeps
working: a generator has no `close` and is left alone, and so is an object that does not name one.

**Without it, a subscription outlives its reader for the life of the program.** That is the shape a
source usually has — a topic, a query, a tail of a file — and a writer that simply stopped pulling
left the thing behind it holding a reader that would never read again. `sse` forwards the message to
the source it was given, so an event stream gets it through the wrapper.

**It is called once.** There are several ways a streamed response can end early, and a source that
counted its own readers would go wrong if any of them said so twice.

## `sse(source)`

Server-sent events, which is a streamed response with one format on top of it:

```slate
import { sse } from slate:http

app.get("/events", req -> sse(ticks()))
app.get("/quiet", req -> sse(ticks(), { heartbeat: 0 }))
```

A piece may be a **string**, which is its data, or an **object** naming any of `event`, `id`, `retry`
and `data` — and a `data` that is not a string is JSON, which is what a browser's
`JSON.parse(e.data)` wants anyway. **Every line of the data is prefixed**, a bare newline inside one
being what would otherwise end the event.

**`heartbeat` is a member of the response, not something the server guesses.** `sse` sets it to 15
seconds; the writer sends `: keep-alive` on that interval while nothing else is going down the
stream, which is what keeps a proxy from closing an idle connection. `0` turns it off, and any
streamed response may ask for one:

```slate
{ status: 200, headers: { "Content-Type": "text/plain" }, heartbeat: 30, body: rows() }
```

## HTTP/2

**A server that was given a certificate and an `alpn` list speaks either version, and the handler is
written once.** What decides is ALPN and nothing else: `h2` and `http/1.1` arrive on one port over one
socket, and HTTP/2's own preface is bytes a malformed HTTP/1.1 request could also begin with.

```slate
serve({ port: 8443, cert: pem, key: keyPem, alpn: ["h2", "http/1.1"] }, app)
```

- **The `Request` is the same value.** `method`, `path`, `search`, `query`, `cookies`, `params` and
  `headers` are all filled in the same way, and a reply may be a string, an object or an array of
  bytes exactly as before — the same compression rule and the same header rules apply.
- **`:authority` arrives as `host`**, so a handler reading `req.headers.host` need not know which
  version it was spoken to over.
- **Repeated `cookie` fields are joined with `"; "`**, which RFC 9113 §8.2.3 asks for: HTTP/2 lets a
  client split its cookies one per field so that each compresses on its own, and browsers do. Every
  other repeated header name keeps the last, which is what the HTTP/1.1 path does with one.
- **A body is bounded by the same megabyte the HTTP/1.1 server applies**, and one past it is answered
  `413` — the limit a program thinks it has is the same limit on both versions of one listener.
- **`keepAlive` is always `true`** and there is no pipelining question: a connection carries many
  streams at once and each is answered on its own.
- **A header name goes out lowercased**, an upper-case field name being malformed in HTTP/2 rather
  than merely unconventional. On HTTP/1.1 what you wrote is what is sent.
- **A streamed response goes out as a DATA frame per piece**, and `sse` works with its heartbeat —
  the head is sent before the source is asked for anything, which is what lets a response whose
  source never ends say `200` at all.
- **`serveStream` hands the body over as it lands**, one arrival per DATA frame, and a stream the
  peer resets ends the body the handler is reading rather than leaving it waiting.

**Without a certificate there is no ALPN and nothing changes** — `h2c`, which is HTTP/2 in the clear,
is not spoken here. The framing layer on its own is [`slate:nghttp2`](nghttp2.md).

## `router()`

**A router is an ordinary object holding functions, and `serve` asks an object for its `handle`** — so
`serve(3000, app)` works and nothing in the server knows what routing is.

```slate
val app = router()

app.get("/notes/:id", req -> find(req.params.id))
app.post("/notes", req -> create(req.body))
app.any("/health", req -> "ok")
app.notFound(req -> { status: 404, body: "nothing here" })

serve(3000, app)
```

`get`, `post`, `put`, `patch`, `delete`, `head`, `options`, `any`, and `notFound`. Patterns take `:name`
and `*rest`.

- **Routes are tried in the order they were added**, the only rule a reader can predict.
- **A path that is there under another method is `405` with an `Allow`**, not `404` — the difference
  between a client being told what to send and being told the thing is not there.
- **No middleware, and that is a decision.** A chain each link may short-circuit is a control flow of its
  own to learn; `app.get("/x", authed(handler))` says what it does at the site that needs it.

## `files(root)`

Serves a directory.

- **`ETag` and `If-None-Match`, deliberately not `Last-Modified`.** A validator a client never received is
  one it can never send, so the two are not both needed — and the older pair costs an HTTP date, a
  rendering in English of a moment in one zone.
- **The tag is the size and the modification time, not a hash of the contents.** Hashing a file per request
  is what a static server exists not to do.
- **A path that climbs out is refused and not sanitised.** A missing file and a directory with no index
  answer the same `404`, telling a client which is which mapping out the disk for it.

## Compression

**A response is compressed without asking the handler.** Every browser sends `Accept-Encoding: br` before
`gzip`, and a server that made this a per-handler choice would be making everybody write the same three
lines.

- **Over a kilobyte, at quality 5.** Below that [brotli](brotli.md) usually makes a body *larger*, having a
  frame to write.
- **A body that does not get smaller is sent as it was.**
- **`Vary: Accept-Encoding` goes on whether or not this one was compressed**, on every response that
  consulted the header. What a cache must not do is hand a compressed body to a client that did not ask,
  and it cannot know that unless the response says so.
- **The escape hatch is to set `Content-Encoding` yourself**, which says the body is already encoded. It is
  the only one.
- **`Accept-Encoding` is split into tokens** rather than searched for two letters, so `br;q=0` is a client
  saying it would rather not — which is not the same as not mentioning it.
