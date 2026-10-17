// The handler `bench/serve/` measures, called without a socket.
//
// **A benchmark server that silently 404s makes a very good-looking number**, so the handler every
// slate run of the server benchmark serves is pinned here: what each of the three endpoints answers,
// and that a wrong path or a wrong method is refused rather than answered. `bench/serve/run.sh
// --check` asks the same of every server in that directory over a real socket, TLS and h2 included;
// this is the half that runs in the suite and on both back ends.

import { handler } from "../../bench/serve/app.sl"

@test
THE_PLAIN_ENDPOINT_ANSWERS_HELLO_AS_TEXT() =
    val r = handler({ method: "GET", path: "/plain", body: "" })

    assertEq(r.status, 200)
    assertEq(r.body, "hello")
    assertEq(r.headers["Content-Type"], "text/plain")

@test
THE_JSON_ENDPOINT_BUILDS_A_FRESH_OBJECT_PER_REQUEST() =
    val first = handler({ method: "GET", path: "/json", body: "" })
    val second = handler({ method: "GET", path: "/json", body: "" })
    val a = parseJSON(first.body).value
    val b = parseJSON(second.body).value

    assertEq(first.status, 200)
    assertEq(first.headers["Content-Type"], "application/json")
    assertEq(a.ok, true)
    assertEq(a.items, [1, 2, 3])
    assertEq(b.seq, a.seq + 1)

@test
THE_ECHO_ENDPOINT_RETURNS_THE_POSTED_BODY() =
    val r = handler({ method: "POST", path: "/echo", body: "ping body" })

    assertEq(r.status, 200)
    assertEq(r.body, "ping body")

@test
A_WRONG_METHOD_OR_A_WRONG_PATH_IS_REFUSED_AND_NOT_ANSWERED() =
    assertEq(handler({ method: "GET", path: "/echo", body: "" }).status, 405)
    assertEq(handler({ method: "GET", path: "/nope", body: "" }).status, 404)
    assertEq(handler({ method: "POST", path: "/plain", body: "x" }).body, "hello")
