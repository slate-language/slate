// The slate server of the server benchmark.
//
//     slate bench/serve/server.sl <port> [<cert.pem> <key.pem>]
//
// With a certificate and key it speaks HTTPS and negotiates HTTP/2 or HTTP/1.1 by ALPN; without,
// plain HTTP/1.1. The handler is `app.sl`'s. A port of 0 asks the kernel and the line printed
// says which it gave, though the runner always names one.

import { args } from slate:process
import { serve } from slate:http
import { localPort } from slate:net
import { readFileSync } from slate:fs
import { handler } from "./app.sl"

val port = number(args[0] ?? "0")

val server = if args.length >= 3
    serve({ port: port, cert: readFileSync(args[1]).value, key: readFileSync(args[2]).value, alpn: ["h2", "http/1.1"] }, handler)
else
    serve(port, handler)

print("listening " + string(localPort(server)))
