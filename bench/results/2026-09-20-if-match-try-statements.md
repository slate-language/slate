# `if`, `match` and `try` as statements — item 1's remainder, and `bench/` CANNOT SEE IT — 2026-09-20

Item 1 deliberately left these three alone: written as a statement, each still compiled as the
expression it is, so every branch produced a value — a `PushNull` where the branch had none — and
the far side of the join met a `Discard`. They are compiled to produce no value now, and the
language rule is unchanged: where somebody reads the answer they are the expressions they were.

**THE HEADLINE IS NOT A NUMBER, IT IS THAT NINETEEN OF THE TWENTY-TWO PROGRAMS HERE CONTAIN NO `if`,
`match` OR `try` AT ALL.** The three that do are `fib`, whose `if` is an expression on one line, and
`mapset`, `strindex` and `strwalk`, each of which writes one `if x then y` in a loop. So the exact
instruction counts, taken with `--features profile` on the two ends of one commit, are these — and
**seventeen of the twenty-two did not move by a single execution**:

| benchmark | before | after | change |
|---|---|---|---|
| `strindex` | 429,042 | 387,042 | **-9.8%** |
| `strwalk` | 443,042 | 400,042 | **-9.7%** |
| `mapset` | 50,030,044 | 50,027,044 | -0.006% |
| the other nineteen | — | — | **not one execution** |
| all twenty-two | 1,914,283,331 | 1,914,195,331 | -0.005% |

**So the timing run measures the machine and nothing else, and it is reported as such.** Best of 5
under `caffeinate`, box at 98.2% idle, no neighbour but `syslogd`, both locks held — the two that
could move and two controls, in milliseconds of process wall time:

| | before | after | lua |
|---|---|---|---|
| `arith` | 1253.8 | 1248.6 | 46.7 |
| `loops` | 934.2 | 941.3 | 117.1 |
| `mapset` | 806.3 | 808.0 | 16.6 |
| `strindex` | 11.4 | 11.1 | 2.4 |
| `strwalk` | 12.8 | 12.9 | 147.9 |

**The geometric means on this page are untouched**, no full run having been taken: an item whose
instruction counts are flat on nineteen programs cannot move a mean, and a mean re-measured from a
partial run would be a statement about the afternoon.

**WHAT IT IS WORTH IS MEASURED ON TWO PROGRAMS WRITTEN FOR IT**, each two million turns of a loop
with one construct in statement position. They are not benchmarks — they have no `.lua`, `.js` or
`.py` twin and no line in `expected.txt` — and they are reported here because they are the only
measurement of this item there is:

| probe | instructions before | after | change | wall before | wall after |
|---|---|---|---|---|---|
| an `if` with no `else` and an `if`/`else` | 72,666,695 | 63,666,695 | **-12.4%** | 1021.1 ms | **975.2 ms** (-4.5%) |
| a three-armed `match` | 64,000,020 | 60,000,020 | **-6.3%** | 897.5 ms | 899.2 ms (—) |

**The `match` probe is the honest half and says what these instructions are worth.** Four million
executions went and the clock did not move: a `PushNull` pushes a constant and a `Discard` pops one,
which are the two cheapest things the machine does, so a share of the instruction count is an upper
bound on the share of the time. The `if` probe moves because it loses a `Jump` per turn as well —
a branch with no `else` no longer has a null to jump over.

**THE GAP IS WORTH MORE THAN THE MEASUREMENT: THERE IS NO BENCHMARK HERE IN WHICH A PROGRAM MAKES A
DECISION.** Every one of the twenty-two is a straight-line loop, so this page cannot see this item,
cannot see item 3 (`Tick`), and would not see a branch-prediction or a dispatch change either. A
`branches` benchmark with its three twins would close it, and is not written here because the set
these means are taken over is shared and several items are measuring against it this week.

