# 2026-09-23 — SUPERINSTRUCTIONS, ROUND THREE: FIVE PAIRS, AND THE SAFE POINT LEFT WHERE IT IS

Round two ([superinstructions-2](2026-09-23-superinstructions-2.md)) fused a counted loop's head and
tail and left a list of pairs it judged to be one program's item each. This round measures that list,
plus the pairs a `Tick` makes with what follows it. Control `b95fbcf` (dev); branch
`superinstructions-3`.

## How the pairs were chosen

As before: `sysl build . --features profile`, each of the 23 `bench/*.sl` run once, and adjacent pairs
summed. **Instructions executed, all twenty-three: 1,277,679,305.** These are the candidates, with the
programs each one is hot in:

| pair | executions, all 23 | programs |
|---|---|---|
| `LoadSlot` `GetField` | 33.0M | 4 |
| `Mul` `Add` | 32.0M | 4 |
| `Tick` `LoadSlot` | 30.7M | 6 |
| `TestSlots` `JumpIfFalse` | 23.4M | 2 |
| `Tick` `IterNext` | 19.6M | 4 |
| `LoadCell` `PushInt` | 18.0M | 1 (globals: 17.6% of its instructions) |
| `Tick` `LoadSlot2` | 13.6M | 6 |
| `LoadSlotInt` `Rem` | 12.3M | 2 |
| `Equal` `JumpIfFalse` | 8.2M | 3 |

Every one was built, and **each fold was measured on its own** before the branch was measured as a
whole: a measure-only environment toggle turned one fold off in an otherwise identical binary, and
`bench/alternate.pl 7` compared the two. Anything at or under 0.5% on the programs it runs in was
struck.

## What was built

The same scheme as the first two rounds: **the fused op is written over the first slot and the rest
are left standing**, so a jump that lands mid-run still finds a whole instruction, and a target or a
span that does not fit is read from the slot that was stepped over. Every fast path is a call into
`run_fused.sysl`, because `run_frames` has no registers to spare and an inline body costs its
neighbours (see below).

- **`LoadSlotGetField(i: u16, c: u16, k: u32)`**: `LoadSlot(i)` then `GetField(k, c)`. Round two
  said this pair had no payload room. It does, if the slot and the field cache both fit sixteen bits,
  which every benchmark's do. Anything wider is left as the pair. A fault quotes the `GetField`'s
  span, which is the span of the whole instruction.
- **`MulAdd`**: `Mul` then `Add`. The integer fast path uses `checked_mul` plus an overflow test on
  the sum, and leaves the stack untouched when it declines. The slow path runs the two operators one
  at a time with their own spans, so an overflow or a mixed-kind fault is reported on whichever half
  caused it, even when the expression spans two lines. **Where the `Add` is followed by a
  `StoreSlot`, the pair is left for `AddStoreSlot`**, which the census showed is the better fold of
  the two.
- **`TestSlotsJumpIfFalse(k, first)`**: a `match` arm's test and its exit. `compose_test_slots` now
  returns the boolean instead of pushing it, and the plain `TestSlots` arm pushes it itself.
- **`LoadCellInt(d: u16, k: u16, v: i32)`**: a module variable read, then an integer literal. This is
  the one fold kept for a single program (see below). **`settle_module_defs` in `defs.sysl` gained an
  arm to put it back**: it writes `LoadName` over a `LoadCell` at a remembered pc when that name turns
  out to be rebound, and a fused `LoadCellInt` is the same case.
- **`SlotIntRem(i: u32, v: int)`**: `LoadSlot(i)`, `PushInt(v)`, `Rem`, three slots, folded in
  `fused_run` beside the loop tail. A fault quotes the `Rem`.

`Op`'s payload stays at eight bytes and `Ins` at 32. `profile.sysl`'s `op_width` gives each op its
width, so the pair counter steps over them.

## The counts

| instruction | executions, all 23 |
|---|---|
| `LoadSlotGetField` | 33,000,003 |
| `MulAdd` | 32,000,006 |
| `TestSlotsJumpIfFalse` | 23,434,745 |
| `LoadCellInt` | 18,010,008 |
| `SlotIntRem` | 12,304,348 |

