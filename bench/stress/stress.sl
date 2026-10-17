// A server stress tool, written in slate, beside the server benchmark (`bench/serve/`).
//
//     slate bench/stress/stress.sl <mode> <host> <port> [tls]
//     slate bench/stress/stress.sl --check                 (tiny scale, self-hosted, all TCP modes)
//
// It points slate's own client surface -- `slate:net`, TLS, `slate:nghttp2` and the native `fetch`
// -- at a running server and tries to make it misbehave. The goal is CORRECTNESS UNDER ABUSE, not
// speed: each mode reports `PASS` or `FAIL` against stated expectations. Server RSS and open-fd
// counts before, during and after are the harness's (`run.sh`), which knows the server's pid; this
// program measures what a CLIENT can see -- whether normal requests keep being answered, and whether
// an abusive connection is cut off.
//
// The servers and the three endpoints are `bench/serve/`'s: GET /plain -> "hello". A TLS server's
// certificate is self-signed, so a TLS run is told the CA to trust through `STRESS_CA`.

import { connect, send, shutdown, close, onData, onBytes, onError, startTls, alpnProtocol, localPort } from slate:net
import { serve, close as stopServer } from slate:http
import { h2Client, h2Request, h2Reset, h2Settings, h2Send, h2Receive, h2Next, h2Close } from slate:nghttp2
import { args, env, exit } from slate:process
import { readFileSync } from slate:fs
import { handler } from "../serve/app.sl"

// `--check` scales every mode down to seconds; the heavy run reads its scale from the environment.
var CHECK = false

// The CA to verify a self-signed TLS server against, read once; `null` for a plain run.
readTrust() =
    val p = env("STRESS_CA")

    if p == null
        null
    else
        val r = readFileSync(p)

        if r.ok then r.value else null

val trustPem = readTrust()

// A whole-number option from the environment, with a default.
num(name, fallback) =
    val v = env(name)

    if v == null then fallback else number(v)

// Join an array of strings, since the stress notes are built up as lists.
joined(xs, sep) =
    var out = ""
    var first = true

    for x in xs
        if first then out = x else out = out + sep + x

        first = false

    out

// `fetch` options carrying the trust anchor only where there is one.
fetchOpts() =
    if trustPem == null then { timeout: 4000 } else { timeout: 4000, trust: trustPem }

// Poll until `check()` answers true or `ms` have passed; answers whether it did.
async until(ms, check) =
    var waited = 0

    loop
        if check() then return true

        if waited >= ms then return false

        await sleep(10)

        waited += 10

// One normal request over the native client, which also exercises the connection pool and, on TLS,
// HTTP/2. True only where the server actually answered `/plain`.
async normalOk(base) =
    val r = await fetch(base + "/plain", fetchOpts())

    r.ok && r.value.status == 200 && r.value.body == "hello"

// How many of `count` normal requests succeed while abuse is in flight.
async normalScore(base, count) =
    var ok = 0
    var i = 0

    loop
        if i >= count then return ok

        if await normalOk(base) then ok += 1

        i += 1

// A raw TCP (optionally TLS) connection, as a client would abuse it. Answers the connection or null,
// having registered a reader that records when the peer closes and what it heard.
async rawOpen(host, port, tls, state) =
    val opened = await connect(host, port)

    if !opened.ok then return null

    val conn = opened.value

    if tls
        val tlsOpts = if trustPem == null then { host: host, alpn: ["http/1.1"] } else { host: host, alpn: ["http/1.1"], trust: trustPem }
        val up = await startTls(conn, tlsOpts)

        if !up.ok
            close(conn)

            return null

    onData(conn, chunk ->
        if chunk == null
            state.closed = true
        else
            state.heard = state.heard + chunk)

    onError(conn, _ ->
        state.closed = true)

    conn

