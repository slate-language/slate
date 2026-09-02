// An HTTP server and the requests a program makes itself, both on the loop slate already has.
//
// A handler is a function from a request to a response. A string is a whole response; an object says
// more. Nothing here is a framework: routing is `if req.path == ...`, because slate can already do
// that and a router that only ever called `startsWith` would be a thing to learn for nothing.
//
// **`serve` is written in slate**, on the sockets `slate:net` has -- `slate:http` is a module carried
// in the binary rather than a native, the way node's `http` is JavaScript over its own C sockets.
// `fetch` is the half that is still native, https needing OpenSSL.

import { serve, close } from slate:http
import { localPort } from slate:net

// **A port of `0` asks the kernel for one, and `localPort` says which it gave.** A program you run
// yourself writes the port it wants; an example that has to work on a machine somebody else is
// already developing on cannot, 8080 being the first port a dev server takes.
val server = serve(0, async req ->
    if req.path == "/"
        "try /greet?name=Ada or POST to /echo"
    elif req.path == "/greet"
        "hello, " + (req.query.name ?? "world")
    elif req.path == "/echo" && req.method == "POST"
        { status: 200, headers: { "Content-Type": "text/plain" }, body: req.body }
    elif req.path == "/slow"
        await sleep(50)

        "worth the wait"
    else
        { status: 404, body: "no such path" })

val site = "http://127.0.0.1:" + string(localPort(server))

// `fetch` answers a result, as everything that reaches the network here does. A 404 is a success --
// the server answered, and what it said is the answer; an error means there was no answer at all.

async main()
    val greeting = await fetch(site + "/greet?name=Ada")

    print(greeting.value.status, greeting.value.body)

    val echoed = await fetch(site + "/echo", { method: "POST", body: "sent from slate" })

    print(echoed.value.body)

    val slow = await fetch(site + "/slow")

    print(slow.value.body)

    val missing = await fetch(site + "/nowhere")

    print(missing.ok, missing.value.status, missing.value.body)

    val refused = await fetch("http://127.0.0.1:9/")

    print(refused.ok, refused.error)

    // A server keeps the program alive, so closing it is what lets this one end.
    close(server)

main()
