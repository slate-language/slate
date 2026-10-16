// A `startTls` handshake drives itself, whenever the program starts reading.
//
// **The handshake's bytes are TLS's and not the program's**, so they are read whether or not the
// program has called `onData` yet -- and what arrives for the program before it has is held, and
// handed over once it does. The four cases are the reader registered after the handshake, the reader
// registered before it, a server that speaks the moment the handshake is done, and a handshake that
// fails with nobody reading at all. Everything here is one program run twice and diffed.

import { readFileSync } from slate:fs
import { listen, connect, onData, send, close, localPort, startTls } from slate:net

val theCert = readFileSync("tests/tls/cert.pem").value
val theKey = readFileSync("tests/tls/key.pem").value

async waitFor(ready)
    var turns = 0

    while !ready() && turns < 300
        await sleep(10)
        turns = turns + 1

// A secured echo server; `greeting`, where there is one, is sent the moment a connection arrives.
echoServer(greeting) = listen({ port: 0, cert: theCert, key: theKey }, conn ->
    if greeting != null then send(conn, greeting)

    onData(conn, chunk ->
        if chunk == null
            close(conn)
        else
            send(conn, "echo: " + chunk)))

// The same exchange with the reader put on before the upgrade or after it.
async exchange(readerFirst)
    val server = echoServer(null)
    val c = (await connect("127.0.0.1", localPort(server))).value
    var heard = []
    val reader = chunk -> if chunk != null then heard.push(chunk)

    if readerFirst then onData(c, reader)

    val up = await startTls(c, { host: "localhost", trust: theCert })

    if !readerFirst then onData(c, reader)

    if up.ok
        await send(c, "hello")
        await waitFor(() -> heard.length > 0)

    close(c)
    close(server)

    print(if readerFirst then "reader before" else "reader after", up.ok, heard)

// What the server sends straight after the handshake arrives before anybody is reading, and is
// delivered once somebody is -- in order, and ahead of what comes after it.
async heldUntilRead()
    val server = echoServer("welcome")
    val c = (await connect("127.0.0.1", localPort(server))).value
    val up = await startTls(c, { host: "localhost", trust: theCert })

    // Long enough for the greeting to have landed with no reader on the socket.
    await sleep(100)

    var heard = []

    onData(c, chunk -> if chunk != null then heard.push(chunk))

    print("nothing is delivered inside the call", heard)

    await waitFor(() -> heard.length > 0)
    await send(c, "hello")
    await waitFor(() -> heard.length > 1)

    close(c)
    close(server)

    print("held until read", up.ok, heard)

// A certificate nothing trusts still answers the promise, with no reader ever registered.
async refusedWithNoReader()
    val server = echoServer(null)
    val c = (await connect("127.0.0.1", localPort(server))).value
    val up = await startTls(c, "localhost")

    print("refused with no reader", up.ok, up.error.startsWith("the TLS handshake failed"))

    close(c)
    close(server)

// The server's end of the same rule: a secured `listen` whose connection callback reads late still
// finishes the handshake, and what the client sent in the meantime reaches the late reader.
async serverReadsLate()
    val server = listen({ port: 0, cert: theCert, key: theKey }, async conn ->
        await sleep(100)

        onData(conn, chunk ->
            if chunk == null
                close(conn)
            else
                send(conn, "late: " + chunk)))

    val c = (await connect("127.0.0.1", localPort(server))).value
    var heard = []

    onData(c, chunk -> if chunk != null then heard.push(chunk))

    val up = await startTls(c, { host: "localhost", trust: theCert })

    await send(c, "early")
    await waitFor(() -> heard.length > 0)

    close(c)
    close(server)

    print("server reads late", up.ok, heard)

async main()
    await exchange(false)
    await exchange(true)
    await heldUntilRead()
    await refusedWithNoReader()
    await serverReadsLate()

main()
