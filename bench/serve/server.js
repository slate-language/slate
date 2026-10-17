// The node server of the server benchmark: plain `http` and `http2`, nothing else.
//
//     node bench/serve/server.js <port> [<cert.pem> <key.pem>]
//
// With a certificate it is an HTTPS server that also speaks h2 (`allowHTTP1`). The three endpoints
// are the ones in `app.sl`; the 404 and 405 texts match it too.
const fs = require("fs");
const port = Number(process.argv[2] || 0);
let seq = 0;

function answer(method, path, body, send) {
  if (path === "/plain") return send(200, "text/plain", "hello");
  if (path === "/json") {
    seq += 1;
    return send(200, "application/json", JSON.stringify({ server: "node", seq: seq, ok: true, items: [1, 2, 3] }));
  }
  if (path === "/echo") {
    if (method === "POST") return send(200, "text/plain", body);
    return send(405, "text/plain", "POST only");
  }
  return send(404, "text/plain", "not found");
}

function viaH1(req, res) {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    answer(req.method, req.url, Buffer.concat(chunks).toString(), (status, type, text) => {
      res.writeHead(status, { "Content-Type": type, "Content-Length": Buffer.byteLength(text) });
      res.end(text);
    });
  });
}

let server;
if (process.argv[3]) {
  const opts = { cert: fs.readFileSync(process.argv[3]), key: fs.readFileSync(process.argv[4]), allowHTTP1: true };
  server = require("http2").createSecureServer(opts, (req, res) => viaH1(req, res));
} else {
  server = require("http").createServer(viaH1);
}
server.listen(port, () => console.log("listening " + server.address().port));
