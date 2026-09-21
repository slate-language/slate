# Cells and payload are two collection schedules — shortlist item 7, 2026-09-19

**One threshold over cells PLUS payload gave payload a smallest-worth-collecting of 256 KiB**, which
one medium string is already past — so a program whose live set is a string it is growing allocates
about as much per turn as it holds, crosses its own threshold every turn, and collects almost once a
statement whatever headroom it is given. `maybe_collect` in `obj.sysl` now compares each figure
against a threshold of its own: cells against `collect_above` over `CollectFloor` (256 KiB), payload
against `payload_above` over `PayloadFloor` (1 MiB), both raised to `Headroom ×` what survived, and a
collection either question asks for re-schedules both.

Taken on this machine, best of 3, under `caffeinate`, box at 97.6% idle, **both columns measured in
the same session**: `dev` is `9669959` and `item 7` is this branch on top of it. Only `strings`
moves; every other row drifted 2–5% slower across the session and so did lua's own column beside it,
which is the control saying that drift is the machine and not the change.

| | dev `9669959` | item 7 | change | lua (dev / item 7) |
|---|---|---|---|---|
| strings | 904.4 | **788.2** | **-12.8%** | 361.2 / 362.6 |
| alloc | 1218.3 | 1224.6 | *+0.5%* | 170.4 / 169.8 |
| csv | 577.9 | 592.4 | *+2.5%* | 298.8 / 302.7 |
| arith (control, no payload) | 1198.0 | 1266.4 | *+5.7%* | 46.4 / 47.8 |
| **geomean** | **8.8x** / 7.1x / 4.8x | **8.8x** / 7.1x / 4.8x | | |

**What the collector was actually doing is the number worth keeping**, and `SLATE_PROFILE=1` is where
it is read:

| | collections | collector | heap high water | peak RSS |
|---|---|---|---|---|
| `bench/strings`, dev | 123,925 | 233,424 us | -- | 14.3 MB |
| `bench/strings`, item 7 | **45,627** | **92,254 us** | 1.58 MB | 30.9 MB |
| `bench/alloc`, dev | 18,292 | 119,281 us | -- | 7.9 MB |
| `bench/alloc`, item 7 | **3,685** | 102,404 us | 1.00 MB | 8.7 MB |
| 200 dropped 1 MB buffers, dev | 200 | -- | -- | 11.0 MB |
| 200 dropped 1 MB buffers, item 7 | 200 | -- | 3.23 MB | 10.9 MB |

**`heap high water` is new on the report** — the largest cells-plus-payload `maybe_collect` ever saw
stand — because a COUNT of collections moves whenever the schedule is tuned and only the peak says
what the schedule let stand. `Vm.high_water` is what `tests_payload.sysl` pins.

**A 4 MiB payload floor was measured and REFUSED, and the refusal is the interesting half.**
`bench/strings` churns 22 GB of string copies over a live set of 383 KB: at 4 MiB it runs 10,964
collections in 761 ms (-16%) and peaks at **83.1 MB** resident, against 45,627 in 788 ms and 30.9 MB
at 1 MiB. Resident memory grows by far more than the floor — the dropped strings are every size the
program grew through — so the larger floor buys 4% of one benchmark for six times the memory, on a
language whose near work is a server holding a heap all day.

