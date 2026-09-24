# 2026-09-24 — A REAL IS ANSWERED IN THE OPERATOR'S OWN ARM, BESIDE THE WHOLE NUMBER

`reals.sl` is `arith.sl`'s loop with a real in it (`total = total + i * 1.5 - 0.5`, ten million turns).
On the 0.1.7 PGO build it took **120 ms against `arith`'s 77**: 2.2x Lua and 1.5x PHP, the largest
single gap left on the page. It now takes **81 ms, −33.1%: 1.4x Lua and 1.0x PHP**.

Control `3195752` (dev, slate 0.1.7); branch `reals-inline`. Both sides built with `bench/pgo.sh`.

## What the profile said

`sysl build . --features profile`, `SLATE_PROFILE=1 ./slate bench/reals.sl`: **70,000,024 instructions,
seven a turn**, the same on both sides — this change adds no instruction and removes none:

| per turn | instructions |
|---|---|
| loop head | `TickSlotIntLess` |
| `total = total + i * 1.5 - 0.5` | `LoadSlot2`, `PushReal`, `MulAdd`, `PushReal`, `SubStoreSlot` |
| `i = i + 1` + back edge | `SlotIntAddStoreJump` |

The count was never the problem; what each of `MulAdd` and `SubStoreSlot` cost was. Both had a fast
path for machine integers ONLY. `MulAdd` tested three `Int`s and, finding a real, ran
`fused_mul_add_slow`: pop three, `multiplied` → `arith(Star, …)`, `added` → `arith(Plus, …)`, push.
`SubStoreSlot` ran `subtracted` → `arith(Minus, …)`, then `stored_in_slot`'s `keepable`. Each `arith`
is an out-of-line call that tests the operator for the string join, matches the operand kinds, and
then matches the token again over seventeen arms in `real_arith` — three out-of-line calls and six
matches a turn to do two multiplies' worth of floating point. PHP and Lua open-code the double beside
the integer in the handler.

## The change

**Every leaf in `run_arith.sysl` answers a pair with a real in it in place**, wherever the answer is
one IEEE operation: `+ - * /`, the four orderings, `==`/`!=`, and `-v`. `Real`/`Real`, `Int`/`Real`
and `Real`/`Int`, the integer side promoted with `real(x)` exactly as `arith` promotes it. **The
integer pair stays the first arm in every leaf.** Everything else still hands off unchanged: a big
integer (a comparison against a real is exact there, never promoted), `%` and `\` on a real (both
refuse, with `real_arith`'s sentences), a bitwise operator, strings, sets, dates, operator methods.

**The fused forms answer it too** (`run_fused.sysl`): `MulAdd` computes a real product and sums it into
a real or integer `c` on the stack — and a whole-number product that fits meets a real `c` as
`real(product)`. Two rounded steps, never one fused multiply-add, which would round once and answer a
different last bit from the unfused pair. `AddStoreSlot` and `SubStoreSlot` write a real sum or
difference straight into the cell with no `keepable` question, a real never being an absence.

**The compare-and-jump fusions needed nothing.** `TickSlotIntLess` tests the loop COUNTER, which in
`reals.sl` is an integer; `LessJumpIfFalse`'s int-only test falls through to `is_less`, which now
answers a real in place. `run_frames.sysl` is untouched (999 lines).

## Wall time

An alternating best-of-9 on `bench/timeit.pl` (`bench/alternate.pl 9`), PGO against PGO, under
`caffeinate -dimsu`, `pgrep -x java` empty, 86.8% idle at the start. This is the landed binary:

| | dev `3195752` | reals-inline | change |
|---|---|---|---|
| **reals** | 120.5 | **80.7** | **−33.1%** |
| startup | 2.56 | 2.36 | −7.9% |
| alloc | 121.7 | 118.2 | −2.9% |
| strwalk | 3.92 | 3.83 | −2.2% |
| calls | 116.0 | 113.9 | −1.8% |
| fields | 87.5 | 86.0 | −1.7% |
| dispatch | 130.2 | 128.1 | −1.6% |
| closures | 73.0 | 72.4 | −0.8% |
| options | 150.5 | 149.3 | −0.8% |
| methods | 160.0 | 159.6 | −0.3% |
| arith | 77.5 | 77.6 | +0.1% |
| funcs | 69.8 | 69.8 | +0.1% |
| arrays | 115.3 | 115.6 | +0.2% |
| branches | 153.8 | 154.1 | +0.2% |
| fib | 138.0 | 138.4 | +0.3% |
| strings | 8.24 | 8.27 | +0.4% |
| sorting | 122.8 | 123.7 | +0.7% |
| globals | 48.0 | 48.4 | +0.8% |
| nested | 149.4 | 150.6 | +0.8% |
| loops | 90.5 | 91.5 | +1.1% |
| csv | 101.6 | 103.1 | +1.5% |
| mapset | 39.2 | 40.1 | +2.3% |
| strindex | 2.88 | 3.02 | +4.9% |
| **GEOMEAN** | | | **−2.03%** |

**The integer controls do not move**: `arith` +0.1%, `fib` +0.3%, `branches` +0.2%, `loops` +1.1%.

**`loops` is the one worth the paragraph.** An earlier PGO build of the same source read it +3.6%
control-first and +3.5% branch-first (mean −1.72% / −1.27%, `reals` −32.6% both ways), and its hot
pair, `Mul` then `AddStoreSlot` over two whole numbers, is exactly what the real arms sit beside. So the
two store functions were rebuilt with their integer bodies **byte for byte as on dev** and the real arms
moved behind `@noinline` — and `loops` read **+9.1%**, worse, with `reals` still −32.2%. A variant whose
integer path is source-identical to the control cannot owe 9% to that path: the swing is the PGO
layout of the whole binary, which earlier write-ups (`narrow-signal`) measured at ±5–7% a row. The
inline form was kept, and its own landed build reads `loops` +1.1%.

## Position

`bench/run.sh -n 5 pgo/slate reals arith`, taken once on the branch's PGO binary: **reals 81.2 ms —
Lua 56.9, PHP 81.8, node --jitless 134.8, CPython 249.2, qjs 130.3, luajit -joff 66.8** — **1.4x Lua,
1.0x PHP**, 0.6x node --jitless, 0.3x CPython, 0.6x qjs, 1.2x LuaJIT's interpreter. `reals` (81 ms)
now costs what `arith` (78) costs, which is what the two loops' instruction counts said it should.

## Tests

- `tests_operators.sysl` (3): **every leaf against `arith` over every pair of a 13-value grid** — 0, 1,
  −3, the largest and the most negative `long`, `0.0`, `-0.0`, 1.5, −2.25, 1e300, NaN and both
  infinities — for `+ - * / \ %` and the four orderings (1,690 pairs), comparing kind, IEEE value, NaN
  as NaN and a zero's sign; `==`, `!=` and `-v` against `same`/`unary` over the same grid; and a
  control that the comparison can fail (a whole real is not the integer it equals, `-0.0` is not
  `0.0`).
- `tests/lang/realarith.sl` (15, both back ends): real/real, int/real and real/int through every
  operator with the result's kind; `1 / 2` still `0.5`; integer overflow still growing; a big integer
  beside a real; `-0.0` from negation, products and sums; NaN equal to and ordered against nothing;
  the infinities; mixed comparisons; `%` and `\` on a real still refused with their sentences; a real
  beside an object still refused; and the fused forms — the `reals.sl` loop, a product summed with the
  real on each side, a product that grows beside a real, and real sums and differences stored into a
  local (`+=`/`-=` included).
- `check.sh` unchanged.
