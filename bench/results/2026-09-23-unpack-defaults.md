# 2026-09-23 — A ROW OF NAMES WITH DEFAULTS TAKES THE INSTRUCTION — profile 6's item 2

Profile 6's item 2. `options` spent about 40% of its time in the matcher because its binding,
`val { width = 10, height, scale = 2 } = opts`, carries a DEFAULT, and `for-head`'s `UnpackFixed`
refused one. So every call went `UnpackSlots` → `match_walk` → `match_object` → `match_leaf` per
name, pushed what it bound (and an `undefined` placeholder for each name left out) onto the operand
stack, and `lay_bindings` copied that run down into the cells and built the mask. **A default is not a
half-match**: it is a name the subject may leave out, and what a binding site does about one was
already decided downstream of the unpack.

Control `a952ff2` (dev, slate 0.1.3); branch `unpack-defaults`.

## What changed

**`UnpackFixed(w: u32, object: bool, masked: bool)`** — the third operand is `UnpackSlots`' own flag,
and the payload is still six bytes. `unpack_op` in `match.sysl` now hands a row of bare names the
fixed instruction whether or not it carries defaults:

- an **object** of bare names, no `?`: a key the subject supplies is written into its cell and sets
  its bit; a key it does not is a fault unless that key has a default, in which case the cell is left
  alone and the bit stays zero;
- an **array** of bare names, closed, no rest: the subject may be shorter than the pattern down to the
  elements with no default (all at the end — the parser's rule), and each element it has sets a bit.

On success `unpacked_fixed` replaces the subject with the mask where the pattern carries defaults and
takes it off where it does not — `compose_unpack_slots`' exact stack effect, so the two instructions
are interchangeable at the site. **The defaults themselves are untouched**: the `JumpIfSet` / expression
/ `StoreSlot` triple `emit_slot_defaults` has always emitted reads the same mask. That was the design
choice the item asked for. A constant default could have been precomputed into the instruction, but a
non-constant one (`h = w * 2`, `b = counted()`) still needs the follow-up code, so precomputing would
make two paths for one rule and put a value table on the instruction; keeping the guarded assignments
costs one `JumpIfSet` per default and keeps the arm exactly as small as it was.

**`run_frames.sysl` got two lines SHORTER** (999 → 997): the arm's truncate moved into the callee,
which is where the mask is decided. The hot-arm order and `Step`'s size are unchanged.

A `?` never reaches a binding site (`refuse_optionals`), a rest and a nested pattern still walk, and a
subject that does not fit still gets `unpack_complaint`'s sentence, which already knew about defaults.

## The counts

**One instruction replaces one instruction**: `options`' 4,000,000 `UnpackSlots` become 4,000,000
`UnpackFixed`, and every `JumpIfSet`, `StoreSlot` and `Pop` after them is the same code. The totals are
identical to the instruction; what came off is a call graph — `match_walk`, `match_object`, three
`match_leaf`s or `hold_places`, three stack pushes and the `lay_bindings` copy — per call.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `a952ff2` against the branch, run twice from the
same pair of binaries, on a box at 89% idle with `pgrep -x java` empty.

| program | run A | run B |
|---|---|---|
| **options** | **−41.1%** | **−41.3%** |
| closures | −4.1% | −4.2% |
| methods | −4.2% | −3.3% |
| fib | −3.7% | −3.6% |
| fields | −3.6% | −3.7% |
| nested | −2.9% | −3.8% |
| funcs | −4.5% | −2.8% |
| dispatch | −3.6% | −1.3% |
| sorting | +4.0% | +3.2% |
| **geometric mean, all twenty-three** | **−4.09%** | **−3.69%** |

**After merging dev `386d133`** (the call-path item, which touched `run_frames.sysl` and `code.sysl`)
both binaries were rebuilt and measured a third time, control `386d133` against the merged branch,
92% idle: **`options` 493 → 285 ms, −42.2%; geometric mean −4.16%** (`fib` −5.9%, `dispatch` −4.8%,
`startup` −4.4%, `strindex` −3.4%; nothing slower than `branches` +1.9%).

**`options` goes 505 → 297 ms, which is all of the matcher share the profile named and then some** —
the 40% the profile priced was the matcher's frames, and the stack traffic and placeholder pushes
around them came off with it. The shortlist's ceiling for the mean was ~2%; the rest of the table moves
together by 2–4% on programs holding no destructuring binding at all, which is this instrument's
floor for a change that moves code in the dispatch loop's file (the arm shrank). `sorting`, whose loop
is inside a builtin, reads slower in both runs for the same reason in the other direction.
`bench/check.sh`: all four implementations' answers unchanged.

## The tests

- **`tests_slots.sysl`** — `A_ROW_OF_NAMES_WITH_DEFAULTS_TAKES_THE_INSTRUCTION_AND_LEAVES_THE_MASK`:
  `bench/options.sl`'s own function, an array head with a default, an object head whose second turn
  leaves out what the first supplied (the cell still holds the old value and only the mask says the
  default is owed), and an unpacking parameter whose default reads the name to its left — each takes
  `UnpackFixed` and no `UnpackSlots`, and each program's printed answer is asserted beside it.
  `EVERY_OTHER_SHAPE_STILL_WALKS_THE_MATCHER` now pins a NESTED default as still walking.
- **`tests_pattern.sysl`** — `A_ROW_WITH_DEFAULTS_THAT_DOES_NOT_FIT_SAYS_WHAT_THE_MATCHER_SAYS`: a
  missing field with no default, a non-object, an array below its floor, an array past its length and a
  non-array, all inside a function so the names are cells, plus a subject exactly at the floor.
- **`tests/lang/patterns.sl`** — `a_row_of_names_with_defaults_binds_the_same_at_every_site`, on both
  back ends: a `val`, a parameter, a `for` head over objects and over arrays, a default that reads a
  name to its left, one that runs only where the name is missing (its call count is asserted), a field
  a proto supplies, and a `var` row written afterwards.

## What is left

Nothing of the destructuring binding. The `JumpIfSet` per default is the remaining cost of a defaulted
name, and a constant default folded into the instruction would take it off — worth doing only if a
profile ever shows it, the guarded assignment being three short arms.
