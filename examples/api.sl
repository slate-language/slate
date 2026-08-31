// An API server: routes, the query string, cookies, a form, and files off the disk.
//
// `examples/http.sl` is the server underneath this one -- a function from a request to a response,
// and a chain of `if req.path == ...`. This is what a program writes once there is more than one
// path: a router binds the parts of a path to names, and the request arrives with its query and its
// cookies already read.

import { serve, close, router, files, parseForm, setCookie } from slate:http
import { writeFileSync, mkdirSync, removeSync, rmdirSync } from slate:fs

// Something to serve. A real program has these on the disk already.
mkdirSync("./example-public")
writeFileSync("./example-public/style.css", "body { font-family: sans-serif }")

val app = router()

// A route's `:name` binds that part of the path, and `req.params` is where it lands.
app.get("/users/:id", (req) -> "user " + req.params.id)

// `req.query` is the text after the `?`, read. `req.search` is that text as it was sent, for the
// program that wants a name a client sent more than once.
app.get("/greet", (req) -> "hello, " + (req.query.name ?? "world"))

// A form body is the same grammar as a query string, and is parsed where a handler asks -- a body
// has a content type, and one that did not ask should not have a form made of it.
app.post("/signup", (req) ->
    val form = parseForm(req.body)

    { status: 201,
      headers: { "Set-Cookie": setCookie("who", form.name ?? "", { httpOnly: true, maxAge: 3600 }) },
      body: "signed up " + (form.name ?? "nobody") })

// A cookie the client sent is read off `req.cookies`, whether or not this program set it.
app.get("/whoami", (req) -> req.cookies.who ?? "nobody")

// `files` answers a handler, so the root is said once and the route decides what reaches it. A `*`
// takes the whole of the rest, slashes included, which is what a file server needs.
app.get("/assets/*rest", files("./example-public", { cacheControl: "max-age=300" }))

// A path nothing routes is 404; a path that is there under another method is 405, with `Allow`.
app.notFound((req) -> { status: 404, body: "no route for " + req.method + " " + req.path })

// `serve` takes the router itself, because it is an object with a `handle`.
val server = serve(8081, app)

async main()
    val user = await fetch("http://127.0.0.1:8081/users/42")

    print(user.value.body)

    val greeting = await fetch("http://127.0.0.1:8081/greet?name=Ada+Lovelace")

    print(greeting.value.body)

    val made = await fetch("http://127.0.0.1:8081/signup",
        { method: "POST", body: "name=Ada", headers: { "Content-Type": "application/x-www-form-urlencoded" } })

    print(made.value.status, made.value.body)

    val known = await fetch("http://127.0.0.1:8081/whoami", { headers: { Cookie: "who=Ada" } })

    print(known.value.body)

    val asset = await fetch("http://127.0.0.1:8081/assets/style.css")

    print(asset.value.status, asset.value.body)

    // The wrong method on a path that is there says what to send instead.
    val wrong = await fetch("http://127.0.0.1:8081/signup")

    print(wrong.value.status)

    val nowhere = await fetch("http://127.0.0.1:8081/nowhere")

    print(nowhere.value.status, nowhere.value.body)

    close(server)
    removeSync("./example-public/style.css")
    rmdirSync("./example-public")

main()