// --- scenario 1: slowloris ----------------------------------------------------------------------
// Thousands of connections dribbling a request one byte at a time. A correct server keeps answering
// normal requests and cuts the slow ones off on a header-read timeout. We report whether it has one.
async slowloris(host, port, tls, base) =
    val conns = if CHECK then 40 else num("STRESS_CONNS", 1000)
    val states = []
    var opened = 0
    var i = 0

    loop
        if i >= conns then break

        val state = { closed: false, heard: "" }
        val conn = await rawOpen(host, port, tls, state)

        if conn != null
            states.push({ conn: conn, state: state })

            await send(conn, "GET /plain HTTP/1.1\r\nHost: x\r\nX-A: ")

            opened += 1

        i += 1

    val served = await normalScore(base, 10)

    // Dribble one byte a second to every connection still open, for longer than any reasonable
    // header deadline. An idle clock that each byte resets never fires; a header-read deadline does.
    val waitMs = if CHECK then 7000 else num("STRESS_SLOW_WAIT", 20000)
    var waited = 0

    loop
        if waited >= waitMs then break

        for entry in states
            if !entry.state.closed then send(entry.conn, "a")

        await sleep(1000)

        waited += 1000

    var cut = 0

    for entry in states
        if entry.state.closed then cut += 1

    for entry in states
        close(entry.conn)

    val hasTimeout = cut > 0

    { pass: served >= 9 && hasTimeout, note: "opened=" + string(opened) + " served=" + string(served) + "/10 cutOff=" + string(cut) + "/" + string(opened) + " hasHeaderTimeout=" + string(hasTimeout) }

// --- scenario 2: idle flood ---------------------------------------------------------------------
// Thousands of connections that connect and then say nothing. Normal requests are still served.
async idleFlood(host, port, tls, base) =
    val conns = if CHECK then 40 else num("STRESS_CONNS", 1000)
    val held = []
    var opened = 0
    var i = 0

    loop
        if i >= conns then break

        val state = { closed: false, heard: "" }
        val conn = await rawOpen(host, port, tls, state)

        if conn != null
            held.push(conn)

            opened += 1

        i += 1

    val served = await normalScore(base, 10)

    for conn in held
        close(conn)

    { pass: served >= 9, note: "idle=" + string(opened) + " served=" + string(served) + "/10" }

