// `slate:http`'s two deadlines, and `httpHeading` under them, on both back ends.
//
// **A request's head has `headMillis` from its first byte and the whole request `requestMillis`**,
// and neither is moved by bytes arriving. The idle clock is: a head sent one byte at a time reset it
// with every byte and was held for ever. `tests_deadline.sysl` runs this file through the
// interpreter against a written answer, so the two back ends agreeing about a mistake they shared
// would still be caught.
//
// **Nothing here pins a timing.** Each server's other deadline is long, so a cut that came from the
// wrong clock would come after the client had stopped trying, and print differently.

import { connect, onData, send, close, localPort } from slate:net
import { serve, serveStream, close as shutServer } from slate:http
import { httpParser, httpStream, httpFeed, httpHeading } from slate:llhttp

// -- the parser's half ---------------------------------------------------------------------------------

heading()
    val p = httpParser(8192, 1048576)

    print("before a byte", httpHeading(p))

    httpFeed(p, toBytes("GET / HTTP/1.1\r\nHo"))
    print("part way through a head", httpHeading(p))

    httpFeed(p, toBytes("st: x\r\n\r\n"))
    print("after the blank line", httpHeading(p))

    httpFeed(p, toBytes("POST /u HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nab"))
    print("in a body", httpHeading(p))

    httpFeed(p, toBytes("cdeGET /b"))
    print("a pipelined head", httpHeading(p))

    val bad = httpParser(8192, 1048576)

    print("refused", httpFeed(bad, toBytes("GET / HTTP/1.1\r\nBad Name: x\r\n\r\n")).status)
    print("after a refusal", httpHeading(bad))

    print(httpHeading(httpStream(8192)) catch e -> e.message)
    print(httpHeading("p") catch e -> e.message)

// -- a client written by hand ------------------------------------------------------------------------
//
// What is under test is how a server treats bytes that arrive slowly, which no `fetch` can be asked
// to do.

async dial(port)
    val c = (await connect("127.0.0.1", port)).value
    val s = { conn: c, heard: "", gone: false }

    onData(c, chunk ->
        if chunk == null
            s.gone = true
        else
            s.heard = s.heard + chunk)

    s

// The status codes a connection was answered with, in order.
codes(s)
    val parts = s.heard.split("HTTP/1.1 ")
    var out = []
    var i = 1

    while i < parts.length
        out.push(parts[i][0..<3])
        i = i + 1

    join(out, ",")

answers(s) = s.heard.split("HTTP/1.1 ").length - 1

// Each piece `gap` milliseconds after the last, stopping once the server has hung up.
async dribble(s, pieces, gap)
    for p in pieces
        if s.gone then return

        try
            await send(s.conn, p)
        catch e
            return

        await sleep(gap)

// Wait for `n` answers or the server hanging up, whichever is first.
async until(s, n)
    var turns = 0

    while !s.gone && answers(s) < n && turns < 300
        await sleep(10)
        turns = turns + 1

// A first piece and then `n` single bytes.
trickle(first, n)
    var out = [first]
    var i = 0

    while i < n
        out.push("a")
        i = i + 1

    out

// -- what both servers are held to -------------------------------------------------------------------

async heldTo(name, quick, slow)
    // A head that never finishes is cut at the head's deadline. The request's is five seconds, and
    // the client gives up after a second and a half.
    val s1 = await dial(localPort(quick))

    await dribble(s1, trickle("GET / HTTP/1.1\r\nHost: x\r\nX-A: ", 15), 100)
    await until(s1, 1)
    print(name, "a slow head", codes(s1), "closed", s1.gone)
    close(s1.conn)

    // A head that finishes inside the deadline is answered.
    val s2 = await dial(localPort(quick))

    await dribble(s2, ["GET / HTTP/1.1\r\n", "Host: x\r\n\r\n"], 50)
    await until(s2, 1)
    print(name, "a head in time", codes(s2))
    close(s2.conn)

    // A kept connection's second request has deadlines of its own: the pause is longer than the
    // head's deadline, so one left over from the first request would cut the second.
    val s3 = await dial(localPort(quick))

    await send(s3.conn, "GET /one HTTP/1.1\r\nHost: x\r\n\r\n")
    await until(s3, 1)
    await sleep(400)
    await dribble(s3, ["GET /two HTTP/1.1\r\n", "Host: x\r\n", "\r\n"], 60)
    await until(s3, 2)
    print(name, "a kept connection", codes(s3), "closed", s3.gone)
    close(s3.conn)

    // A pipelined second head gets its own deadline once the first is answered.
    val s4 = await dial(localPort(quick))

    await dribble(s4, trickle("GET /a HTTP/1.1\r\nHost: x\r\n\r\nGET /b HTTP/1.1\r\nHost: x\r\nX-A: ", 15), 100)
    await until(s4, 2)
    print(name, "a pipelined slow head", codes(s4), "closed", s4.gone)
    close(s4.conn)

    // An upload slower than the head's deadline and faster than the request's is answered: only the
    // head is held to the short one.
    val s5 = await dial(localPort(quick))

    await dribble(s5, trickle("POST /up HTTP/1.1\r\nHost: x\r\nContent-Length: 8\r\n\r\n", 8), 100)
    await until(s5, 1)
    print(name, "a slow upload", codes(s5), s5.heard.split("got 8").length == 2)
    close(s5.conn)

    // A body that never finishes is cut at the request's deadline. The head's is five seconds.
    val s6 = await dial(localPort(slow))

    await dribble(s6, trickle("POST /up HTTP/1.1\r\nHost: x\r\nContent-Length: 40\r\n\r\n", 20), 100)
    await until(s6, 1)
    print(name, "a slow body", codes(s6), "closed", s6.gone)
    close(s6.conn)

// -- a deadline that is not a number -------------------------------------------------------------------

refused()
    print(serve({ port: 0, headMillis: "soon" }, req -> "x") catch e -> e.message)
    print(serve({ port: 0, requestMillis: 0 }, req -> "x") catch e -> e.message)

async main()
    heading()
    refused()

    val quick = serve({ port: 0, headMillis: 300, requestMillis: 5000 }, req -> "got " + string(req.bytes.length))
    val slow = serve({ port: 0, headMillis: 5000, requestMillis: 600 }, req -> "got " + string(req.bytes.length))

    await heldTo("serve", quick, slow)
    shutServer(quick)
    shutServer(slow)

    val counted = async (req) ->
        var n = 0

        for await chunk in req
            n = n + chunk.length

        "got " + string(n)

    val streamQuick = serveStream({ port: 0, headMillis: 300, requestMillis: 5000 }, counted)
    val streamSlow = serveStream({ port: 0, headMillis: 5000, requestMillis: 600 }, counted)

    await heldTo("serveStream", streamQuick, streamSlow)
    shutServer(streamQuick)
    shutServer(streamSlow)

main()