**Instructions executed, all twenty-three: 1,277,679,305 → 1,158,930,195 (−9.3%).**

| program | before | after |
|---|---|---|
| globals | 102.0M | 78.0M |
| methods | 99.0M | 75.0M |
| branches | 111.02M | 92.95M |
| dispatch | 120.0M | 102.5M |
| arith | 80.0M | 70.0M |
| reals | 80.0M | 70.0M |
| fields | 55.0M | 45.0M |
| alloc | 45.0M | 42.0M |
| calls | 40.0M | 38.0M |
| strings | 1.50M | 1.35M |

Every other program is unchanged or within a few thousand.

## Each fold on its own

Same binary with one fold switched off against the same binary with it on, `alternate.pl 7`, idle
91.9–93.3%, `pgrep -x java` empty. The figure is the geometric mean over all twenty-three, and the
rows are the programs the fold runs in. (Startup read about −6% in every one of these runs; that
comes from the environment wrapper, not from the fold.)

| fold | geomean | the programs it runs in |
|---|---|---|
| `MulAdd` | −2.58% | arith −21.6%, globals −13.8%, methods −9.0%, reals −4.3% |
| `LoadSlotGetField` | −0.79% | fields −2.7%, methods −2.5% |
| `SlotIntRem` | −0.70% | branches −8.3% |
| `TestSlotsJumpIfFalse` | −0.56% | dispatch −8.2%, branches −2.5% |
| `LoadCellInt` | −0.46% | globals −5.7% |
| `EqualJumpIfFalse` | **+0.04%** | struck |
| the three `Tick` folds | **−0.30%** | struck; see below |

**`LoadCellInt` is under 0.5% on the mean and stays anyway**, because the brief's rule is "hot on
more than one program, *or dominant on one*". On `globals` the pair is 17.6% of all instructions
executed, and folding it takes 5.7% off that program.

## The numbers

The shipped build is PGO (`bench/pgo.sh`), so the whole branch was measured that way: `bench/pgo.sh`
in the control and branch worktrees, then `alternate.pl 9` between the two `pgo/slate` binaries.
Idle was 89.9% at the start and 91.2% at the end, and `pgrep -x java` was empty.

| program | control | branch | change |
|---|---|---|---|
| **globals** | 130.0 | 109.2 | **−16.0%** |
| **arith** | 114.1 | 100.3 | **−12.1%** |
| **branches** | 207.3 | 183.5 | **−11.5%** |
| **dispatch** | 185.2 | 164.3 | **−11.3%** |
| fields | 118.5 | 112.9 | −4.7% |
| startup | 4.39 | 4.18 | −4.7% |
| methods | 231.0 | 222.7 | −3.6% |
| arrays | 160.2 | 157.3 | −1.8% |
| nested | 188.1 | 185.8 | −1.2% |
| strwalk | 5.85 | 5.80 | −0.9% |
| alloc | 192.6 | 191.6 | −0.5% |
| reals | 168.3 | 167.7 | −0.4% |
| mapset | 115.6 | 115.5 | −0.1% |
| strindex | 4.96 | 4.96 | −0.1% |
| sorting | 430.9 | 430.9 | −0.0% |
| csv | 146.8 | 146.9 | +0.1% |
| strings | 12.18 | 12.19 | +0.1% |
| fib | 171.7 | 172.3 | +0.3% |
| options | 188.1 | 188.6 | +0.3% |
| closures | 89.0 | 89.3 | +0.4% |
| funcs | 96.8 | 97.5 | +0.7% |
| calls | 172.0 | 174.7 | +1.5% |
| loops | 117.6 | 119.3 | +1.5% |
| **geometric mean, all twenty-three** | | | **−2.91%** |

`bench/check.sh ./slate`: the answers from slate, lua, node and python3 are all unchanged.

## A FINDING ABOUT MEASURING: A PLAIN BUILD'S DISPATCH MOVES PROGRAMS THE CHANGE NEVER TOUCHES

