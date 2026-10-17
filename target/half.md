# Server stress: correctness under abuse

Taken with `bench/stress/run.sh ./slate` under `caffeinate -dimsu`. The slate client surface
(`slate:net`, TLS, `slate:nghttp2`, native `fetch`) is pointed at each server to try to make it
misbehave. PASS/FAIL is the client's verdict; RSS and fd columns are the server process's.

Machine: Apple M5 Pro, 18 cores, macOS 26.6.2, 2026-10-16.

## Verdict, and server RSS (MB) / open fds, before / peak / after

| server | mode | verdict | rss before | rss peak | rss after | fd before | fd peak | fd after |
|---|---|---|---:|---:|---:|---:|---:|---:|
| slate | halfclose | PASS | 11 | 46 | 46 | 13 | 293 | 13 |
| node | halfclose | PASS | 44 | 57 | 57 | 17 | 17 | 17 |
| go | halfclose | PASS | 11 | 16 | 16 | 9 | 9 | 9 |

## What each mode saw

| server | mode | detail |
|---|---|---|
| slate | halfclose | rounds=300 answeredAfterHalfClose=300/300 served=10/10 (no crash) |
| node | halfclose | rounds=300 answeredAfterHalfClose=300/300 served=10/10 (no crash) |
| go | halfclose | rounds=300 answeredAfterHalfClose=300/300 served=10/10 (no crash) |
