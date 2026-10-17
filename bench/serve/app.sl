// The handler the server benchmark measures. It is a module of its own so a test can call it with
// a request-shaped object and no socket, which is how `tests/lang/benchserve.sl` checks that all
// three endpoints answer what the other servers in this directory answer.
//
// **Three endpoints, and every server in `bench/serve/` implements exactly these:**
//   GET  /plain  ->  "hello", text/plain
//   GET  /json   ->  a small object built per request, application/json
//   POST /echo   ->  the request body, text/plain
// Anything else is a 404 and a wrong method on `/echo` is a 405, so a benchmark pointed at a
// misspelt path measures a 404 loop and cannot pass `check.sh`.

var seq = 0

export handler(req) =
    if req.path == "/plain"
        { status: 200, headers: { "Content-Type": "text/plain" }, body: "hello" }
    elif req.path == "/json"
        seq += 1

        { status: 200, headers: { "Content-Type": "application/json" }, body: toJSON({ server: "slate", seq: seq, ok: true, items: [1, 2, 3] }) }
    elif req.path == "/echo" && req.method == "POST"
        { status: 200, headers: { "Content-Type": "text/plain" }, body: req.body }
    elif req.path == "/echo"
        { status: 405, headers: { "Content-Type": "text/plain" }, body: "POST only" }
    else
        { status: 404, headers: { "Content-Type": "text/plain" }, body: "not found" }
