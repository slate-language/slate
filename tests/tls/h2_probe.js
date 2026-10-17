// The client half of tests_js_h2.sysl: node's own HTTP/2 against a slate server running under node.
//
//     node tests/tls/h2_probe.js <server.js>
//
// It starts the server, waits for the line it prints naming its port, makes the requests below and
// prints one line for each. A line is what a test compares, so everything printed is a fact about
// what came back and never about timing.

const http2 = require("http2")
const tls = require("tls")
const { spawn } = require("child_process")

const child = spawn("node", [process.argv[2]], { stdio: ["ignore", "pipe", "inherit"] })

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

    again.close()
}
