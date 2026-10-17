# Server stress: correctness under abuse

Taken with `bench/stress/run.sh ./slate` under `caffeinate -dimsu`. The slate client surface
(`slate:net`, TLS, `slate:nghttp2`, native `fetch`) is pointed at each server to try to make it
misbehave. PASS/FAIL is the client's verdict; RSS and fd columns are the server process's.

Machine: Apple M5 Pro, 18 cores, macOS 26.6.2, 2026-10-16. slate is a plain `sysl build .` binary
at dev `d9a966d`, which carries the finalizer-leak fix (`4b83324`); soak 30 s; "after" is read 7 s
after each mode, past every server's idle clock. The modes run one after another on ONE server
process per group, so a mode's "rss before" is the previous mode's "after".

**What the slate server got wrong (each a bug, not fixed here):**

1. **slowloris: no header-read deadline.** A connection that has sent a partial head is closed by the
   5 s `IdleMillis` clock only while it is silent: one byte a second resets the clock, and all 1000
   dribbling connections were still held after 20 s. Reduction: connect, send
   `GET / HTTP/1.1\r\nHost: x\r\nX-A: `, then one byte per second; never closed (sent nothing more:
   closed at 5000 ms). node and Go also failed at a 20 s wait (node's `headersTimeout` is 60 s; Go's
   `net/http` has none by default), so the reference servers are no better here.
2. **soak: RSS creeps, the memory the process OWNS does not (diagnosed, not a leak).** A 300 s soak
   on a fresh server (`ok=15000/15000`) read RSS 21.7 -> 25.0 MB in the first minute and then
   ~0.6 MB a minute to 27.6 MB. Over the same run `vmmap`'s **physical footprint** was 12.8 MB at
   150 s and 12.5 MB at 300 s, `leaks <pid>` found **0 leaks** at start, middle, end and 10 s after,
   and the `heap` census of live malloc blocks (the 256 MiB collector block aside) was 10.2 MB mid-run
   and 11.4 MB at the end under load. The gap is `MALLOC_SMALL` pages that are resident but not dirty
   (21.5 MB resident, 10.8 MB dirty at the end): freed blocks that macOS malloc marked reusable,
   which RSS still counts and the footprint does not. `run.sh -d 300` over the same binary read
   "plateau rss 125->130 MB, fds 61->62" after the storm. fds peak at ~63 under load and return to 13.
