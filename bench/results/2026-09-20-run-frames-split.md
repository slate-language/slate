# 2026-09-20 — CUTTING `run_frames.sysl` IN TWO IS TIMED NEUTRAL

`run_frames.sysl` was 1,124 lines and the rule is a thousand. The file is one function whose body is
one `match` over `Op`, so there was nothing outside the match to move: **ten arms went to
`run_compose.sysl`** as ordinary functions — `MakeArray`, `MakeObject`, `MakeRange`, `Join`,
`Repeat`, `WithObject`, `WithMerge`, `JoinArrays`, `SetIndex`, `SetField` — every one of which
allocates, walks a list or runs a lookup, so the call reaching it is a fraction of what it does. 893
and 321 lines. **The cheap instructions were deliberately left written out in the loop**, a call
being the whole cost of a `PushInt` or a `LoadSlot`.

Both binaries built in one session from dev `6d0342b`, `bench/run.sh -n 5` under both locks, box 98%
idle, no other build or gate running (neighbours: a terminal and an editor at ~5% each). slate
milliseconds, control → branch:

| | arith | calls | fib | loops | dispatch | closures |
|---|---|---|---|---|---|---|
| | 1250 → 1266 | 1154 → 1153 | 1872 → 1879 | 942 → 938 | 1637 → 1607 | 860 → 872 |
| | +1.3% | 0.0% | +0.4% | -0.4% | -1.8% | +1.5% |

| | arrays | fields | alloc | mapset | strings | csv | options | nested |
|---|---|---|---|---|---|---|---|---|
| | 1224 → 1233 | 1190 → 1199 | 1230 → 1281 | 814 → 822 | 795 → 824 | 596 → 615 | 1510 → 1509 | 1445 → 1455 |
| | +0.7% | +0.7% | +4.2% | +0.9% | +3.6% | +3.2% | -0.1% | +0.7% |

**The second table is the one that matters** — those eight are the benchmarks that actually reach
the moved arms, and timing only the first six would have proved nothing about the move.

**`alloc`, `strings` and `csv` read past +2% and none of them is a regression, which the CONTROL
COLUMNS say and the slate column cannot.** Lua moved the same way in all three (+3.2%, +4.6%,
+7.4%), and so did `node --jitless` and `python3` — the whole pass drifted. Re-timed with the ORDER
REVERSED, branch first, the sign flips: `alloc` 1248 against 1254, `strings` 803 against 837, `csv`
605 against 607, the branch now faster by as much as it had been slower. Averaged over the two
orderings: `alloc` +1.8%, `strings` -0.3%, `csv` +1.5%. **Whichever binary runs second is slower,
and that is the measurement rather than the code** — so a single-ordering figure near the noise
floor should be re-run the other way round before it is believed.

Gates green on the merged commit: 2780 passed / 0 failed, and 2759 / 0 under `--features profile`.

