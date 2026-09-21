# `branches` — the missing benchmark that makes a decision, 2026-09-20

**Added because of the gap named directly above**: nineteen of the twenty-two programs here held no
`if`, `match` or `try` at all, so nothing on this page could see a branch misprediction, a `match`'s
arm search, or `Tick`'s cost against real control flow rather than a straight-line loop. `branches`
loops two million turns inside a function and every turn runs a bare `if`, an `if`/`elif`/`elif`/`else`
chain with a nested `if` inside one arm, an early `continue`, a five-armed `match` on a small integer,
an `if` used as an expression whose value is read, and — every thousandth turn — a `try`/`catch`
around a call that faults on a rare input. The input is a Park-Miller LCG written out in-program, so
all four twins walk the identical deterministic sequence and print the same checksum,
`1064937133`. Twins: `dispatch.lua`'s `if`-chain style for Lua's missing `match`, a `switch` for
JavaScript, Python's own `match`/`case`, `goto` for Lua's missing `continue`, and `pcall` / `try-except`
/ `try-catch` for the rare fault.

Taken 2026-09-20 on this machine, `slate` built from `dev` `6d0342b`, best of 5, under `caffeinate`,
both locks held, box at 85.66% idle before and 98.79% after, `pgrep -x java` empty (no neighbour).
Milliseconds of process wall time.

| | slate | lua | node --jitless | python | slate/lua | slate/node-jl | slate/py |
|---|---|---|---|---|---|---|---|
| `branches`, solo (`-n 5`) | 1345.8 | 100.7 | 312.1 | 388.7 | 13.4x | 4.3x | 3.5x |
| `branches`, in the full run | 1331.5 | 100.4 | 309.7 | 384.1 | 13.3x | 4.3x | 3.5x |

**The geometric mean, both ways, from the same run** (the previous twenty-two programs — the 21 timed
rows plus `startup` — against all twenty-three with `branches` added):

| | against lua | against node --jitless | against python3 |
|---|---|---|---|
| the previous twenty-two | 8.71x | 7.03x | 4.77x |
| all twenty-three, with `branches` | **8.88x** | **6.88x** | **4.70x** |

One benchmark added to a mean of twenty-one moves it by about the same tenth of one that the shortlist
items above already found — `branches` is 13.3x off Lua, near the middle of the existing spread, so it
nudges the mean rather than shifting it. **The value is not in this mean**: it is that a change to
`Tick`, to `match`'s arm search, or to branch prediction now has one place on this page to show up,
where before it had none.

