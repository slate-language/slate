# Server stress: correctness under abuse

Taken with `bench/stress/run.sh ./slate` under `caffeinate -dimsu`. The slate client surface
(`slate:net`, TLS, `slate:nghttp2`, native `fetch`) is pointed at each server to try to make it
misbehave. PASS/FAIL is the client's verdict; RSS and fd columns are the server process's.

Machine: Apple M5 Pro, 18 cores, macOS 26.6.2, 2026-10-16.

## Verdict, and server RSS (MB) / open fds, before / peak / after

| server | mode | verdict | rss before | rss peak | rss after | fd before | fd peak | fd after |
|---|---|---|---:|---:|---:|---:|---:|---:|
| slate | slowloris | FAIL | 11 | 50 | 50 | 13 | 1014 | 13 |

## What each mode saw

| server | mode | detail |
|---|---|---|
| slate | slowloris | opened=1000 served=10/10 cutOff=0/1000 hasHeaderTimeout=false |
