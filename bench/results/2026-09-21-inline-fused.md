# 2026-09-21 — THE FOUR SUPERINSTRUCTION ARMS ARE WRITTEN OUT IN THE DISPATCH — shortlist item 1

**`fused_load_slot_int`, `fused_add_store_slot`, `fused_load_slot2` and `fused_less_jump_if_false`
were functions in `run_fused.sysl`, called once each from the `match` in `run_frames.sysl`.** The
[third sampled profile](2026-09-21-sampled-profile-3.md) put the four at **7.41% of weighted wall
time** and showed the `run_frames + <offset>` → `fused_*` call-graph edges that say they are calls:
a `bl` and a frame around ten instructions, paid once per fused pair. Each one is now written out in
its own arm, and `nm` finds none of the four symbols in the binary.

**Measured: -1.96% on the alternating best-of-9 geometric mean**, against a ceiling of 3–5%.
Control is dev `bf4dd9b`. `fib` -6.4%, `arith` -5.3%, `fields` -4.5%, `branches` -3.9%,
`mapset` -3.7%, `loops` -3.2%.

## WHY `-O2` DID NOT INLINE THEM, WHICH IS A FACT ABOUT THE FILE SPLIT AND NOT ABOUT THEIR SIZE

**`private` in sysl is private to the FILE.** These four are called from `run_frames.sysl` and were
written in `run_fused.sysl`, so they could not be `private` — and that is the whole of it. Read off
`sysl emit-llvm .`, which emits the entire program as ONE LLVM module (541,157 lines for slate):

```
define void @dev.slatelang.slate$fused_load_slot2(...)                     ← external linkage
define internal %enum.sysl$Option.string @dev.slatelang.slate$operator_method(...)   ← `private`
```

So sysl lowers a `private` function to `define internal` and a module-visible one to a plain
`define`. An externally-linked body must be kept whatever the inliner decides, so LLVM's
single-caller bonus — the "last call to a static", which is what brings a function of this size under
the `-O2` threshold — never applies; and these are not small by the inliner's measure, `Span` being
passed by value and `Result[Option[Value], Signal]` returned through an `sret`. The manifest already
says `optimization = "2"` and there is nothing to change there: **`-O2` was doing the right thing
about a function it was not allowed to delete.**

**The rule that falls out: a fast path that has to be inline goes in the file its caller is in.**
There is no `@inline` attribute in sysl (only `@noinline` and `@cold`), so the placement *is* the
instruction — and hand-writing it in the arm makes the outcome certain rather than a threshold's
verdict. `run_fused.sysl` is the same finding in reverse: it still holds `stored_in_slot`, the cold
tail `AddStoreSlot` reaches only where its sum is not whole, and that one is a call on purpose.

## What changed

| | was | now |
|---|---|---|
| `LoadSlot2` | `fused_load_slot2(vm, base, i, j)` | two reads and two pushes in the arm; both cells still read before either is pushed |
| `LoadSlotInt` | `fused_load_slot_int(vm, base, i, v)` | one read and two pushes in the arm |
| `AddStoreSlot` | `fused_add_store_slot(...)? match` over `Option[Value]`, then `stored_in_slot` | the int-int sum and the overflow test in the arm, storing straight into the cell; the other path calls `added` and `stored_in_slot` |
| `LessJumpIfFalse` | `fused_less_jump_if_false(vm, at)?` | the int-int comparison in the arm; the other path calls `is_less`, which `run_arith.sysl` already held |

**The `Option` in the two hot arms is a tagged union of a scalar and costs nothing**: the fast path
answers `Some(sum)` / `Some(!(x < y))` and the arm reads it back, which is how a value is carried out
of a `match` without a second call. The `pc += 1` that steps over the slot `fuse` left standing is
unchanged in all four, and so is every sentence: the absence refusal still reads its span out of the
`StoreSlot` the fusion stepped over, on the one path that needs it.

### `run_frames.sysl` had to be cut first, and the cut is `run_compose.sysl`'s existing rule

The file was **994 lines** against the project's thousand-line limit, and writing four bodies into it
adds 33. Seven more arms moved to `run_compose.sysl`, every one meeting that file's stated test —
*touches none of the loop's own state, and already allocates, walks a list or runs a lookup*:

`compose_seal_data`, `compose_check_slot`, `compose_declare_name` (which is `DeclareVal` and
`DeclareVar`, one flag apart), `compose_declare_absent`, `compose_store_name`,
`compose_unpack_slots` and `compose_define_fn`. Every one of them either hashes a spelling and walks
the scope chain (`declare`, `assign_name`, `lookup`) or runs the pattern matcher. **`LoadName` stayed
inline** — a read by name is far commoner than a write or a declaration — and so did `Discard`,
`IterNext` and the arithmetic, which are the hot ones.

`run_frames.sysl` is **971 lines** after both halves.

**`globals` is the witness that the cut cost nothing**: it is the one benchmark whose loop is at a
module's top level, so it is the one that executes the moved by-name arms, and it measured **+0.2%** —
inside the noise. The two rows that went the wrong way, `strings` +2.2% and `alloc` +1.5%, run their
loops **inside functions**, which is to say in slotted chunks that never reach a moved arm at all;
both are allocation-bound, and that is where this set's run-to-run variance lives.

## Instructions: identical, to the instruction

**This is a pure codegen change and the counts prove it.** `--features profile` built on both sides,
and `diff` of the two reports differs in the wall-clock line and the per-builtin microseconds and in
nothing else — every instruction-kind count, every pair and every triple is the same number:

