# Server stress: correctness under abuse

Beside the throughput benchmark in [`bench/serve/`](../serve), this is a **stress tool written in
slate** that points slate's own client surface — [`slate:net`](../../docs/library/net.md), TLS,
[`slate:nghttp2`](../../docs/library/nghttp2.md) and the native
[`fetch`](../../docs/library/globals.md#fetch) (which now has a connection pool and HTTP/2, so this
exercises them too) — at a running server and tries to make it misbehave. **The goal is correctness
under abuse, not speed.** Each mode reports `PASS` or `FAIL` from the client's side; the harness
records the server's RSS and open-fd counts before, during and after.

It reuses `bench/serve/`'s three-endpoint servers (slate, node, Go) and its start/stop shape.

## Running it

```
caffeinate -dimsu bench/stress/run.sh -o bench/results/$(date +%F)-server-stress.md ./slate
```

`run.sh` starts each server, runs every mode once, and writes the results table. Options:

- `--only slate` (repeatable: `slate`, `node`, `go`) — which servers to stress.
- `--mode slowloris` (repeatable) — which modes to run.
- `-d <secs>` — soak duration (default 30).
- `-o <file>` — also write the table there.

The TCP modes hit a **plain HTTP/1.1** server; `h2abuse` hits the same server on **TLS**, where it
negotiates `h2`, connecting to `localhost` to match the self-signed test certificate
(`tests/tls/cert.pem`, trusted through `STRESS_CA`). The exit status is non-zero if the **slate**
server failed any mode.

## The modes

1. **slowloris** — thousands of connections sending a request's headers a byte at a time. The server
   must keep answering normal requests, and the slow ones must be cut off by a header-read timeout.
   The verdict reports whether the server under test has one (`hasHeaderTimeout`).
2. **idleflood** — thousands of idle connections that say nothing. Normal requests are still served.
3. **halfclose** — a client that drops right after its request, one that drops mid-request, one that
   drops mid-body. No crash, no leaked fd (the fd columns are the check).
4. **malformed** — a bad request line, oversized headers, too many headers, a bad chunked body, and a
   huge `Content-Length` behind a short body. The server answers 4xx or closes, and keeps serving.
5. **h2abuse** (TLS + h2 only) — a stream flood past `MAX_CONCURRENT_STREAMS`, a zero-window stall, a
   rapid-reset loop (`RST_STREAM` straight after `HEADERS` — the 2023 "rapid reset" pattern), and a
   `SETTINGS` flood, all driven through `slate:nghttp2`'s client half. The server must stay
   responsive and bounded.
6. **soak** — steady mixed load for `-d` seconds. The RSS/fd columns must plateau, not climb.

## The quick check

`stress.sl --check` runs every TCP mode (1–4 and 6) at tiny scale against a slate server it starts in
its own process, over plain HTTP/1.1, in a few seconds — the smoke. `h2abuse` needs a TLS server and
is left to the full run above.

```
./slate bench/stress/stress.sl --check
```

This is a **script run, not a suite test**: `bench/` is not reached by `sysl test .` or by
`./slate test tests/lang`, and the full modes are timing-heavy enough to trip the suite's watchdogs.
Run it by hand after a build, as the benchmark is run.
