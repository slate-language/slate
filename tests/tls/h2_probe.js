// The other half of tests_js_h2.sysl and tests_js_h2_client.sysl: node's own HTTP/2, as a client
// against a slate server running under node, or as a server for a slate client running under node.
//
//     node tests/tls/h2_probe.js <server.js>
//     node tests/tls/h2_probe.js --client <client.js>
//
// As a client it starts the server, waits for the line it prints naming its port, makes the requests
// below and prints one line for each. As a server it listens on a port of its own, starts the slate
// client with that port as its argument, and prints what the client printed and then one line per
// request it was asked, sorted. A line is what a test compares, so everything
// printed is a fact about what was said and never about timing.

const http2 = require("http2")
const tls = require("tls")
const fs = require("fs")
const { spawn } = require("child_process")

// node's http2 server, answering by path: `/hello` a body, `/echo` what it was sent and a header
// saying what arrived, `/trailers` a body with trailers after it, `/big` more than any window, and
// anything else a 404.
const serveForClient = (file) => {
    const asked = []
    const server = http2.createSecureServer({ cert: fs.readFileSync("tests/tls/cert.pem"), key: fs.readFileSync("tests/tls/key.pem") })

    server.on("stream", (stream, headers) => {
        let body = ""

        stream.setEncoding("latin1")
        stream.on("data", (d) => { body += d })
        stream.on("end", () => {
            const path = headers[":path"]

            // A stream the client reset is never answered, and is not counted as asked.
            if (stream.closed || stream.destroyed) return

            asked.push(headers[":method"] + " " + path + " " + body.length + " " + (headers["x-custom"] || "-"))

            if (path === "/hello") {
                stream.respond({ ":status": 200, "content-type": "text/plain" })
                stream.end("hello from node")
            } else if (path === "/echo") {
                stream.respond({ ":status": 200, "x-seen": String(body.length) })
                stream.end(body)
            } else if (path === "/trailers") {
                stream.respond({ ":status": 200 }, { waitForTrailers: true })
                stream.on("wantTrailers", () => stream.sendTrailers({ "x-done": "yes" }))
                stream.end("with trailers")
            } else if (path === "/big") {
                stream.respond({ ":status": 200 })
                stream.end("b".repeat(200000))
            } else {
                stream.respond({ ":status": 404 })
                stream.end()
            }
        })
    })

    server.listen(0, () => {
        const child = spawn("node", [file, String(server.address().port)], { stdio: ["ignore", "pipe", "inherit"] })
        let out = ""

        child.stdout.on("data", (chunk) => { out += chunk })
        child.on("exit", () => {
            process.stdout.write(out)

            // Concurrent streams end in whatever order the network gives, so the list is sorted.
            for (const line of asked.sort()) console.log("asked " + line)

            server.close()
            process.exit(0)
        })
    })
}

if (process.argv[2] === "--client") serveForClient(process.argv[3])
else startServer(process.argv[2])

function startServer(file) {
    const child = spawn("node", [file], { stdio: ["ignore", "pipe", "inherit"] })

    let said = ""
    let started = false

    child.stdout.on("data", (chunk) => {
        said += chunk

        const found = /listening (\d+)/.exec(said)

        if (found && !started) {
            started = true

            run(Number(found[1])).then(() => child.kill(), (e) => {
                console.log("probe failed: " + (e && e.message))
                child.kill()
            })
        }
    })
}

const request = (client, method, path, body, headers) => new Promise((resolve, reject) => {
    const r = client.request(Object.assign({ ":method": method, ":path": path, "user-agent": "probe/1", "accept-encoding": "gzip, deflate" }, headers || {}))
    let text = ""
    let head

    r.setEncoding("utf8")
    r.on("response", (h) => { head = h })
    r.on("data", (d) => { text += d })
    r.on("end", () => resolve({ status: head[":status"], type: head["content-type"], seen: head["x-seen"], text: text }))
    r.on("error", reject)
    r.end(body)
})