Before PGO, the branch was measured as plain thin-LTO builds, and the answers did not hold still.
Three successive versions of this branch read −8.47%, −5.45% and −1.64% on the geometric mean. In
each one, programs that run **none** of the new instructions moved by up to 15%: `loops` +3.3%, then
+5.9%, then +15%; `options` +12.5%; `nested` +9.9%; `mapset` +9.4%. The census rules out a change in
the work those programs do, since their instruction counts are identical to the control's. What
changed is how the compiler laid out the dispatch loop around arms those programs never run.

Under PGO, that same final tree reads −2.91%, and no program is worse than +1.5%. So:

- **Judge a change to `run_frames` on PGO builds, the configuration that ships**, and not on a plain
  build. A plain build's number says more about how the loop happened to be laid out than about the
  change.
- **A per-fold toggle in one binary is the clean way to isolate a fold**, because the layout is
  identical on both sides. That is how the table above was taken.
- **This is why every fast path is a call.** Writing the `MulAdd` and `TestSlotsJumpIfFalse` bodies
  inline in `run_frames` read faster on their own programs and slower on the unrelated ones.

## STRUCK: `EqualJumpIfFalse`

`Equal` then `JumpIfFalse`, 8.2M on three programs, measured **+0.04%**. `==` is already a
general-kind comparison through `same`, so fusing it saves one dispatch next to a call that costs
much more. It was backed out. `AN_EQUALITY_BEFORE_A_JUMP_IS_LEFT_AS_A_PAIR` pins that it stays a
pair, and `AN_EQUALITY_BEFORE_A_JUMP_ANSWERS_FOR_EVERY_KIND` pins the answers on both back ends.

## STRUCK: THE SAFE POINT FOLDED INTO WHAT FOLLOWS IT

`TickLoadSlot`, `TickLoadSlot2` and `TickIterNext` were built. They carry the collector's safe point
into the instruction after it, and they keep the two invariants: one safe point at the top of a loop,
and one in a chunk whose body is an expression. Together they measured **−0.30%**, and on their own
programs the results went both ways: arrays −1.6%, dispatch −1.8%, options −1.8% and closures −1.2%,
but csv +1.3% and strwalk +1.3%.

**A `Tick` is a counter decrement and a rarely taken branch**, so all a fold removes is one dispatch.
The one place a fused `Tick` has paid off is round two's `TickSlotIntLess`, where it came with four
other instructions' stack traffic. All three were backed out.
`A_SAFE_POINT_BEFORE_A_LOAD_OR_A_WALK_IS_LEFT_ON_ITS_OWN` pins that, and
`A_SAFE_POINT_IN_A_WALK_A_LOOP_AND_A_RECURSION_STILL_COLLECTS_EVERY_TURN` is kept: it runs a `for`, a
`while` and a thousand-deep recursion against a small heap, which is what would fail if a safe point
were ever lost. `ticks` in `tests_bookkeeping.sysl` did not need to change.

**Not tried: folding the safe point into the call arm or the backward `Jump`.** Neither a `Tick`+call
nor a `Tick`+`Jump` pair appears among the census's hot pairs. The three built above are every
`Tick` pair it does list.

## The tests

- `tests_fused.sysl`:
  - a local's field is one instruction and faults at the field;
  - a product plus a sum is one instruction, and each half faults on its own line, including across a
    line break;
  - a product summed into a local is left for `AddStoreSlot`;
  - a `match` arm's test and its exit are one instruction;
  - a module variable and a literal are one instruction and go back to `LoadName` when the name is
    rebound;
  - a remainder of a local by a literal is one instruction, faults at the `%` (quoting `n % 0`),
    truncates toward zero (−7 % 3 is −1), and refuses a real;
  - the struck equality and `Tick` folds are left as pairs;
  - a load after a safe point still pairs onward;
  - every loop shape collects over a small heap;
  - a fault in a folded walk quotes the `for`.
- `tests/lang/fused.sl`: seven more tests on both back ends:
  - a field read, and one refused;
  - a product-sum, with promotion and mixed kinds;
  - a `match` arm;
  - a module variable that sees every write;
  - a remainder by a literal: truncation, promotion and refusal;
  - an equality before a jump, for every kind;
  - a walk over every kind, and a recursion.

  30 passed on the interpreter and 30 on `--js`.
