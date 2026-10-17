// `shutdown` on both back ends: the write-side half-close, plain and over TLS.
//
// **One program run twice and diffed**, the listener and the client in the same process. The client
// says its piece, half-closes, and the server — which reads until the end of the stream — answers
// anyway; the client is still reading, so it hears the answer, and then the server's own end.
//
// **What is pinned is the contract**: `send` after `shutdown` refuses with a sentence, a second
// `shutdown` answers `{ ok: true }` again, `close` still works, and a secured socket half-closes the
// same way (the close-notify goes out first, which neither program can see and the peer's clean end
// of stream depends on).

import { readFileSync } from slate:fs
import { listen, connect, onData, send, shutdown, close, localPort, startTls } from slate:net

val theCert = readFileSync("tests/tls/cert.pem").value
val theKey = readFileSync("tests/tls/key.pem").value

// Wait for something a callback will do, a turn of the loop at a time.
async waitFor(ready)
    var turns = 0

    while !ready() && turns < 300
        await sleep(10)
        turns = turns + 1

// Answer once the client has finished speaking: the server's reply is sent AFTER the end of the
// stream was read, which is the whole of what a half-close is for.
async replied(conn, heard)
    await send(conn, "reply to " + heard)
    close(conn)

// A server that reads to the end of the stream and then answers. With `secure` it speaks the
// PostgreSQL shape first: one byte in the clear, then the upgrade, then the request.
serving(serverSide)
    listen(0, conn ->
        var heard = ""
        var secured = serverSide == null

        onData(conn, chunk ->
            if chunk == null
                replied(conn, heard)
            else if secured
                heard = heard + chunk
            else
                secured = true

                send(conn, "S")
                startTls(conn, serverSide)))

// The client half: say `hello`, half-close, then read to the end of the stream.
async halfClosed(serverSide, clientSide)
    val server = serving(serverSide)
    val c = (await connect("127.0.0.1", localPort(server))).value
    var heard = []
    var ended = false

    onData(c, chunk ->
        if chunk == null then ended = true else heard.push(chunk))

    if clientSide != null
        await send(c, "SSLRequest")
        await waitFor(() -> heard.length > 0)

        val up = await startTls(c, clientSide)

        print("upgraded", up.ok)

        heard = []

    val sent = await send(c, "hello")
    val first = await shutdown(c)
    val again = await shutdown(c)
    val after = await send(c, "more")

    await waitFor(() -> ended)

    print("sent", sent.ok)
    print("shutdown", first.ok, "twice", again.ok)
    print("send after", after.ok, after.error)
    print("heard", heard.join(""), "ended", ended)

    close(c)
    close(server)

async plain()
    await halfClosed(null, null)

async overTls()
    await halfClosed({ cert: theCert, key: theKey }, { host: "localhost", trust: theCert })

// A listener has no writing side, and a closed socket is not one to shut down.
async refused()
    val server = listen(0, conn -> close(conn))
    val onServer = await shutdown(server)

    print("listener", onServer.ok)

    val c = (await connect("127.0.0.1", localPort(server))).value

    close(c)
    close(server)

async main()
    await plain()
    await overTls()
    await refused()

main()
