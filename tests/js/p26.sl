// `slate:net` and `slate:http`, on both back ends.
//
// **The whole of `slate:net` was OWED under `slate js` until 0.0.31**, so nothing above a socket ran
// there at all — `slate:http` is written in slate over these names, and a framework checking its
// router by rendering a page through a real request had two tests skipping on every run.
//
// **A client needs a server, and this program is both.** That is what makes a socket testable as a
// corpus file at all: the listener asks the kernel for a port, the client reads it back with
// `localPort`, and everything happens inside one program that is run twice and diffed.
//
// **Nothing here pins a port and nothing here pins a timing.** The addresses and the ordering are
// the host's; what is compared is what the two back ends say about the bytes.

import { listen, connect, onData, onBytes, send, close, localPort, remoteAddress,
    alpnProtocol } from slate:net
import { serve, close as shutServer } from slate:http
import { httpParser, httpStream, httpFeed, httpTake, httpTakePart, httpClose,
    httpUpgraded } from slate:llhttp

// -- a socket carries text -------------------------------------------------------------------------

async echoOnce()
    val server = listen(0, conn ->
        onData(conn, chunk ->
            if chunk == null
                close(conn)
            else
                send(conn, "echo: " + chunk)))

    // **A port of `0` asks the kernel for one**, and this is how a program finds out which.
    print("a port was chosen", localPort(server) > 0)

    val dialled = await connect("127.0.0.1", localPort(server))

    print("connected", dialled.ok)

    val client = dialled.value
    var said = ""

    onData(client, chunk ->
        if chunk != null
            said = chunk
            close(client)
            close(server))

    await send(client, "hello")

    // The reply lands on a later turn of the loop, so the program waits for it rather than for a
    // number of milliseconds.
    var turns = 0

    while said == "" && turns < 200
        await sleep(10)
        turns = turns + 1

    print("heard", said)

// -- a socket carries bytes, and the reader that reads them ------------------------------------------

async bytesOnce()
    val server = listen(0, conn ->
        onBytes(conn, chunk ->
            if chunk == null
                close(conn)
            else
                send(conn, [chunk[0] + 1, chunk[1] + 1])))

    val dialled = await connect("127.0.0.1", localPort(server))
    val client = dialled.value
    var got = null

    onBytes(client, chunk ->
        if chunk != null
            got = chunk
            close(client)
            close(server))

    await send(client, [1, 2])

    var turns = 0

    while got == null && turns < 200
        await sleep(10)
        turns = turns + 1

    print("bytes", toJSON(got))

// -- what a listener is, and what it is not ----------------------------------------------------------

async shapeOfASocket()
    val server = listen(0, conn -> close(conn))

    // A listener has no other end, and saying so is an answer rather than a failure.
    print("a listener has no peer", remoteAddress(server))

    // **A plain socket has agreed no application protocol**, which is what `slate:http` reads to
    // tell HTTP/2 from HTTP/1.1 — and the answer being `null` is why every plain server works.
    print("no alpn", alpnProtocol(server))

    close(server)

    // Closing twice is fine: a server closing its connections and a read callback closing its own
    // is the ordinary way to write this.
    close(server)

    print("closed twice", true)

    // Everything else refuses a socket that has been given back, in the same words on both hosts.
    print(localPort(server) catch e -> e.message)
    print(send(server, "x") catch e -> e.message)
    print(onData(server, (c) -> c) catch e -> e.message)

    // And a value that is not a socket at all is the other refusal.
    print(close(42) catch e -> e.message)
    print(localPort("a") catch e -> e.message)

// -- a real request, parsed and answered ---------------------------------------------------------------

async servedOnce()
    val server = serve(0, req ->
        { status: 200,
          headers: { "x-method": req.method, "x-path": req.path, "x-query": req.search },
          body: "you said " + req.body })

    val where = "http://127.0.0.1:" + string(localPort(server)) + "/notes?a=1"
    val answer = await fetch(where, { method: "POST", body: "hello" })

    shutServer(server)

    print("status", answer.value.status)
    print("method", answer.value.headers["x-method"])
    print("path", answer.value.headers["x-path"])
    print("query", answer.value.headers["x-query"])
    print("body", answer.value.body)

