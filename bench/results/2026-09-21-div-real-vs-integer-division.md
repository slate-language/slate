# 2026-09-21 — `/` ANSWERS A REAL AND `\` IS THE INTEGER DIVISION: TIMED NEUTRAL

**The second entry here that is not an optimisation, and the reading is the opposite of the one
below it.** `/` between two integers answers a *real* now, always — `7 / 2` is three and a half and
`4 / 2` is a whole real — and `\` is the whole-number division, truncating toward zero. The section
below this one says what a language change can cost; this one says that a language change need not
cost anything, and why the two differ.

**Nothing on a hot path grew a test.** The overflow check below sits *inside* `+`, `-` and `*`, so
every addition a program does pays for it. This change adds an arm to the same `match` — `Backslash`
beside `Slash` in `int_arith`, `big_arith` and `real_arith` — and replaces what the `Slash` arm
does. A `match` over an enum is a jump table, so an arm nobody takes costs nothing, and the `Slash`
arm went from a zero test, an overflow test and a machine division to two `real` conversions and a
double division. Neither is a per-operation tax and neither benchmark here divides at all.

Both binaries built in this session from the two ends of one branch, so the control is dev
**`78c43d8`** and the branch is that tree with this change and nothing else. `bench/run.sh -n 5` per
binary, box **96.9% idle at the start and 97.6% at the end** of the first pass, `pgrep -x java`
empty, no other build or gate running. **Every figure is the MEAN OF BOTH ORDERINGS**
(control→branch and branch→control), whichever binary runs second reading slower on this box. The
`/lua` columns divide by one Lua figure — the mean of all four readings of it — because Lua's own
column drifted about 2% across the pass, which is more than anything in the slate column moved.
Milliseconds of process wall time.

| | dev `78c43d8` | real-division | change | dev/lua | branch/lua |
|---|---|---|---|---|---|
| arith | 1295.1 | 1293.1 | **-0.2%** | 26.7x | 26.7x |
| reals | 1289.7 | 1286.0 | **-0.3%** | 22.2x | 22.1x |
| fib | 1622.7 | 1613.5 | **-0.6%** | 20.3x | 20.2x |

**All three read slightly in the branch's favour and not one of them is a result.** This machine's
run-to-run spread is two to three percent — the `native-args` section below documents four readings
of `globals` spanning 100 ms — so a figure at half a percent is a way of saying *no change was
measured*, and the three of them agreeing in sign is what four readings apiece buys rather than
evidence of a speed-up. `arith` and `reals` are the two that would have shown a per-operation cost:
`arith` is a loop of nothing but `+`, `-` and `*` on integers, `reals` the same loop on doubles.

**The witness that the readings are not hiding a divide is that `bench/` CONTAINS NO DIVISION.**
Every one of the twenty-three programs was grepped and the only `/` in any of them is in a comment
in `branches.sl`, which says the four languages' truncating-versus-floor difference deliberately
never comes up. So the twins are untouched, `expected.txt` is unchanged, and **nothing in this
directory was edited by this item at all** — which also means these numbers say what the change
costs a program that does not divide, and say nothing about one that does.

**No instruction count moved, and that is read off the diff rather than off a profile.** `\`
compiles to the `BinaryOp` every other arithmetic operator compiles to, carrying its own `Tok`;
neither `code.sysl` nor `run_frames.sysl` is touched by this branch, so there is no new instruction
for `--features profile` to count and the instruction mix under it is the control's exactly. What
changed is what `BinaryOp` *does* for two of its tokens, which is why the wall clock is the only
instrument that can see this item.

**Nothing on the ranked shortlist is struck through.** The shortlist is optimisations and this is a
language change; the pair of entries to read together is this one and the one below, which together
say that an integer that never wraps costs about one shortlist item's worth of work and that
splitting its division in two costs nothing on top.

