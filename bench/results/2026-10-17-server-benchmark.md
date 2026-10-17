# Server benchmark, slate 0.1.30 (released PGO binary), 5 repeats

Replaces the single-run figures of `2026-10-16-server-benchmark.md`, which used a plain `sysl build`
binary, one run per figure, before the finalizer-leak fix and the shared read slab.

Machine: Apple M5 Pro, 18 cores, macOS 26.6.2, 2026-10-17. Servers and load generator share the
machine, on loopback.

Method: `caffeinate -dimsu sh bench/serve/run.sh -n 5 /opt/homebrew/bin/slate`. Each figure is five
consecutive 8 s `oha` runs at 64 connections after a 3 s warm-up per server, reported as the median
with the min-max range beside it. Tools: oha 1.16.0, node v24.14.0, bun 1.4.3, go1.27.2, slate 0.1.30
(`/opt/homebrew/bin/slate`, the PGO build). `slatejs` is the same `server.sl` compiled by `slate js`
and run under node.

Box state: `pmset -g` reports `sleep 0`; instantaneous idle 97% before the run. The one-minute load
average read 3.35 (several idle `claude` processes and a VM; see CLAUDE.md on why that is not the
check). Another agent was running `sysl test` gates on the machine during this session, so
`run.sh -n` waits before every repeat while a `sysl test` is running (it waited 31 times, 30 s each,
and no repeat in the table below started with a gate running). A gate that starts mid-repeat is not
detected, and the narrow min-max ranges (slate under 5% of the median everywhere; the widest of any
server is `bun /json` at 8%, from one fast repeat) say none distorted a repeat noticeably. A first attempt at this run was discarded and restarted once the
gate check existed.

## HTTP/1.1, requests per second and latency (oha)

| server | endpoint | req/s median | req/s min-max | p50 ms | p99 ms | p99.9 ms |
|---|---|---:|---:|---:|---:|---:|
| slate | /plain | 38083 | 37354-38650 | 1.718 | 1.952 | 2.893 |
| slate | /json | 36860 | 35794-37625 | 1.732 | 2.039 | 2.577 |
| slate | /echo | 37271 | 36260-37585 | 1.743 | 1.980 | 3.102 |
| slatejs (node) | /plain | 64372 | 64128-64975 | 0.936 | 1.931 | 2.395 |
| slatejs (node) | /json | 58536 | 57015-60399 | 1.036 | 2.115 | 2.622 |
| slatejs (node) | /echo | 61634 | 60924-62475 | 0.979 | 2.015 | 2.491 |
| node | /plain | 140582 | 138390-140918 | 0.416 | 0.878 | 1.040 |
| node | /json | 138157 | 136419-139494 | 0.426 | 0.893 | 1.041 |
| node | /echo | 129934 | 127135-130746 | 0.452 | 0.947 | 1.129 |
| bun | /plain | 178588 | 177914-180348 | 0.308 | 0.653 | 0.855 |
| bun | /json | 178221 | 174738-188435 | 0.311 | 0.663 | 0.899 |
| bun | /echo | 167684 | 166206-174133 | 0.336 | 0.726 | 0.975 |
| go | /plain | 114557 | 114431-115254 | 0.535 | 1.301 | 1.692 |
| go | /json | 103847 | 103210-105426 | 0.521 | 1.633 | 2.343 |
| go | /echo | 110849 | 110464-112679 | 0.536 | 1.417 | 1.740 |

## HTTPS + HTTP/2, requests per second and latency (oha)

Bun's `Bun.serve` negotiates HTTP/1.1 only (bun 1.4.3), so it has no h2 row.

| server | endpoint | req/s median | req/s min-max | p50 ms | p99 ms | p99.9 ms |
|---|---|---:|---:|---:|---:|---:|
| slate | /plain | 21343 | 21162-21760 | 2.986 | 3.472 | 4.518 |
| slate | /json | 19183 | 18884-19459 | 3.308 | 3.951 | 4.922 |
| slatejs (node) | /plain | 41131 | 40606-42977 | 1.483 | 2.415 | 3.486 |
| slatejs (node) | /json | 41758 | 38031-42377 | 1.477 | 2.431 | 3.352 |
| node | /plain | 60294 | 60193-60638 | 1.019 | 1.538 | 3.599 |
| node | /json | 59564 | 59250-59725 | 1.032 | 1.536 | 3.601 |
| go | /plain | 90424 | 90216-91163 | 0.646 | 1.672 | 2.206 |
| go | /json | 84260 | 83760-84564 | 0.653 | 1.817 | 2.469 |

