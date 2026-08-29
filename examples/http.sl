// An HTTP server and the requests a program makes itself, both on the loop slate already has.
//
// A handler is a function from a request to a response. A string is a whole response; an object says
// more. Nothing here is a framework: routing is `if req.path == ...`, because slate can already do
// that and a router that only ever called `startsWith` would be a thing to learn for nothing.

val server = serve(8080, async req ->
    if req.path == "/"
        "try /greet?name=Ada or POST to /echo"
    elif req.path == "/greet"
        "hello, " + (req.query.replace("name=", "") ?? "world")
    elif req.path == "/echo" && req.method == "POST"
        { status: 200, headers: { "Content-Type": "text/plain" }, body: req.body }
    elif req.path == "/slow"
        await sleep(50)

        "worth the wait"
    else
        { status: 404, body: "no such path" })

// `fetch` answers a result, as everything that reaches the network here does. A 404 is a success --
// the server answered, and what it said is the answer; an error means there was no answer at all.

async main()
    val greeting = await fetch("http://127.0.0.1:8080/greet?name=Ada")

    print(greeting.value.status, greeting.value.body)

    val echoed = await fetch("http://127.0.0.1:8080/echo", { method: "POST", body: "sent from slate" })

    print(echoed.value.body)

    val slow = await fetch("http://127.0.0.1:8080/slow")

    print(slow.value.body)

    val missing = await fetch("http://127.0.0.1:8080/nowhere")

    print(missing.ok, missing.value.status, missing.value.body)

    val refused = await fetch("http://127.0.0.1:9/")

    print(refused.ok, refused.error)

    // A server keeps the program alive, so closing it is what lets this one end.
    close(server)

main()