| | instructions | `LoadSlotInt` | `LoadSlot2` | `AddStoreSlot` | `LessJumpIfFalse` |
|---|---|---|---|---|---|
| arith | 130,000,025 | 20,000,001 | 10,000,000 | 10,000,000 | 10,000,001 |
| branches | 121,451,942 | 27,437,679 | 1,978,038 | 8,281,858 | 6,999,505 |
| fib | 119,760,624 | 22,811,545 | — | — | 11,405,773 |
| nested | 84,108,048 | 12,001 | 12,000,000 | 6,006,000 | 7,002 |
| loops | 64,138,039 | 16,001 | 8,000,000 | 8,008,000 | 9,002 |

So the wall clock is the whole of the evidence, exactly as it was for
[one instruction per operator](2026-09-21-per-op-instructions.md).

### The symbols are gone, which is the other half of the proof

```
nm slate-control | grep fused        nm slate | grep fused
T _…$fused_add_store_slot            (nothing but _…$refused, an unrelated name)
T _…$fused_less_jump_if_false
T _…$fused_load_slot2
T _…$fused_load_slot_int
```

Four `T` — external text symbols — in the control, none in the branch.

## Wall time

Alternating best-of-9 on `bench/timeit.pl` (`bench/alternate.pl 9`), control and branch back to back,
nine times, lowest of each kept. Box 84.4% idle, `pgrep -x java` empty, under `caffeinate -dimsu`.
The `/lua` columns use the Lua times from the `bench/run.sh -n 5` pass taken beside it.

| | dev `bf4dd9b` | inline-fused | change | dev/lua | branch/lua |
|---|---|---|---|---|---|
| fib | 553.6 | **518.3** | **-6.4%** | 6.7x | 6.3x |
| arith | 285.1 | **270.0** | **-5.3%** | 5.9x | 5.6x |
| fields | 271.3 | **259.2** | **-4.5%** | 4.5x | 4.3x |
| startup | 4.81 | 4.59 | -4.5% | 2.4x | 2.3x |
| branches | 337.3 | **324.1** | **-3.9%** | 3.2x | 3.1x |
| mapset | 254.7 | **245.2** | **-3.7%** | 15.0x | 14.4x |
| strwalk | 10.69 | 10.31 | -3.6% | 0.07x | 0.07x |
| strindex | 9.00 | 8.70 | -3.3% | 3.8x | 3.6x |
| loops | 307.4 | **297.5** | **-3.2%** | 2.5x | 2.4x |
| reals | 363.8 | 354.9 | -2.4% | 6.7x | 6.5x |
| nested | 504.4 | 493.4 | -2.2% | 3.8x | 3.7x |
| options | 591.4 | 581.2 | -1.7% | 7.0x | 6.9x |
| dispatch | 485.7 | 477.9 | -1.6% | 5.2x | 5.1x |
| methods | 564.6 | 555.7 | -1.6% | 3.8x | 3.8x |
| closures | 248.2 | 246.0 | -0.9% | 5.1x | 5.1x |
| sorting | 522.5 | 519.3 | -0.6% | 0.90x | 0.89x |
| arrays | 435.8 | 433.4 | -0.5% | 4.7x | 4.7x |
| calls | 560.8 | 559.2 | -0.3% | 3.6x | 3.6x |
| csv | 371.4 | 371.8 | +0.1% | 1.24x | 1.24x |
| globals | 1113.2 | 1115.3 | +0.2% | 11.3x | 11.4x |
| alloc | 607.7 | 616.8 | +1.5% | 3.7x | 3.7x |
| funcs | 243.5 | 247.6 | +1.7% | 5.1x | 5.2x |
| strings | 720.6 | 736.6 | +2.2% | 1.93x | 1.97x |
| **GEOMEAN** | | | **-1.96%** | | |

**Eighteen of twenty-three faster, and the ranking is the profile's own.** The programs that moved are
exactly the ones profile 3 named: `branches` carried 14.0% + 3.7% + 2.5% in the three arms, `arith`
10.3% + 9.7% + 7.4%, `fib` 6.8%, `fields` 5.9%. The programs that did not move are the ones whose
time is in the allocator or in a builtin — `alloc`, `strings`, `sorting`, `csv`, `calls` — where a
`bl` per fused pair was never a measurable share.

**Why -1.96% against a 3–5% ceiling.** The 7.41% was weighted self time, and the frame around a
handful of instructions is not the whole of what a call costs nor all of what is recovered: a
prologue and an epilogue come off, but the arm's code now shares the dispatch's register pressure and
the fused work itself remains. The ceiling was read as though the whole 7.41% were overhead; about a
quarter of it was.

## What is left of `run_fused.sysl`

The prose — what a fused pair is, which four pairs and why they were measured rather than guessed,
and now **why a body that has to be inline may not live in a file of its own** — plus
`stored_in_slot`. That file is where the next session proposing a fifth pair should look, and the
paragraph about linkage is the one to read before writing the fifth one anywhere but in the arm.

## Tests

**None added: this is a pure refactor, so rule 4-0's second half applies** — no declaration, no
signature and no body answers differently, which the identical instruction counts and the identical
profile reports are the evidence for. `tests_fused.sysl` already asserts every fused pair is
answer-for-answer identical to the two instructions it replaces, including the two sentences that
belong to the `StoreSlot` rather than to the `Add`, and it is green unchanged; two of its comments
were rewritten where they named a function that no longer exists.