3. **A connection storm's memory is not given back (diagnosed: allocator retention, no bug in
   slate).** 11 -> 124 MB across 1000 slowloris connections, all fds returned. After the storm and
   after settling, the live malloc blocks total **6.1 MB** (baseline 4.9 MB, 23,302 blocks), with
   **0 leaks**. The footprint stays at 99.6 MB because 74.5 MB of `MALLOC_SMALL (empty)` regions
   are still resident (65.2 MB of it dirty). That memory is freed and nothing references it; macOS
   malloc keeps the empty regions. `malloc_zone_pressure_relief(NULL, 0)` does not help: a C probe
   that frees 1000 80 KB blocks gets **0 bytes** back from it, with the footprint unchanged at 79.5 MB.
   So no workaround was added. Most of the peak comes from **sh.sysl.libuv's per-stream read buffer**:
   `read_start(cb, buffer_size = 65536)` in `stream.sysl` gives every connection its own 64 KiB,
   held for as long as the connection is reading, so 1000 idle connections hold ~64 MB of buffers.
   node shares one slab per read and Go's `bufio` starts at 4 KiB. Changing that belongs in the
   binding (or in kairos's reads over it), not here. node grew 44 -> 78 MB over the same mode and
   also kept it, Go 11 -> 35 MB.

Everything else held on slate: idle flood, hang-ups (no fd left behind), all five malformed requests
closed, h2 rapid reset / stream flood / SETTINGS flood / zero window answered normal requests
afterwards. Go's `oversized-header` "2xx?!" is Go accepting a 128 KB header under its 1 MB limit,
which is legal; "waiting" on a huge `Content-Length` means the server is still reading a body it was
promised, which is legal while it serves everyone else.

**Re-taken on dev `6019cb1`** with `run.sh --only slate --mode slowloris --mode soak -d 300`, one
server process:

| server | mode | verdict | rss before | rss peak | rss after | fd before | fd peak | fd after |
|---|---|---|---:|---:|---:|---:|---:|---:|
| slate | slowloris | FAIL | 10 | 124 | 124 | 13 | 1014 | 13 |
| slate | soak (300 s) | PASS | 124 | 131 | 131 | 13 | 64 | 13 |

The instruments are `leaks <pid>`, `heap -s <pid>` and `vmmap --summary <pid>` on the live server
(physical footprint, and resident vs dirty per malloc region). Read the footprint, not RSS, on
macOS: RSS counts pages malloc has marked reusable.

## Verdict, and server RSS (MB) / open fds, before / peak / after

| server | mode | verdict | rss before | rss peak | rss after | fd before | fd peak | fd after |
|---|---|---|---:|---:|---:|---:|---:|---:|
| slate | slowloris | FAIL | 11 | 124 | 124 | 13 | 1014 | 13 |
| slate | idleflood | PASS | 124 | 125 | 125 | 13 | 13 | 13 |
| slate | halfclose | PASS | 125 | 125 | 125 | 13 | 13 | 13 |
| slate | malformed | PASS | 125 | 125 | 125 | 13 | 14 | 13 |
| slate | soak | FAIL | 125 | 127 | 127 | 13 | 63 | 13 |
| slate | h2abuse | PASS | 13 | 23 | 23 | 13 | 13 | 13 |
| node | slowloris | FAIL | 44 | 78 | 78 | 17 | 1018 | 17 |
| node | idleflood | PASS | 78 | 81 | 81 | 17 | 17 | 17 |
| node | halfclose | PASS | 81 | 84 | 84 | 17 | 17 | 17 |
| node | malformed | PASS | 84 | 84 | 84 | 17 | 18 | 17 |
| node | soak | PASS | 84 | 84 | 84 | 17 | 18 | 17 |
| node | h2abuse | PASS | 51 | 70 | 70 | 17 | 17 | 17 |
| go | slowloris | FAIL | 11 | 35 | 35 | 9 | 1010 | 9 |
| go | idleflood | PASS | 35 | 40 | 40 | 9 | 9 | 9 |
| go | halfclose | PASS | 40 | 40 | 40 | 9 | 9 | 9 |
| go | malformed | FAIL | 40 | 41 | 41 | 9 | 12 | 9 |
| go | soak | PASS | 41 | 45 | 45 | 9 | 10 | 9 |
| go | h2abuse | PASS | 11 | 19 | 19 | 9 | 9 | 9 |

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
| node | soak | secs=30 ok=1500/1500 [server plateau rss 83->84 MB, fds 17->18] |
| node | h2abuse | resets=2000 streams=500 settings=1000 zeroWindow=1 served=10/10  |
| go | slowloris | opened=1000 served=10/10 cutOff=0/1000 hasHeaderTimeout=false |
| go | idleflood | idle=1000 served=10/10 |
| go | halfclose | rounds=300 served=10/10 (no crash) |
| go | malformed | handled=4/5 served=10/10 [bad-request-line=closed oversized-header=2xx?! too-many-headers=closed bad-chunked=closed huge-content-length=waiting] |
| go | soak | secs=30 ok=1500/1500 [server plateau rss 41->44 MB, fds 9->10] |
| go | h2abuse | resets=2000 streams=500 settings=1000 zeroWindow=1 served=10/10  |

## Re-taken with kairos 0.1.9 and libuv 0.1.15 (shared read slab)

`run.sh --only slate --mode slowloris` on the slab build: an armed idle reader no longer holds a
buffer, so the storm's footprint drops.

| server | mode | verdict | rss before | rss peak | rss after | fd before | fd peak | fd after |
|---|---|---|---:|---:|---:|---:|---:|---:|
| slate | slowloris | FAIL | 11 | 50 | 50 | 13 | 1014 | 13 |

Peak RSS 11 -> 50 MB, against 11 -> 124 MB before. The verdict is still FAIL for the unchanged
reason (`cutOff=0/1000 hasHeaderTimeout=false`): the header-read deadline is a separate item.