// -- the parser underneath, driven by hand -------------------------------------------------------------

parsedByHand()
    val p = httpParser(8192, 1048576)

    print("nothing yet", httpTake(p))
    print("fed", httpFeed(p, toBytes("POST /a?b=2 HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello")))

    val req = httpTake(p)

    print("method", req.method, "path", req.path, "search", req.search)
    print("host", req.headers["host"], "keepAlive", req.keepAlive, "upgrade", req.upgrade)
    print("body", req.body, "bytes", toJSON(req.bytes))
    print("and no more", httpTake(p))

    // **Two requests in one arrival are two requests**, which is what pipelining is and what a
    // buffer-at-a-time parser has to get right.
    httpFeed(p, toBytes("GET /one HTTP/1.1\r\n\r\nGET /two HTTP/1.1\r\n\r\n"))
    print("pipelined", httpTake(p).path, httpTake(p).path, httpTake(p))

    // A chunked body arrives in pieces and is one body.
    httpFeed(p, toBytes("POST /c HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n2\r\n, \r\n0\r\n\r\n"))
    print("chunked", httpTake(p).body)

    // A head split across two arrivals is still one head.
    httpFeed(p, toBytes("GET /sp"))
    print("half a head", httpTake(p))
    httpFeed(p, toBytes("lit HTTP/1.1\r\n\r\n"))
    print("the other half", httpTake(p).path)

    httpClose(p)

refusedByHand()
    // **The classic request-smuggling shape**, and the refusal is an answer rather than a fault.
    val a = httpParser(8192, 1048576)
    val two = httpFeed(a, toBytes("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"))

    print("two lengths", two.status, two.message != null)

    val b = httpParser(8192, 1048576)
    val both = httpFeed(b, toBytes("GET / HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n"))

    print("length and encoding", both.status)

    val c = httpParser(8192, 1048576)

    print("not a request", httpFeed(c, toBytes("hello there\r\n\r\n")).status)

    // **A head over the limit is 431 and not 400**, which is HTTP this server decided not to hold
    // rather than a client that is broken; a body over its limit is 413 for the same reason.
    val d = httpParser(64, 1048576)

    print("head too big", httpFeed(d, toBytes("GET / HTTP/1.1\r\nX: " + repeat("y", 200) + "\r\n\r\n")).status)

    val e = httpParser(8192, 4)

    print("body too big", httpFeed(e, toBytes("POST / HTTP/1.1\r\nContent-Length: 9\r\n\r\nfar too much")).status)

    // A version nothing here speaks.
    val f = httpParser(8192, 1048576)

    print("wrong version", httpFeed(f, toBytes("GET / HTTP/9.9\r\n\r\n")).status)

    // An id nothing made answers emptily rather than reaching a live connection.
    print("no such parser", httpTake(9999), httpUpgraded(9999), httpFeed(9999, [65]))

    print("what they take", httpUpgraded("p") catch e -> e.message)
    print("how many they take", httpUpgraded() catch e -> e.message)

streamedByHand()
    val p = httpStream(8192)

    httpFeed(p, toBytes("POST /s HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"))

    val head = httpTakePart(p)

    print("head", head.kind, head.method, head.path, head.upgrade)

    val body = httpTakePart(p)

    print("body", body.kind, fromBytes(body.chunk).value)
    print("end", httpTakePart(p).kind)
    print("no more", httpTakePart(p))

    httpClose(p)

upgradedByHand()
    val p = httpParser(8192, 1048576)
    val handshake = "GET /ws HTTP/1.1\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n"

    httpFeed(p, toBytes(handshake + "frame"))

    val req = httpTake(p)

    print("upgrade", req.upgrade, req.path)

    // **It is an offset into that feed**, so what is past it is the other protocol's first bytes.
    print("where the http stopped", httpUpgraded(p) == len(toBytes(handshake)))

    httpClose(p)

async main()
    await echoOnce()
    await bytesOnce()
    await shapeOfASocket()
    await servedOnce()

    parsedByHand()
    refusedByHand()
    streamedByHand()
    upgradedByHand()

main()