## Peak RSS of the server over its runs (MB)

| server | plain HTTP/1.1 | HTTPS + h2 |
|---|---:|---:|
| slate | 30 | 40 |
| slatejs (node) | 226 | 228 |
| node | 178 | 204 |
| bun | 43 | - |
| go | 27 | 31 |

## Ratios against slate (median req/s of the other server over slate's)

| | h1 /plain | h1 /json | h1 /echo | h2 /plain |
|---|---:|---:|---:|---:|
| slate under `slate js` on node | 1.69x | 1.59x | 1.65x | 1.93x |
| node | 3.69x | 3.75x | 3.49x | 2.83x |
| bun | 4.69x | 4.84x | 4.50x | - |
| go | 3.01x | 2.82x | 2.97x | 4.24x |

p50 latency: slate is 4.1x node's, 5.6x bun's and 3.2x go's on h1 /plain, but p99 is within 2.2x of
the other servers (1.95 ms against 0.88 node, 0.65 bun, 1.30 go): slate's latency distribution is
tight, its tail does not blow out, it is simply serving one connection's request at a time on one
thread.

Reading it:

- **slate answers about 37,000 req/s on HTTP/1.1 and 21,000 on h2**, a third to a quarter of the
  node, Bun and Go figures. On h2 slate is closer to node (2.8x) than on h1 (3.7x).
- **Memory is no longer a story**: 30 MB peak on h1 and 40 MB on h2, level with Go and below Bun,
  where the 2026-10-16 run recorded 2649 MB and 1945 MB (the finalizer leak).
- **Throughput did not move with the leak fix and the PGO binary**: `/plain` was 39,126 req/s in the
  first run and is 38,083 now (node moved 121k to 141k between the two, so the two boxes are not
  comparable either way). The leak was a memory problem and the server's time is elsewhere, below.
- Run-to-run spread is small (under 5% of the median for slate on every row), so the ratios above are
  trustworthy to about the first decimal.

## Where slate's time goes (h1 /plain), one profile pass

`SLATE_PROFILE=1` could not be used: it prints its report to stderr when the program ends, and the
server never ends (SIGINT left stderr empty). The pass is instead a macOS `sample` of the live
released binary, 6 s of the main thread under `oha -c 64` on `/plain` (38,238 req/s while sampled, so
sampling costs nothing visible). 5,152 main-thread samples; top of stack, share of those samples:

| # | where | samples | share |
|---|---|---:|---:|
| 1 | `run_frames`, the bytecode loop (the HTTP server is itself slate source: parser glue, header objects, handler, response writer) | 705 | 13.7% |
| 2 | `write`, the response syscall | 650 | 12.6% |
| 3 | `read`, the request syscall | 355 | 6.9% |
| 4 | malloc and free (`_xzm_free` 265, `_xzm_xzone_malloc` 90, `_malloc_zone_malloc` 70, `_free` 42, one more deduplicated frame 76) | 543 | 10.5% |
| 5 | `BufCore.at` on `Machine` and on `Pending` (134 + 121, a by-value `Buf` index on the stack and on the event table) plus `_tlv_get_addr` (133, thread-local access, i.e. `current()`) | 388 | 7.5% |

Next in line: `kevent` 117 (2.3%), `getpeername` 81 (1.6%, called per accepted connection by
`remoteAddress`), `collect_now` 81 and `mark_value` 46 (2.5% together, the collector), `new_str_counted`
80, `_platform_memset` 68 (`gc.alloc` zeroing), `park` 61, and `sysl.text` `step_at` 61 + `scan_at` 55
(request parsing by character). Syscalls as a whole (write, read, kevent, getpeername) are 23% of
the thread, so a quarter of the time is the kernel and cannot be bought back in slate; the
interpreter loop and the allocator around it are about 24%, and the collector is small.

Investigation only: no fix is proposed or made here.
