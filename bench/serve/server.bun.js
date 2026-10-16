// The Bun server of the server benchmark: `Bun.serve`.
//
//     bun bench/serve/server.bun.js <port> [<cert.pem> <key.pem>]
//
// With a certificate it is HTTPS, which Bun serves over h1 and h2 by ALPN. The three endpoints are
// the ones in `app.sl`.
const port = Number(process.argv[2] || 0);
let seq = 0;
const text = { "Content-Type": "text/plain" };

const options = {
  port,
  async fetch(req) {
    const path = new URL(req.url).pathname;
    if (path === "/plain") return new Response("hello", { headers: text });
    if (path === "/json") {
      seq += 1;
      return new Response(JSON.stringify({ server: "bun", seq: seq, ok: true, items: [1, 2, 3] }), {
        headers: { "Content-Type": "application/json" },
      });
    }
    if (path === "/echo") {
      if (req.method === "POST") return new Response(await req.text(), { headers: text });
      return new Response("POST only", { status: 405, headers: text });
    }
    return new Response("not found", { status: 404, headers: text });
  },
};
if (process.argv[3]) options.tls = { cert: Bun.file(process.argv[3]), key: Bun.file(process.argv[4]) };

const server = Bun.serve(options);
console.log("listening " + server.port);