const run = async (port) => {
    const client = http2.connect("https://localhost:" + port, { rejectUnauthorized: false })

    console.log("alpn " + (await new Promise((res) => client.on("connect", () => res(client.alpnProtocol)))))

    const hello = await request(client, "GET", "/hello")

    console.log("get " + hello.status + " " + hello.text)

    // A header value outside ASCII. node writes a header's characters as single bytes, so the UTF-8
    // bytes are spelt as such going out and read back the same way coming in.
    const utf8 = (s) => Buffer.from(s, "utf8").toString("latin1")
    const echoed = await request(client, "POST", "/echo", "x".repeat(300000), { "x-custom": utf8("héllo wörld") })

    console.log("upload " + echoed.status + " " + echoed.text.length + " " + Buffer.from(echoed.seen, "latin1").toString("utf8"))

    // A body larger than every flow-control window, so it only arrives if updates are honoured.
    const big = await request(client, "GET", "/big")

    console.log("download " + big.status + " " + big.text.length)

    const many = await Promise.all(Array.from({ length: 40 }, (_, i) => request(client, "POST", "/echo", "n" + i)))

    console.log("concurrent " + many.every((m, i) => m.text === "n" + i))

    const missing = await request(client, "GET", "/slow")

    console.log("slow " + missing.text)

    // A request abandoned while the handler is still working, and the server still answering after.
    await new Promise((resolve) => {
        const r = client.request({ ":method": "GET", ":path": "/slow" })

        r.on("error", () => {})
        r.on("close", resolve)
        setTimeout(() => r.close(http2.constants.NGHTTP2_CANCEL), 20)
    })

    await new Promise((resolve) => setTimeout(resolve, 200))

    console.log("after cancel " + (await request(client, "GET", "/hello")).text)

    client.close()

    // A client that negotiates h2 and then speaks nonsense is hung up on, and the server goes on.
    const closed = await new Promise((resolve) => {
        const raw = tls.connect({ port: port, host: "localhost", ALPNProtocols: ["h2"], rejectUnauthorized: false }, () => {
            raw.write("this is not the HTTP/2 preface at all.....")
        })

        raw.on("data", () => {})
        raw.on("close", () => resolve("closed"))
        raw.on("error", () => resolve("closed"))
    })

    console.log("garbage " + closed)

    const again = http2.connect("https://localhost:" + port, { rejectUnauthorized: false })

    console.log("after garbage " + (await request(again, "GET", "/hello")).text)

    // The limits a server holds a peer to, each from a client written in raw frames, since node's own
    // client keeps to them. After each the attacker's connection is over or its stream refused, and
    // the well-behaved client above is answered as before.
    // The server opens with an empty SETTINGS and then the one that carries its two limits.
    const opened = await raw(port, Buffer.alloc(0), (fs) => fs.some((f) => f.type === SETTINGS && f.payload.length > 0))
    const limits = opened.frames.find((f) => f.type === SETTINGS && f.payload.length > 0)

    console.log("settings " + settingsOf(limits.payload))

    // A hundred and one requests open at once, none of them ended: the last is refused.
    const many101 = []

    for (let i = 0; i < 101; i++) many101.push(frame(HEADERS, END_HEADERS, 1 + 2 * i, block("POST", "/echo")))

    const crowded = await raw(port, Buffer.concat(many101), (fs) => fs.some((f) => f.type === RST_STREAM))

    console.log("too many streams " + resets(crowded.frames))
    console.log("after streams " + (await request(again, "GET", "/hello")).text)

    // A header list that comes to more than 64 KiB once decoded, from a block of four kilobytes: one
    // field added to the table and then named twenty times, a byte each.
    const indexed = Buffer.concat([Buffer.from([0x40, 5]), Buffer.from("x-big"), Buffer.from([0x7f, 0xa1, 0x1e]), Buffer.alloc(4000, 0x61)])
    const flood = Buffer.concat([block("GET", "/"), indexed, Buffer.alloc(20, 0xbe)])
    const flooded = await raw(port, frame(HEADERS, END_HEADERS | END_STREAM, 1, flood), (fs) => fs.some((f) => f.type === HEADERS))
    const answer = flooded.frames.find((f) => f.type === HEADERS)

    console.log("header flood " + (answer !== undefined && answer.payload.includes("431") ? "431" : "no answer"))
    console.log("after header flood " + (await request(again, "GET", "/hello")).text)

    // The 2024 CONTINUATION flood: a header block that is never ended, in empty frames.
    const continued = [frame(HEADERS, 0, 1, block("GET", "/"))]

    for (let i = 0; i < 20; i++) continued.push(frame(CONTINUATION, 0, 1))

    const conted = await raw(port, Buffer.concat(continued), () => false)

    console.log("continuation flood " + goawayOf(conted.frames) + " " + conted.how)
    console.log("after continuation flood " + (await request(again, "GET", "/hello")).text)

    // The 2023 rapid reset: requests opened and cancelled at once, past nghttp2's bucket of a thousand.
    const pairs = []

    for (let i = 0; i < 1100; i++) {
        pairs.push(frame(HEADERS, END_HEADERS, 1 + 2 * i, block("POST", "/echo")))
        pairs.push(frame(RST_STREAM, 0, 1 + 2 * i, u32(8)))
    }

    const reset = await raw(port, Buffer.concat(pairs), () => false)

    console.log("rapid reset " + goawayOf(reset.frames) + " " + reset.how)
    console.log("after rapid reset " + (await request(again, "GET", "/hello")).text)

    again.close()
}

