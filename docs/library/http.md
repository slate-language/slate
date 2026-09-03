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
| `close(server)` | |
| `router()` | |
| `files(root, options = {})` | a handler serving a directory |
| `setCookie(name, value, options = {})` | a header value |
| `parseQuery(s)`, `parseForm(body)`, `parseCookies(header)` | |
| `encodeComponent(s)` | |

`Request`, `Response` and `Router` are exported as [types](../reference/types.md) too.

The third argument to either server is for a protocol upgrade — see [`slate:ws`](ws.md).

**HTTPS is `listen` told a certificate**, so `serve` did not have to change: TLS lives one layer down.

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

    counted(c)
        total = total + len(c)

    await req.each(counted)

    "that was " + string(total) + " bytes")
```

**Two exports rather than one with an option**, because the two differ by *what the handler is given*
rather than by what the server was told — a streamed request having no `body` and answering `each`
instead. Everything else about the connection is the same server: the same keep-alive rule, the same
order, the same clock.

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
