# Server benchmark: slate, node, Bun and Go

Taken with `bench/serve/run.sh ./slate` under `caffeinate -dimsu`. slate is a plain `sysl build .`
binary, not the PGO one (about 20% slower than a release build, `bench/README.md`), and each figure
is ONE run, not a best-of. slate runs on its interpreter only: `listen` refuses under `slate js`, so
node stands for that host. Bun 1.4.3 negotiates HTTP/1.1 on a TLS port (no h2), so it has no h2 row.

**Two things to read before the numbers.** slate's peak RSS was 2.6 GB on plain HTTP/1.1 against
26-124 MB for the others. It was a leak, not the schedule, and it is fixed: see *The RSS finding*
at the end, and the `slate (fixed)` row in the RSS table. And Bun's `/plain`
fixed-rate p99 of 76 ms is one stall in a single run, since `/json` beside it is 0.19 ms.

Machine: Apple M5 Pro, 18 cores, macOS 26.6.2, 2026-10-16.

Settings: 8 s per run, 64 connections, 3 s warm-up per server, fixed rate 5000 req/s. Servers and load generators share this machine, on loopback.

Tools: oha 1.16.0, wrk 4.2.0 [kqueue] Copyright (C) 2012 Will Glozer, h2load nghttp2/1.70.0, node v24.14.0, bun 1.4.3, go1.27.2, slate slate 0.1.28.

### HTTP/1.1, plain, throughput and latency

oha columns are req/s, then p50, p99 and p99.9 in ms; wrk columns are req/s, p50, p99 (wrk has no p99.9). A trailing ! on a figure means some requests failed.

| server | endpoint | oha req/s | oha p50 | oha p99 | oha p99.9 | wrk req/s | wrk p50 | wrk p99 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| slate | /plain | 39126 | 1.637 | 1.921 | 3.594 | 47027 | 1.320 | 2.340 |
| slate | /json | 36190 | 1.744 | 2.158 | 3.117 | 46478 | 1.370 | 1.700 |
| slate | /echo (POST) | 36846 | 1.695 | 2.782 | 3.631 | - | - | - |
| node | /plain | 121382 | 0.482 | 1.022 | 1.151 | 149125 | 0.410 | 0.829 |
| node | /json | 114416 | 0.511 | 1.113 | 1.252 | 143289 | 0.427 | 0.870 |
| node | /echo (POST) | 104071 | 0.564 | 1.195 | 1.532 | - | - | - |
| bun | /plain | 164882 | 0.336 | 0.738 | 0.959 | 200890 | 0.275 | 0.697 |
| bun | /json | 159010 | 0.348 | 0.773 | 1.027 | 207590 | 0.276 | 0.618 |
| bun | /echo (POST) | 147673 | 0.381 | 0.834 | 1.094 | - | - | - |
| go | /plain | 109966 | 0.532 | 1.475 | 6.461 | 136681 | 0.279 | 34.640 |
| go | /json | 102195 | 0.507 | 1.85 | 2.847 | 136144 | 0.286 | 1.230 |
| go | /echo (POST) | 111232 | 0.533 | 1.438 | 1.815 | - | - | - |

### HTTP/1.1, plain, fixed rate (oha -q, latency-corrected; stands in for wrk2)

| server | endpoint | target req/s | achieved req/s | p50 | p99 | p99.9 |
|---|---|---:|---:|---:|---:|---:|
| slate | /plain | 5000 | 4997 | 0.171 | 0.466 | 0.765 |
| slate | /json | 5000 | 4998 | 0.174 | 0.475 | 4.836 |
| node | /plain | 5000 | 4998 | 0.107 | 0.29 | 0.411 |
| node | /json | 5000 | 4999 | 0.109 | 0.235 | 0.535 |
| bun | /plain | 5000 | 4998 | 0.08 | 76.327 | 257.874 |
| bun | /json | 5000 | 4999 | 0.077 | 0.191 | 0.771 |
| go | /plain | 5000 | 4998 | 0.09 | 0.218 | 0.595 |
| go | /json | 5000 | 4998 | 0.098 | 0.244 | 0.474 |

### HTTPS + h2, throughput

| server | endpoint | oha req/s | oha p50 | oha p99 | oha p99.9 | h2load req/s |
|---|---|---:|---:|---:|---:|---:|
| slate | /plain | 24430 | 2.584 | 3.612 | 3.996 | 11502 |
| slate | /json | 24743 | 2.599 | 3.148 | 4.15 | 11308 |
| node | /plain | 53426 | 1.16 | 1.735 | 3.951 | 108395 |
| node | /json | 51382 | 1.202 | 1.78 | 4.096 | 101276 |
| bun | not measured: negotiated HTTP/1.1, no h2 | | | |
| go | /plain | 89519 | 0.645 | 1.738 | 2.567 | 254130 |
| go | /json | 86357 | 0.637 | 1.911 | 3.187 | 238995 |

### Peak RSS of the server over its runs (MB)

| server | plain HTTP/1.1 | HTTPS + h2 |
|---|---:|---:|
| slate | 2649 | 1945 |
| slate (fixed) | 40 | 73 |
| node | 124 | 267 |
| bun | 39 | - |
| go | 26 | 48 |

### The RSS finding, and the re-run

**The collected heap was never the problem.** Under one 8 s `oha` run on `/plain` (~32k req/s),
`SLATE_PROFILE` put the heap high water at 2.1 MB, while RSS climbed in a straight line at about
50 MB a second, reached 397 MB, and stayed there once the load stopped. `leaks` on the live server
found 1.66 million leaked 64-byte blocks after 4 s. Every one of them was allocated in a finalizer:
`finalize_object`, `finalize_array`, `finalize_bytes` and `finalize_promise`.

**The cause:** each finalizer let go of an object's `Buf` or `Map` by assigning `buf()` or `map()`
over it. A `Buf` is a reference, so `buf()` allocates a fresh core. The next `gc.alloc` to reuse the
cell then zeroed that core away without releasing it, which lost one core per object swept, on
every request. The fix is `release()`, which sysl provides for exactly this case (`collector.sysl`).
`tests_finalize.sysl` measures it with malloc's own block count: 359,893 blocks left behind by a
program that keeps nothing before the fix, and under 20,000 after.

**Re-run, slate only, same settings, same machine, after the fix.** Peak RSS was **40 MB** on plain
HTTP/1.1 and **73 MB** on HTTPS + h2. Under one 8 s `oha` run, RSS sat flat at 30 MB on h1 and at
64 MB on h2. Throughput did not move: oha 36,199 / 37,098 / 36,799 req/s on `/plain`, `/json` and
`/echo`, wrk 46,137 / 46,065; h2 oha 23,639 / 22,714, h2load 10,756 / 10,977.
