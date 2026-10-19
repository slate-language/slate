// `req.address` on a connection that carries more than one request, on both back ends.
//
// **The address is the same for every request a connection carries**, and the HTTP speakers ask the
// socket for it once rather than once per request. What a handler sees must not have changed with
// that, so the first request and the second on one kept connection both say `127.0.0.1` -- the
// `::ffff:` form a dual-stack listener reports is taken off -- and so does a request on a second
// connection. Nothing here pins a port.

import { connect, onData, send, close, localPort } from slate:net
import { serve, close as shutServer } from slate:http

// Two requests written together onto one connection, the second ending it, and what the handler said
// of each: the address it was given, between angle brackets.
async ask(port)
    val dialled = await connect("127.0.0.1", port)
    val c = dialled.value
    var got = ""
    var ended = false

    onData(c, chunk ->
        if chunk == null
            close(c)
            ended = true
        else
            got = got + chunk)

    val one = "GET /a HTTP/1.1\r\nHost: h\r\n\r\n"
    val two = "GET /b HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n"

    await send(c, one + two)

    var turns = 0

    while !ended && turns < 400
        await sleep(10)
        turns = turns + 1

    got

said(answer) = split(answer, "<127.0.0.1>").length - 1

async main()
    val server = serve(0, req -> { status: 200, body: "<" + req.address + ">" })
    val port = localPort(server)

    print("one connection, requests answered with the right address:", said(await ask(port)))
    print("a second connection:                                      ", said(await ask(port)))

    shutServer(server)

main()