// -- raw frames ---------------------------------------------------------------------------------------

const PREFACE = Buffer.from("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n", "latin1")
const HEADERS = 1, RST_STREAM = 3, SETTINGS = 4, GOAWAY = 7, CONTINUATION = 9
const END_STREAM = 1, END_HEADERS = 4

const u32 = (n) => {
    const b = Buffer.alloc(4)

    b.writeUInt32BE(n, 0)

    return b
}

const frame = (type, flags, stream, payload) => {
    const body = payload || Buffer.alloc(0)
    const head = Buffer.alloc(9)

    head.writeUIntBE(body.length, 0, 3)
    head[3] = type
    head[4] = flags
    head.writeUInt32BE(stream, 5)

    return Buffer.concat([head, body])
}

// A request's header block: the method, `https` and the path from the static table, and the authority
// as a literal that is not indexed, so the block leaves the server's table as it found it.
const block = (method, path) => Buffer.concat([
    Buffer.from([method === "GET" ? 0x82 : 0x83, 0x87]),
    path === "/" ? Buffer.from([0x84]) : Buffer.concat([Buffer.from([0x04, path.length]), Buffer.from(path, "latin1")]),
    Buffer.from([0x01, 9]), Buffer.from("localhost", "latin1")
])

// A connection that sends the preface, an empty SETTINGS and `bytes`, and keeps every frame the server
// sends until `enough` says so, the server hangs up, or three seconds pass.
const raw = (port, bytes, enough) => new Promise((resolve) => {
    const frames = []
    let inbuf = Buffer.alloc(0)
    let done = false

    const finish = (how) => {
        if (done) return

        done = true
        clearTimeout(timer)
        sock.destroy()
        resolve({ frames: frames, how: how })
    }

    const sock = tls.connect({ port: port, host: "localhost", ALPNProtocols: ["h2"], rejectUnauthorized: false }, () => {
        sock.write(Buffer.concat([PREFACE, frame(SETTINGS, 0, 0), bytes]))
    })

    const timer = setTimeout(() => finish("still open"), 3000)

    sock.on("data", (chunk) => {
        inbuf = Buffer.concat([inbuf, chunk])

        while (inbuf.length >= 9 && inbuf.length >= 9 + inbuf.readUIntBE(0, 3)) {
            const len = inbuf.readUIntBE(0, 3)

            frames.push({ type: inbuf[3], flags: inbuf[4], stream: inbuf.readUInt32BE(5) & 0x7fffffff, payload: inbuf.subarray(9, 9 + len) })
            inbuf = inbuf.subarray(9 + len)
        }

        if (enough(frames)) finish("open")
    })

    sock.on("close", () => finish("closed"))
    sock.on("error", () => finish("closed"))
})

const settingsOf = (payload) => {
    const said = []

    for (let at = 0; at + 6 <= payload.length; at += 6) said.push(payload.readUInt16BE(at) + "=" + payload.readUInt32BE(at + 2))

    return said.join(" ")
}

const resets = (frames) => frames.filter((f) => f.type === RST_STREAM).map((f) => f.stream + ":" + f.payload.readUInt32BE(0)).join(" ")

const goawayOf = (frames) => {
    const g = frames.find((f) => f.type === GOAWAY)

    return g === undefined ? "no goaway" : "goaway " + g.payload.readUInt32BE(4)
}