// --- scenario 3: half-close and hang-ups --------------------------------------------------------
// A client that half-closes right after the request (and must still be answered), one that drops
// mid-request, and one that drops mid-body. No crash, and nothing leaked (the harness checks fds).
async halfClose(host, port, tls, base) =
    val rounds = if CHECK then 20 else num("STRESS_HALF_ROUNDS", 300)
    var i = 0
    var answered = 0

    loop
        if i >= rounds then break

        val s1 = { closed: false, heard: "" }
        val c1 = await rawOpen(host, port, tls, s1)

        if c1 != null
            await send(c1, "GET /plain HTTP/1.1\r\nHost: x\r\n\r\n")

            // A real half-close: the FIN goes out while this end still reads. A server that treats
            // the end of the request stream as the end of the connection never answers.
            await shutdown(c1)

            var waited = 0

            while !s1.heard.startsWith("HTTP/1.1 200") && !s1.closed && waited < 1000
                await sleep(5)
                waited += 5

            if s1.heard.startsWith("HTTP/1.1 200") then answered += 1

            close(c1)

        val s2 = { closed: false, heard: "" }
        val c2 = await rawOpen(host, port, tls, s2)

        if c2 != null
            await send(c2, "GET /plain HTT")

            close(c2)

        val s3 = { closed: false, heard: "" }
        val c3 = await rawOpen(host, port, tls, s3)

        if c3 != null
            await send(c3, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\nhalf")

            close(c3)

        i += 1

    val served = await normalScore(base, 10)

    { pass: served >= 10 && answered == rounds, note: "rounds=" + string(rounds) + " answeredAfterHalfClose=" + string(answered) + "/" + string(rounds) + " served=" + string(served) + "/10 (no crash)" }

// --- scenario 4: malformed and oversized --------------------------------------------------------
// A bad request line, oversized headers, too many headers, a bad chunked body, and a huge
// Content-Length behind a short body. The server answers 4xx or closes, and keeps serving others.
async malformed(host, port, tls, base) =
    val headerKb = if CHECK then 64 else num("STRESS_HEADER_KB", 128)
    var big = "X-Big: "

    loop
        if big.length >= headerKb * 1024 then break

        big = big + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    var manyHeaders = ""
    var h = 0

    loop
        if h >= 5000 then break

        manyHeaders = manyHeaders + "X-H" + string(h) + ": v\r\n"

        h += 1

    val cases = [
        { name: "bad-request-line", bytes: "NOT-A-METHOD /\r\n\r\n" },
        { name: "oversized-header", bytes: "GET /plain HTTP/1.1\r\nHost: x\r\n" + big + "\r\n\r\n" },
        { name: "too-many-headers", bytes: "GET /plain HTTP/1.1\r\nHost: x\r\n" + manyHeaders + "\r\n" },
        { name: "bad-chunked", bytes: "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nZZZZ\r\n" },
        { name: "huge-content-length", bytes: "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 999999999\r\n\r\nshort" }
    ]

    var handled = 0
    val details = []

    for c in cases
        val state = { closed: false, heard: "" }
        val conn = await rawOpen(host, port, tls, state)

        if conn == null
            details.push(c.name + "=noconnect")
        else
            await send(conn, c.bytes)

            await until(5000, () -> state.closed || state.heard.length > 0)

            val status4xx = state.heard.length >= 12 && (state.heard[9] == "4" || state.heard[9] == "5")
            // A server still reading a body it was PROMISED is legal, provided it serves everyone
            // else meanwhile (checked below); only that case may be silent.
            val waiting = c.name == "huge-content-length" && !state.closed && state.heard.length == 0
            val ok = state.closed || status4xx || waiting

            if ok then handled += 1

            details.push(c.name + "=" + (if state.closed then "closed" elif status4xx then "4xx" elif waiting then "waiting" elif state.heard.length > 0 then "2xx?!" else "hung"))

            close(conn)

    val served = await normalScore(base, 10)

    { pass: handled == cases.length && served >= 10, note: "handled=" + string(handled) + "/" + string(cases.length) + " served=" + string(served) + "/10 [" + joined(details, " ") + "]" }

// --- scenario 5: h2 abuse (TLS + h2 only) --------------------------------------------------------
// A stream flood past MAX_CONCURRENT_STREAMS, a zero-window stall, a rapid-reset loop (RST_STREAM
// straight after HEADERS -- the 2023 pattern), and a SETTINGS flood. The server must stay responsive
// and bounded. The frames are driven by `slate:nghttp2`'s client half over a TLS socket we pump.
async h2Abuse(host, port, base) =
    val opened = await connect(host, port)

    if !opened.ok then return { pass: false, note: "connect failed: " + opened.error }

    val conn = opened.value
    val tlsOpts = if trustPem == null then { host: host, alpn: ["h2", "http/1.1"] } else { host: host, alpn: ["h2", "http/1.1"], trust: trustPem }
    val up = await startTls(conn, tlsOpts)

    if !up.ok then return { pass: false, note: "startTls failed: " + up.error }

    if alpnProtocol(conn) != "h2"
        close(conn)

        return { pass: false, note: "server did not negotiate h2 (got " + string(alpnProtocol(conn)) + ")" }

    val session = h2Client()

    // Flush whatever nghttp2 wants written; feeding what arrives happens in the reader.
    pump() =
        val out = h2Send(session)

        if out != null && out.length > 0 then send(conn, out)

    onBytes(conn, chunk ->
        if chunk != null
            h2Receive(session, chunk)

            pump())

    onError(conn, _ -> true)

    val reqHeaders = { ":method": "GET", ":scheme": "https", ":authority": host, ":path": "/plain" }

    // Rapid reset: open a stream and reset it at once, over and over.
    val resets = if CHECK then 100 else num("STRESS_H2_RESETS", 2000)
    var r = 0

    loop
        if r >= resets then break

        val stream = h2Request(session, reqHeaders)

        h2Reset(session, stream, 8)

        pump()

        r += 1

    // Stream flood: ask for many streams at once, past any MAX_CONCURRENT_STREAMS.
    val floods = if CHECK then 50 else num("STRESS_H2_STREAMS", 500)
    var f = 0

    loop
        if f >= floods then break

        h2Request(session, reqHeaders)

        f += 1

    pump()

    // SETTINGS flood: a storm of SETTINGS frames.
    val settingsN = if CHECK then 100 else num("STRESS_H2_SETTINGS", 1000)
    var sN = 0

    loop
        if sN >= settingsN then break

        h2Settings(session, { })

        pump()

        sN += 1

    // Zero-window stall: shrink the receive window to nothing and ask for a body.
    h2Settings(session, { initialWindowSize: 0 })

    h2Request(session, reqHeaders)

    pump()

    await sleep(500)

    pump()

    var protoErr = ""

    loop
        val ev = h2Next(session)

        if ev == null then break

        if ev.kind == "goaway" && ev.code != 0 then protoErr = "goaway code=" + string(ev.code)

    h2Close(session)

    close(conn)

    val served = await normalScore(base, 10)

    { pass: served >= 9, note: "resets=" + string(resets) + " streams=" + string(floods) + " settings=" + string(settingsN) + " zeroWindow=1 served=" + string(served) + "/10 " + protoErr }

// --- scenario 6: soak ---------------------------------------------------------------------------
// Steady mixed load for a configurable duration. The harness watches server RSS and fds for a
// plateau (a slope check); this side keeps the load steady and reports it stayed answered.
async soak(host, port, tls, base) =
    val secs = if CHECK then 1 else num("STRESS_SOAK_SECS", 30)
    var elapsed = 0
    var good = 0
    var total = 0

    loop
        if elapsed >= secs * 1000 then break

        var b = 0

        loop
            if b >= 5 then break

            total += 1

            if await normalOk(base) then good += 1

            b += 1

        val state = { closed: false, heard: "" }
        val conn = await rawOpen(host, port, tls, state)

        if conn != null
            await send(conn, "GET /plain HTTP/1.1\r\nHost: x\r\n\r\n")

            close(conn)

        await sleep(100)

        elapsed += 100

    { pass: total > 0 && good >= total - (total / 100) - 1, note: "secs=" + string(secs) + " ok=" + string(good) + "/" + string(total) }

// How many modes failed, so the program's exit status says so.
var failures = 0

report(mode, result) =
    val tag = if result.pass then "PASS" else "FAIL"

    if !result.pass then failures += 1

    print(mode + ": " + tag + " -- " + result.note)

async runMode(mode, host, port, tls, base) =
    mode match
        "slowloris" -> report(mode, await slowloris(host, port, tls, base))
        "idleflood" -> report(mode, await idleFlood(host, port, tls, base))
        "halfclose" -> report(mode, await halfClose(host, port, tls, base))
        "malformed" -> report(mode, await malformed(host, port, tls, base))
        "h2abuse" -> if tls then report(mode, await h2Abuse(host, port, base)) else print(mode + ": SKIP -- needs a TLS+h2 server")
        "soak" -> report(mode, await soak(host, port, tls, base))
        _ -> print(mode + ": SKIP -- unknown mode")

// `--check`: a self-hosted tiny-scale run over plain HTTP/1.1 of every TCP mode. It starts the slate
// benchmark server in this process, runs each mode once at tiny scale, and stops it. `h2abuse` needs
// TLS and is left to the full external run.
async check()
    val server = serve(0, handler)
    val port = localPort(server)
    val base = "http://127.0.0.1:" + string(port)

    for mode in ["slowloris", "idleflood", "halfclose", "malformed", "soak"]
        await runMode(mode, "127.0.0.1", port, false, base)

    stopServer(server)

async main()
    if args.length >= 1 && args[0] == "--check"
        CHECK = true

        await check()

        if failures > 0 then exit(1)

        return

    if args.length < 3
        print("usage: slate bench/stress/stress.sl <mode> <host> <port> [tls]")
        print("       slate bench/stress/stress.sl --check")

        return

    val mode = args[0]
    val host = args[1]
    val port = number(args[2])
    val tls = args.length >= 4 && args[3] == "tls"
    val scheme = if tls then "https://" else "http://"
    val base = scheme + host + ":" + string(port)

    await runMode(mode, host, port, tls, base)

    if failures > 0 then exit(1)

main()
