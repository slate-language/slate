# `slate:net`

TCP, and TLS at both ends.

```
import { listen, connect, onData, onError, send, close, localPort, startTls } from slate:net

val server = listen(0, conn ->
    onData(conn, chunk ->
        if chunk == null
            close(conn)
        else
            send(conn, "echo: " + chunk)))

async main()
    val client = (await connect("127.0.0.1", localPort(server))).value

    onData(client, chunk ->
        if chunk != null
            print(chunk)
            close(client)
            close(server))

    await send(client, "hello")

main()
```

| | |
|---|---|
| `listen(port, fn)` or `listen({ port, cert, key, alpn }, fn)` | a server |
| `connect(host, port)` | a promise of a result |
| `onData(sock, fn)` | each chunk as text, and `null` at the end |
| `onBytes(sock, fn)` | the same reader for something that is not text |
| `onError(sock, fn)` | a sentence, *instead of* that `null` |
| `send(sock, v)` | a promise of a result; an **array is sent as bytes** |
| `close(sock)` | |
| `localPort(server)` | |
| `startTls(sock, options)` | a promise that settles when the handshake finishes |

## Promises and callbacks

**`connect` and `send` answer promises of a result; `listen`, `onData` and `onBytes` take callbacks.**
That split is not a matter of taste: a connect and a send are each one attempt with one outcome, which is
what a promise is, and a listener does not have one connection any more than a connection has one chunk.

A refused connection is the ordinary thing a client handles, so it comes back as `{ ok: false, error: … }`
rather than stopping the program.

**`onData` hands over `null` once the peer has finished sending** — the end of a stream is a value here
rather than a failure, because a peer closing its half is how a request ordinarily ends. **Calling either
reader a second time replaces the function** rather than adding one, which is what makes a protocol that
changes what it expects halfway through writable at all.

**A socket that fails ends its stream — it does not stop the program.** A connection reset is something any
peer can produce, so it arrives as the same `null` a peer that finished sends: `if chunk == null then
close(c)` is right either way. `onError` is how a program tells the two apart, and one that never registers
a handler never hears about it. It is a registration of its own rather than a third argument to `onData`
**because `onData` replaces its callback**.

## Ports and names

A port of `0` asks the kernel to pick one and `localPort` says which.

**`connect` takes a name or an address**, resolving through libuv's resolver on its thread pool. A name that
does not resolve settles the promise the way a refused connection does, rather than raising.

## Lifetime

**A socket keeps the program alive, exactly as a timer does**, so `close` is not optional; a program that
leaves one open never exits. **Closing twice is fine**, which is what lets a server close its connections
while a read callback closes its own.

**A closed socket is not whatever opens next.** The value a program holds carries the generation that
claimed its slot, so a socket held across a `close` never comes to mean its successor.

## TLS

A listener told a certificate hands out connections whose bytes are already decrypted, so
[`slate:http`](http.md) — and any other protocol written over these sockets — is an HTTPS server without
learning that TLS exists:

```
val server = listen({ port: 8443, cert: pem, key: keyPem }, conn -> …)
```

**TLS is a transport and not an HTTP concern**, which is why it goes under `listen` rather than beside
`serve`. node splits it the other way, with an `https` module beside `http`; node's `https` is literally
`http` over a `tls.Server`, and putting the seam one layer down is that arrangement with the duplication
left out. `alpn` beside them offers a protocol list.

**The other end is `startTls`, which upgrades a socket that is already open:**

```
async main()
    val db = (await connect("db.example.com", 5432)).value

    onBytes(db, read)

    val up = await startTls(db, { host: "db.example.com", trust: authority })

    if !up.ok then print(up.error)
```

**An upgrade rather than a flag on `connect`, because that is what protocols actually do.** TLS from byte
zero is one case and not the general one: PostgreSQL sends eight bytes in the clear and reads one back
before any handshake, SMTP has `STARTTLS`, IMAP and FTP have their own, and a WebSocket over TLS is HTTPS
first. It is also the weaker primitive — TLS from the start is `connect` and then this — so one builtin
covers both where a flag would have covered neither.

**A server upgrades its end the same way**, with the certificate and key `listen` would have taken:

```
startTls(conn, { cert: pem, key: keyPem })
```

There is no third argument saying which end this is: a client has a name to check and a server has a
certificate to present, and neither object could be mistaken for the other.

Everything after the handshake is unchanged: `send` takes plaintext, the reader is handed plaintext, and a
program that writes before awaiting has its bytes queued rather than lost.

**The name is checked against the certificate and there is no way to say otherwise.** It goes out as SNI,
without which a shared host does not know which certificate to send, and it is what the certificate's names
are verified against. An address works too and is checked against the certificate's addresses rather than
its names — which is why `connect` resolving matters here rather than being a convenience: verify against
the name the program was looking for, not the address the resolver happened to answer with.

**`trust` is added to the machine's own store rather than put in place of it**, so naming a private
authority does not stop verifying everything else the program talks to.
