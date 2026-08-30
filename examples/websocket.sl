// A WebSocket server, and a client written by hand to drive it.
//
// **The real client is a browser** -- four lines of JavaScript, and `demo/ui.sl` is that program.
// This one talks to itself so that it finishes, which is what lets it run beside the other examples.

import { serve, close } from slate:http
import { accept, framed, unframed } from slate:ws
import { connect, onBytes, send, localPort, close as shutSocket } from slate:net

// `serve` takes a third function now, and it is called when a request asks to stop being HTTP.
// Everything before that is the ordinary server: the handshake arrives as a `GET`, is parsed as one,
// and reaches here with the socket and whatever bytes came behind it.
val server = serve(0, req -> "this page would be your user interface",
    (req, socket, head) ->
        val opened = accept(req, socket, head)

        // A handshake that is not one is an answer, not a fault: a server on the open internet is
        // sent malformed requests as a matter of course.
        if !opened.ok
            print("refused:", opened.error)
            return

        val ws = opened.value

        ws.onMessage(m ->
            print("server heard:", m)
            ws.send("echo: " + m))

        ws.onClose((code, why) -> print("server closed:", code)))

val port = localPort(server)

// What a browser sends. Every frame a client sends is masked -- not for secrecy, but so that a
// hostile page cannot steer a proxy into reading payload bytes as a request of its own.
masked(opcode, payload)
    val key = [7, 11, 13, 17]
    var out = [0x80 | opcode, 0x80 | len(payload)]

    for b in key
        push(out, b)

    for i in 0..<len(payload)
        push(out, payload[i] ^ key[i % 4])

    out

// Where the head of a response ends, so the frames behind it are not read as text.
cut(bs)
    var i = 0

    while i + 3 < len(bs)
        if bs[i] == 13 && bs[i + 1] == 10 && bs[i + 2] == 13 && bs[i + 3] == 10 then return i

        i = i + 1

    0 - 1

async main()
    val opened = await connect("127.0.0.1", port)

    if !opened.ok
        print("could not connect:", opened.error)
        close(server)
        return

    val client = opened.value
    var got = []
    var upgraded = false

    onBytes(client, chunk ->
        if chunk == null then return

        got = concat(got, chunk)

        if !upgraded
            val at = cut(got)

            if at < 0 then return

            print("client heard:", split(fromBytes(got[0..<at]).value, "\r\n")[0])

            upgraded = true
            got = got[(at + 4)..]

            send(client, masked(1, toBytes("hello")))

        // A server's frames are not masked, and one arrival may hold more than one of them.
        val f = unframed(got, 0)

        if f == null then return

        got = got[f.size..]

        print("client heard:", fromBytes(f.payload).value)

        shutSocket(client)
        close(server))

    await send(client, "GET /socket HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n" +
        "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" +
        "Sec-WebSocket-Version: 13\r\n\r\n")

main()
