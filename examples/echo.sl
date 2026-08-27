// A server and a client in one program, which is what one event loop makes easy.
//
// `connect` and `send` answer promises, because each is one attempt with one outcome. `listen` and
// `onData` take callbacks, because a listener does not have one connection and a connection does not
// have one chunk.

// A port of `0` asks the kernel for one, and `localPort` says which it gave.
val server = listen(0, conn ->
    onData(conn, chunk ->
        // The end of the stream is `null`, not a failure -- a peer closing its half is how a
        // request ordinarily ends.
        if chunk == null
            close(conn)
        else
            print("server heard:", chunk)
            send(conn, "echo: " + chunk)))

val port = localPort(server)

print("listening on a port the kernel picked:", port > 0)

async main()
    val client = await connect("127.0.0.1", port)

    onData(client, chunk ->
        if chunk != null
            print("client heard:", chunk)

            // **Nothing here is optional.** A socket keeps the program alive exactly as a timer
            // does, so a program that never closes its sockets never exits.
            close(client)
            close(server))

    await send(client, "hello")

main()
