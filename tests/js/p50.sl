// A secured `listen` on both back ends, and the refusals of `listen(socket, fn)`.
//
// **`listen({ port, cert, key, alpn }, fn)` hands out connections whose bytes are already decrypted**,
// so the server below is the same plain echo it would be without a certificate. The client reaches it
// with `startTls` straight after `connect`, which is the other end of the same handshake. Everything
// here is one program run twice and diffed, the listener and the client in the same process.
//
// **A failure is described in each host's own words**, so what is printed about a refusal is whether
// it named the right thing and never the whole sentence where the sentence is the host's.
//
// The accepting half of `listen(socket, fn)` needs a second program to pass the listener, so it is
// `tests_process.sysl`'s; what a single program can say about it, that a socket which is not a passed
// listener is refused, is here.

import { readFileSync } from slate:fs
import { listen, connect, onData, send, close, localPort, startTls, alpnProtocol } from slate:net

val theCert = readFileSync("tests/tls/cert.pem").value
val theKey = readFileSync("tests/tls/key.pem").value
val otherKey = readFileSync("tests/tls/other-key.pem").value

async waitFor(ready)
    var turns = 0

    while !ready() && turns < 300
        await sleep(10)
        turns = turns + 1

// A secured echo server, and a client that upgrades to talk to it.
async talkTo(options, clientSide)
    val server = listen(options, conn ->
        onData(conn, chunk ->
            if chunk == null
                close(conn)
            else
                send(conn, "echo: " + chunk)))

    val c = (await connect("127.0.0.1", localPort(server))).value
    var heard = []

    onData(c, chunk ->
        if chunk != null then heard.push(chunk))

    val up = await startTls(c, clientSide)

    if up.ok
        await send(c, "hello")
        await waitFor(() -> heard.length > 0)

    val protocol = if up.ok then alpnProtocol(c) else null

    close(c)
    close(server)

    { up: up, heard: heard, protocol: protocol }

async served()
    val r = await talkTo({ port: 0, cert: theCert, key: theKey }, { host: "localhost", trust: theCert })

    print("handshake", r.up.ok)
    print("heard", r.heard)
    print("no protocol was offered", r.protocol)

async negotiatedAProtocol()
    val r = await talkTo({ port: 0, cert: theCert, key: theKey, alpn: ["h2", "http/1.1"] },
        { host: "localhost", trust: theCert, alpn: ["h2", "http/1.1"] })

    print("negotiated", r.up.ok, r.protocol)

    val first = await talkTo({ port: 0, cert: theCert, key: theKey, alpn: ["http/1.1", "h2"] },
        { host: "localhost", trust: theCert, alpn: ["h2"] })

    print("client's only choice", first.up.ok, first.protocol)

async untrusted()
    val r = await talkTo({ port: 0, cert: theCert, key: theKey }, "localhost")

    print("untrusted", r.up.ok, r.up.error.startsWith("the TLS handshake failed"))

// The key may be bytes as well as text, as everywhere else a PEM is taken.
async keyAsBytes()
    val r = await talkTo({ port: 0, cert: theCert, key: toBytes(theKey) }, { host: "localhost", trust: theCert })

    print("key as bytes", r.up.ok, r.heard)

// A secured listener is a listener: it has a port, and closing it stops it.
async portAndClose()
    val server = listen({ port: 0, cert: theCert, key: theKey }, conn -> close(conn))
    val port = localPort(server)

    print("has a port", port > 0)

    close(server)
    close(server)

    print(localPort(server) catch e -> e.message)

// -- what is refused, in the same words on both hosts ---------------------------------------------------

refusedListeners()
    print(listen({ port: 0, cert: theCert, key: otherKey }, conn -> conn) catch e -> e.message.startsWith("this certificate and key could not be used"))
    print(listen({ port: 0, cert: theCert }, conn -> conn) catch e -> e.message)
    print(listen({ port: 0, cert: 5, key: theKey }, conn -> conn) catch e -> e.message)
    print(listen({ port: 0, cert: theCert, key: 5 }, conn -> conn) catch e -> e.message)
    print(listen({ port: 0, cert: theCert, key: theKey, alpn: "h2" }, conn -> conn) catch e -> e.message)
    print(listen({ port: 0, cert: theCert, key: theKey, alpn: [1] }, conn -> conn) catch e -> e.message)
    print(listen({ port: 0, cert: theCert, key: theKey, reusePort: 1 }, conn -> conn) catch e -> e.message)
    print(listen({ port: 0, cert: theCert, key: theKey }, 7) catch e -> e.message)

// `listen(socket, fn)` takes a socket another program was listening on and nothing else.
async refusedPassedListeners()
    val server = listen(0, conn -> conn)

    print(listen(server, conn -> conn) catch e -> e.message)

    val c = (await connect("127.0.0.1", localPort(server))).value

    print(listen(c, conn -> conn) catch e -> e.message)
    print(listen(server, 7) catch e -> e.message)

    close(c)
    close(server)

    print(listen(server, conn -> conn) catch e -> e.message)

async main()
    await served()
    await negotiatedAProtocol()
    await untrusted()
    await keyAsBytes()
    await portAndClose()
    refusedListeners()
    await refusedPassedListeners()

main()
