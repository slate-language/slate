// `startTls` on both back ends, at both ends of one upgrade.
//
// **The upgrade is PostgreSQL's shape**: the client says something in the clear, the server answers
// one byte, and then both ends call `startTls` on the socket they already hold — the client with a
// name to check, the server with a certificate and a key. Everything here is one program run twice
// and diffed, the listener and the client in the same process.
//
// **A certificate that does not verify is described in each host's own words** after slate's own
// `the TLS handshake failed:`, so what is printed about a failure is whether it named the right
// thing, never the sentence itself.

import { readFileSync } from slate:fs
import { listen, connect, onData, send, close, localPort, startTls, alpnProtocol } from slate:net

val theCert = readFileSync("tests/tls/cert.pem").value
val theKey = readFileSync("tests/tls/key.pem").value
val otherKey = readFileSync("tests/tls/other-key.pem").value

// Wait for something a callback will do, a turn of the loop at a time.
async waitFor(ready)
    var turns = 0

    while !ready() && turns < 300
        await sleep(10)
        turns = turns + 1

// A server that answers the first thing it hears with `S`, upgrades, and then echoes.
negotiating(serverSide)
    listen(0, conn ->
        var secured = false

        onData(conn, chunk ->
            if chunk == null
                close(conn)
            else if secured
                send(conn, "echo: " + chunk)
            else
                secured = true

                send(conn, "S")
                startTls(conn, serverSide)))

// The client half: ask, read the `S`, upgrade with `clientSide`, then say `hello`.
async upgradeAgainst(serverSide, clientSide)
    val server = negotiating(serverSide)
    val c = (await connect("127.0.0.1", localPort(server))).value
    var heard = []

    onData(c, chunk ->
        if chunk != null then heard.push(chunk))

    await send(c, "SSLRequest")
    await waitFor(() -> heard.length > 0)

    val up = await startTls(c, clientSide)

    if up.ok
        await send(c, "hello")
        await waitFor(() -> heard.length > 1)

    val protocol = if up.ok then alpnProtocol(c) else null

    close(c)
    close(server)

    { up: up, heard: heard, protocol: protocol }

// -- the upgrade, and what goes over it -------------------------------------------------------------

async upgraded()
    val r = await upgradeAgainst({ cert: theCert, key: theKey }, { host: "localhost", trust: theCert })

    print("upgraded", r.up.ok, r.up.value)
    print("heard", r.heard)
    print("no protocol was offered", r.protocol)

async negotiatedAProtocol()
    val r = await upgradeAgainst({ cert: theCert, key: theKey, alpn: ["h2", "http/1.1"] },
        { host: "localhost", trust: theCert, alpn: ["h2", "http/1.1"] })

    print("negotiated", r.up.ok, r.protocol)

// -- a certificate that is not checked out ------------------------------------------------------------

async untrusted()
    val r = await upgradeAgainst({ cert: theCert, key: theKey }, "localhost")

    print("untrusted", r.up.ok, r.up.error.contains("certificate"), r.up.error.startsWith("the TLS handshake failed"))

async wrongName()
    val r = await upgradeAgainst({ cert: theCert, key: theKey }, { host: "example.com", trust: theCert })

    print("wrong name", r.up.ok, r.up.error.startsWith("the TLS handshake failed"))

// -- the server end refusing its own certificate -----------------------------------------------------

async mismatchedKey()
    var said = null

    val server = listen(0, conn ->
        onData(conn, chunk -> chunk)

        async upgrade()
            said = await startTls(conn, { cert: theCert, key: otherKey })
            close(conn)

        upgrade())

    val c = (await connect("127.0.0.1", localPort(server))).value

    onData(c, chunk -> chunk)
    await send(c, "hi")
    await waitFor(() -> said != null)

    print("mismatched key", said.ok, said.error.contains("certificate and key"))

    close(c)
    close(server)

// -- a peer that is not speaking TLS at all ------------------------------------------------------------

async hungUp()
    val server = listen(0, conn -> close(conn))
    val c = (await connect("127.0.0.1", localPort(server))).value

    onData(c, chunk -> chunk)

    val up = await startTls(c, "localhost")

    print("hung up", up.ok, up.error.contains("handshake"))

    close(c)
    close(server)

// -- writing before the handshake has finished -------------------------------------------------------

async sentEarly()
    val server = listen(0, conn ->
        var secured = false

        onData(conn, chunk ->
            if chunk == null
                close(conn)
            else if secured
                send(conn, "echo: " + chunk)
            else
                secured = true

                send(conn, "S")
                startTls(conn, { cert: theCert, key: theKey })))

    val c = (await connect("127.0.0.1", localPort(server))).value
    var heard = []

    onData(c, chunk ->
        if chunk != null then heard.push(chunk))

    await send(c, "SSLRequest")
    await waitFor(() -> heard.length > 0)

    // **Not awaited**: what is written now waits for the handshake rather than going in the clear.
    startTls(c, { host: "localhost", trust: theCert })
    await send(c, "early")
    await waitFor(() -> heard.length > 1)

    print("sent early", heard)

    close(c)
    close(server)

// -- what is refused, in the same words on both hosts ---------------------------------------------------

async refusals()
    val server = negotiating({ cert: theCert, key: theKey })
    val c = (await connect("127.0.0.1", localPort(server))).value

    onData(c, chunk -> chunk)

    print(startTls(c, {}) catch e -> e.message)
    print(startTls(c, 42) catch e -> e.message)
    print(startTls(c, { host: 1 }) catch e -> e.message)
    print(startTls(c, { host: "localhost", trust: 5 }) catch e -> e.message)
    print(startTls(c, { host: "localhost", alpn: "h2" }) catch e -> e.message)
    print(startTls(c, { host: "localhost", alpn: [1] }) catch e -> e.message)
    print(startTls(c, { cert: theCert }) catch e -> e.message)

    // The first upgrade is under way, so the second is refused on the spot.
    startTls(c, { host: "localhost", trust: theCert })
    print(startTls(c, { host: "localhost", trust: theCert }) catch e -> e.message)

    close(c)
    close(server)

    print(startTls(c, "localhost") catch e -> e.message)
    print(startTls(42, "localhost") catch e -> e.message)

async main()
    await upgraded()
    await negotiatedAProtocol()
    await untrusted()
    await wrongName()
    await mismatchedKey()
    await hungUp()
    await sentEarly()
    await refusals()

main()
