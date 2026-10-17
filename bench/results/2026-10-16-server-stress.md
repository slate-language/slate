# Server stress: correctness under abuse

Taken with `bench/stress/run.sh ./slate` under `caffeinate -dimsu`. The slate client surface
(`slate:net`, TLS, `slate:nghttp2`, native `fetch`) is pointed at each server to try to make it
misbehave. PASS/FAIL is the client's verdict; RSS and fd columns are the server process's.

Machine: Apple M5 Pro, 18 cores, macOS 26.6.2, 2026-10-16. slate is a plain `sysl build .` binary
at dev `9db3b9e`; soak 30 s; "after" is read 7 s after each mode, past every server's idle clock.
The modes run one after another on ONE server process per row group, so a mode's "rss before" is
the previous mode's "after".

**What the slate server got wrong (each a bug, not fixed here):**

1. **slowloris: no header-read deadline.** A connection that has sent a partial head is closed by the
   5 s `IdleMillis` clock only while it is silent: one byte a second resets the clock, and all 1000
   dribbling connections were still held after 20 s. Reduction: connect, send
   `GET / HTTP/1.1\r\nHost: x\r\nX-A: `, then one byte per second; never closed (silent: closed at
   5000 ms). node and Go also failed this mode at a 20 s wait (node's `headersTimeout` is 60 s, Go's
   `net/http` has none by default), so the reference servers are no better here.
2. **soak: RSS climbs under steady load.** A separate 90 s soak on a fresh slate server read
   `ok=4500/4500` with mean RSS 16 -> 34 MB from the first quarter to the last (fds bounded: peak 64,
   back to 13). node and Go plateaued. In the table, the 30 s soak's fds rose 45 -> 63 under load and
   fell back to 13 after settling, so that half is the idle window lagging rather than a leak.
3. **RSS is not given back after a connection storm**: 11 -> 161 MB across 1000 slowloris
   connections and 161 -> 246 MB across 1000 idle ones, with every fd returned. node grew 44 -> 81 MB
   over the same two modes, Go 11 -> 39 MB. Probably the same retention `serverss` is chasing.

Everything else held on slate: idle flood, hang-ups (no fd left behind), all five malformed requests
closed, h2 rapid reset / stream flood / SETTINGS flood / zero window answered normal requests
afterwards. Go's `oversized-header` "2xx?!" is Go accepting a 128 KB header under its 1 MB limit,
which is legal; "waiting" on a huge `Content-Length` means the server is still reading a body it was
promised, which is legal while it serves everyone else.

## Verdict, and server RSS (MB) / open fds, before / peak / after

| server | mode | verdict | rss before | rss peak | rss after | fd before | fd peak | fd after |
|---|---|---|---:|---:|---:|---:|---:|---:|
| slate | slowloris | FAIL | 11 | 161 | 161 | 13 | 1014 | 13 |
| slate | idleflood | PASS | 161 | 246 | 246 | 13 | 13 | 13 |
| slate | halfclose | PASS | 246 | 256 | 256 | 13 | 13 | 13 |
| slate | malformed | PASS | 256 | 256 | 256 | 13 | 14 | 13 |
| slate | soak | FAIL | 256 | 262 | 262 | 13 | 64 | 13 |
| slate | h2abuse | PASS | 13 | 23 | 23 | 13 | 13 | 13 |
| node | slowloris | FAIL | 44 | 78 | 78 | 17 | 1018 | 17 |
| node | idleflood | PASS | 78 | 81 | 81 | 17 | 17 | 17 |
| node | halfclose | PASS | 81 | 84 | 84 | 17 | 17 | 17 |
| node | malformed | PASS | 84 | 84 | 84 | 17 | 18 | 17 |
| node | soak | PASS | 84 | 84 | 84 | 17 | 18 | 17 |
| node | h2abuse | PASS | 51 | 70 | 70 | 17 | 17 | 17 |
| go | slowloris | FAIL | 11 | 35 | 35 | 9 | 1010 | 9 |
| go | idleflood | PASS | 35 | 39 | 39 | 9 | 9 | 9 |
| go | halfclose | PASS | 39 | 41 | 41 | 9 | 9 | 9 |
| go | malformed | FAIL | 41 | 41 | 41 | 9 | 12 | 9 |
| go | soak | PASS | 41 | 43 | 43 | 9 | 10 | 9 |
| go | h2abuse | PASS | 11 | 20 | 20 | 9 | 9 | 9 |

## What each mode saw

| server | mode | detail |
|---|---|---|
| slate | slowloris | opened=1000 served=10/10 cutOff=0/1000 hasHeaderTimeout=false |
| slate | idleflood | idle=1000 served=10/10 |
| slate | halfclose | rounds=300 served=10/10 (no crash) |
| slate | malformed | handled=5/5 served=10/10 [bad-request-line=closed oversized-header=closed too-many-headers=closed bad-chunked=closed huge-content-length=closed] |
| slate | soak | secs=30 ok=1500/1500 [server CLIMBING fds 45->63] |
| slate | h2abuse | resets=2000 streams=500 settings=1000 zeroWindow=1 served=10/10  |
| node | slowloris | opened=1000 served=10/10 cutOff=0/1000 hasHeaderTimeout=false |
| node | idleflood | idle=1000 served=10/10 |
| node | halfclose | rounds=300 served=10/10 (no crash) |
| node | malformed | handled=5/5 served=10/10 [bad-request-line=closed oversized-header=closed too-many-headers=closed bad-chunked=closed huge-content-length=waiting] |
| node | soak | secs=30 ok=1500/1500 [server plateau rss 84->84 MB, fds 17->18] |
| node | h2abuse | resets=2000 streams=500 settings=1000 zeroWindow=1 served=10/10  |
| go | slowloris | opened=1000 served=10/10 cutOff=0/1000 hasHeaderTimeout=false |
| go | idleflood | idle=1000 served=10/10 |
| go | halfclose | rounds=300 served=10/10 (no crash) |
| go | malformed | handled=4/5 served=10/10 [bad-request-line=closed oversized-header=2xx?! too-many-headers=closed bad-chunked=closed huge-content-length=waiting] |
| go | soak | secs=30 ok=1500/1500 [server plateau rss 41->42 MB, fds 9->10] |
| go | h2abuse | resets=2000 streams=500 settings=1000 zeroWindow=1 served=10/10  |
