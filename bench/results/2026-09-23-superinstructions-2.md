# 2026-09-23 — SUPERINSTRUCTIONS, ROUND TWO: A COUNTED LOOP'S HEAD AND TAIL ARE ONE DISPATCH EACH

The first round ([2026-09-21](2026-09-21-superinstructions.md)) fused four PAIRS. Since then every one
of them has become the front half of a hotter pair, and the pairs chain into two five-instruction
runs that every counted loop in the language executes once a turn:

```
head:  Tick  LoadSlot(i)  PushInt(v)  Less  JumpIfFalse(out)     while i < v
tail:  LoadSlot(i)  PushInt(v)  Add  StoreSlot(i)  Jump(head)    i += v
```

This round fuses those two runs, plus the one broad pair the first round left, and nothing else.
Control `9d794de` (dev); branch `superinstructions-2`.

## How the pairs were chosen

`sysl build . --features profile`, every `bench/*.sl` run once, and the adjacent pairs and triples
summed over all twenty-three. A pair qualifies by its count **and** by how many programs run it at 1%
or more of their instructions, since a pair hot in one program is that program's item and not the
interpreter's.

| pair | executions, all 23 | programs ≥1% |
|---|---|---|
| `AddStoreSlot` `Jump` | 78.6M | 20 |
| `LoadSlotInt` `LessJumpIfFalse` | 68.6M | 14 |
| `Tick` `LoadSlotInt` | 63.6M | 14 |
| `LoadSlotInt` `AddStoreSlot` | 60.0M | 16 |
| `LessJumpIfFalse` `LoadSlot2` | 39M | — |
| `LoadSlot` `GetField` | 33M | — |
| `Mul` `Add` | 32M | — |
| `TestSlots` `JumpIfFalse` | 23M | — |
| `Sub` `StoreSlot` | 20M | 2 |
| `LoadSlotInt` `Rem` | 12M | — |
| `Equal` `JumpIfFalse` | 8.2M | — |

The first four are two triples wearing four names: `Tick LoadSlotInt LessJumpIfFalse` 63.57M and
`LoadSlotInt AddStoreSlot Jump` 56.96M. So the unit to fuse was the RUN, not the pair.

**The profiler had a hole that hid pairs like these, and it is fixed here.** A pair is counted when
the instruction after the one just counted runs, which it tested as `here_pc == counted_pc + 1` — so
nothing following a FUSED instruction was ever counted, the next one being two slots on.
`op_width` in `profile.sysl` gives each fused op its width and the counter steps over it.
`A_PAIR_THAT_BEGINS_WITH_A_FUSED_INSTRUCTION_IS_COUNTED` pins it (`LoadSlotInt Add`, 30 in a
thirty-turn loop, where it read zero before).

## What was built

Three instructions, the first round's scheme unchanged: **the fused op is written over the first slot
and the others are left standing**, so no jump target needs analysis — and the inner pairs are
folded where they stand, so a jump landing mid-run still finds a whole instruction.

- **`TickSlotIntLess(i: u32, v: int)`** — `Tick`, `LoadSlot(i)`, `PushInt(v)`, `Less`,
  `JumpIfFalse(to)`, five slots. The exit target does not fit beside two operands in eight bytes, so
  the arm reads it lazily from the `JumpIfFalse` slot it steps over, only on the way out. Where the
  slot is not an integer it falls back to the general comparison, quoting the `Less`'s own span.
- **`SlotIntAddStoreJump(i: u16, v: i16, to: u32)`** — `LoadSlot(i)`, `PushInt(v)`, `Add`,
  `StoreSlot(i)`, `Jump(to)`, one slot read and written. Folded only where the slot and the step fit
  sixteen bits; anything wider is left to the pairs (`A_STEP_OR_A_SLOT_TOO_WIDE_FOR_SIXTEEN_BITS_IS_LEFT_TO_THE_PAIRS`
  folds `32767` and not `32768`). An overflow or a non-integer takes the slow path with the `Add`'s
  and the `StoreSlot`'s spans read from the slots stepped over.
- **`SubStoreSlot(i)`** — `AddStoreSlot`'s twin for `-`. The no-overflow test is
  `(x ^ y) & (x ^ diff) >= 0`.

`Op`'s payload stays at eight bytes, `Ins` at 32 and `Step` at 64. `run_frames.sysl` is 991 lines;
the unary and bitwise arms were compressed to one line each (`compose_bit_and` and its four
neighbours in `run_compose.sysl`) to make room.

## The counts

| instruction | executions, all 23 |
|---|---|
| `TickSlotIntLess` | 63,571,032 |
| `SlotIntAddStoreJump` | 58,962,746 |
| `SubStoreSlot` | 20,000,000 |

**Instructions executed, all twenty-three: 1,542,746,861 → 1,277,679,305 (−17.2%).**

| program | before | after |
|---|---|---|
| arith | 130.0M | 80.0M |
| reals | 130.0M | 80.0M |
| fib | 119.76M | 96.95M |
| fields | 75.0M | 55.0M |
| funcs | 72.0M | 56.0M |
| closures | 60.0M | 44.0M |
| dispatch | 140.0M | 120.0M |
| alloc | 57.0M | 45.0M |
| methods | 111.0M | 99.0M |
| mapset | 34.0M | 26.0M |
| calls | 48.0M | 40.0M |
| options | 86.0M | 78.0M |
| branches | 121.45M | 111.02M |
| arrays | 91.0M | 80.0M |
| loops | 64.14M | 64.11M |
| globals | 102.0M | 102.0M |

`loops` and `globals` do not move: `loops`' turns are `for` heads, and `globals`' counters are
module-level `var`s, which are not slots.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `9d794de` against the branch, idle 85.6–88.3%,
`pgrep -x java` empty.

| program | control | branch | change |
|---|---|---|---|
| **arith** | 263.3 | 167.9 | **−36.2%** |
| **closures** | 202.7 | 160.9 | **−20.7%** |
| **fib** | 474.3 | 377.5 | **−20.4%** |
| **funcs** | 212.4 | 169.9 | **−20.0%** |
| **reals** | 345.9 | 277.7 | **−19.7%** |
| **fields** | 211.1 | 174.5 | **−17.3%** |
| **dispatch** | 404.3 | 335.0 | **−17.1%** |
| methods | 423.6 | 368.3 | −13.1% |
| branches | 304.6 | 278.0 | −8.7% |
| arrays | 259.0 | 236.6 | −8.6% |
| alloc | 453.2 | 420.8 | −7.2% |
| options | 507.7 | 471.5 | −7.1% |
| nested | 337.9 | 314.2 | −7.0% |
| mapset | 242.2 | 225.9 | −6.7% |
| calls | 408.1 | 387.4 | −5.1% |
| startup | 4.81 | 4.57 | −5.0% |
| strwalk | 9.04 | 8.82 | −2.5% |
| csv | 261.0 | 258.0 | −1.1% |
| loops | 157.5 | 155.7 | −1.1% |
| sorting | 531.4 | 531.2 | −0.0% |
| strindex | 7.46 | 7.48 | +0.2% |
| strings | 742.9 | 748.5 | +0.8% |
| globals | 677.6 | 688.6 | +1.6% |
| **geometric mean, all twenty-three** | | | **−10.18%** |

An earlier run, with the struck instruction below still in, read −10.98%; the difference is inside
what two runs of one pair of binaries disagree by. `bench/check.sh ./slate` reports all four
implementations' answers unchanged.

## STRUCK: `AddStoreSlotJump`, the tail without its load

The tail run needs its slot to be read and written by the same instruction. Where a loop's last
statement is `sum += x` into ANOTHER local, what stands is `AddStoreSlot(i)` then `Jump`, 78.6M on
twenty programs — the heaviest pair on the table. It was built as a fourth instruction and measured
against the branch without it:

| program | without | with | change |
|---|---|---|---|
| loops | 172.7 | 161.3 | −6.6% |
| arrays | 243.5 | 250.7 | +3.0% |
| csv | 262.5 | 266.4 | +1.5% |
| nested | 321.7 | 325.4 | +1.2% |
| **geometric mean** | | | **−0.35%** |

Zero, so it was backed out. `A_SUM_INTO_ANOTHER_LOCAL_THAT_ENDS_A_LOOP_BODY_IS_LEFT_AS_A_PAIR` pins
that it stays a pair. **The heaviest pair was not worth fusing on its own, and the reading is the
first round's: a `Jump` is the cheapest instruction there is**, so taking one dispatch off it buys
the dispatch alone, where the runs above take five instructions' worth of stack traffic with them.

## A FINDING ABOUT THE DISPATCH: IT IS ONE JUMP TABLE NOW

The first round's write-up and `run_frames.sysl`'s cold-block line say a new instruction should sit
among the arms sysl's `match` lowered to the FIRST jump table, the rest paying a second. **Under sysl
0.0.127 that no longer binds.** The branch binary's dispatch is `cmp w8, #0x72`, `b.hi`, then `ldrh`
and `br` — one bounds check and one table covering every tag — and the instruction fetch is inlined
into it. So the three arms here are written beside the pairs they extend, and the cold-block comment
now says what the line still is (where the instructions a loop never runs are written) rather than a
table boundary that is gone.

## What was not done

- **`Equal` `JumpIfFalse`** (8.2M), **`LoadSlotInt` `Rem`** (12M), **`TestSlots` `JumpIfFalse`**
  (23M) and **`Mul` `Add`** (32M): each is hot on one or two programs, which makes it that program's
  item.
- **`LoadSlot` `GetField`** (33M) has no payload room — a slot and a field-site index do not fit
  beside each other in eight bytes with a span to read back.
- **`SubStoreSlot` was not measured on its own.** It runs in `arith` and `reals` only, both of which
  also take the loop runs, so no pair of binaries separates its share.

## The tests

- `tests_fused.sysl`: the head and tail each fold to one instruction, with every inner pair still in
  place (`always_followed_by`); the sum-into-another-local and sixteen-bit limits above; a fault in a
  folded head quotes the comparison, one in a folded tail the addition, one in a folded difference
  the subtraction; and a head that collects over a small heap answers exactly (`4498500`).
- `tests_profile.sysl`: the pair after a fused instruction is counted.
- `tests/lang/fused.sl`: nine more, on both back ends — a difference into a slot, its overflow and
  reals, a string refused, a counted loop's turns, a real counter, an overflowing counter, a head with
  no order, a tail over a string, and `break`/`continue` out of a folded loop. 23 passed on the
  interpreter and on `--js`.
