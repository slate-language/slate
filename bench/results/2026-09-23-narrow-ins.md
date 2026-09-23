# 2026-09-23 — a narrower `Ins` — profile 5's item 1

**Profile 5 measured the dispatch head at twenty-two instructions and put five of them on the `Ins`
fetch**: `mov w8,#0x38`, a `madd` by fifty-six, and four loads that pull all fifty-six bytes into six
registers before the head knows which arm wants any of them — plus three spill reloads of the code
buffer's base and length, in a loop the page had already found has no registers left. Its item asked
for **sixteen bytes, one `ldp`**, by narrowing `Op` and moving the span out of the instruction.

**`Op` at 16 bytes is the win: the geometric mean is −2.06% on an alternating best-of-9**, with `fib`
−9.2%, `arith` −7.1%, `arrays` −5.8%, `branches` −5.8% and `reals` −4.9%. `Ins` is **32 bytes**, the
stride is a `lsl #5`, the head is eighteen instructions, and **not one of the three spill reloads is
left** — the code base and both lengths live in registers now.

**Moving the span out as well was built, measured and BACKED OUT: it is 1.65% SLOWER.** That build
reached the item's sixteen bytes and a thirteen-instruction head, and lost on every call-heavy
program in the set. The reason is worth the page it takes, because it re-prices two other items.

## What an instruction is now

`Ins` was `op: Op` at 40 plus `at: Span` at 16. `Op` was 40 because its widest variants carry four
`usize` — `CheckSlot(i, k, t, pk)` and `CallMethod(k, argc, names, c)` — and an enum is its tag plus
its widest payload. **The rule the file now states is that no variant's payload may exceed eight
bytes**, which makes `Op` sixteen: eight for the tag, eight for the payload, the alignment being
`PushInt`'s and `PushReal`'s 64-bit literals.

Three changes carry it, and `@assert(sizeof(Ins) == 32, …)` in `code.sysl` holds it at compile time:

- **Two operands are a pair of `u32`.** Every operand this machine has is an index — a string, a
  chunk, a slot, a cell, a jump target, a site cache, a pattern — and none can reach four thousand
  million. Seventeen variants took this: `GetField`, `SetField`, `CallFn`, `LoadSlot2`, `LoadCell`,
  `StoreCell`, `TestSlots`, `JumpIfBound`, `JumpIfGiven`, `JumpIfSet`, `DefineFn`, `DefineHook`,
  `CheckResult`, `PushShape`, `IsPat`, `Unpack` and `LoadSlotInt`. A use of one widens with
  `usize(k)`, which is a `mov w` or nothing at all on arm64.
- **The six that carry three or four operands hold a `u32` into `Unit.wide`**, a table of three
  `usize` written once per instruction at compile time: `CheckSlot`, `CallMethod`, `CheckType`,
  `DeclareCell`, `DefineDef` and `UnpackSlots`. Each keeps inline what it needs before the table read
  — `CheckSlot` its slot, `CallMethod` its argument count, `UnpackSlots` its mask — and the arm reads
  the rest. Five of the six are instructions a program reaches for a declaration or an annotation;
  `CallMethod` is the one hot exception and pays one load inside an instruction that is about to lay
  a frame.
- **`LoadSlotInt` folds a 32-bit literal, and a wider one is not folded at all.** The fused pair holds
  a slot and a literal in eight bytes, so `a + 4294967296` stays the `LoadSlot` and `PushInt` it
  always was and runs as such. `a + 2147483647` folds; `a + 2147483648` does not, and
  `tests_fused.sysl` pins both edges.

## The `otool` proof

**Before — dev `ad5ac52`, `run_frames+508`, twenty-two instructions:**

```
+508  ldr  x8, [sp, #0x220]     spill reload -- the code buffer's length
+512  cmp  x26, x8 ; +516 b.hs <trap>
+520  ldr  x8, [sp, #0x230]     spill reload -- the length again
+524  cmp  x28, x8 ; +528 b.hs <trap>
+532  mov  w8, #0x38            sizeof(Ins) = 56
+536  ldr  x9, [sp, #0x228]     spill reload -- the code buffer's base
+540  madd x9, x28, x8, x9      base + pc * 56
+544  ldp  x27, x19, [x9, #0x18]
+548  ldp  x23, x22, [x9, #0x8]
+552  ldr  w8,       [x9]       the tag
+556  ldp  x24, x25, [x9, #0x28]   the span -- the hottest PC in 18 of 19 programs
+560  add  x26, x28, #0x1
+564  cmp  w8, #0x5e ; +568 b.hi <second table>
+572  adrp/add/adr/ldrh/add/br
```

**After — eighteen, and the three spill reloads are gone:**

```
      mov  x24, x26
      cmp  x24, x21 ; b.hs <trap>
      cmp  x24, x25 ; b.hs <trap>
      add  x9, x28, x24, lsl #5    base + pc * 32
      ldr  w8, [x9]                the tag
      ldp  x20, x23, [x9, #0x8]    the payload and the span's start
      ldr  x22, [x9, #0x18]        the span's end
      add  x26, x24, #0x1
      cmp  w8, #0x5e ; b.hi <second table>
      adrp/add/adr/ldrh/add/br
```

| | dev | branch |
|---|---|---|
| `sizeof(Ins)` | 56 | **32** |
| `sizeof(Op)` | 40 | **16** |
| head instructions | 22 | **18** |
| spill reloads in the head | 3 | **0** |
| loads of the instruction | 4, into 6 registers | **3, into 4** |
| the stride | `mov` + `madd` by 56 | **`lsl #5`** |

Both tables of `bench/results/2026-09-22-one-jump-table.md` are untouched: the hot forty-two arms are
still the first forty-two written, no cold variant sits below a hot tag, and the head still reaches
one table with `cmp w8,#0x5e`.

## Wall time: alternating best-of-9

Control is dev `ad5ac52` built in a detached worktree, branch is this one; both sysl 0.0.126,
`bench/alternate.pl 9`, everything under `caffeinate -dimsu`. **The box was NOT quiet** — another
session's `sysl` held a core for both runs — which is what the alternating method is for: each
program's two binaries run back to back, nine times, lowest of each kept.

| program | control (ms) | branch (ms) | change | the 16-byte build |
|---|---|---|---|---|
| fib | 468.297 | 425.164 | **−9.2%** | +0.4% |
| arith | 269.305 | 250.207 | **−7.1%** | −0.2% |
| arrays | 427.958 | 403.003 | **−5.8%** | −0.2% |
| branches | 308.033 | 290.165 | **−5.8%** | +0.7% |
| reals | 347.314 | 330.274 | **−4.9%** | +2.8% |
| funcs | 205.758 | 196.329 | **−4.6%** | +7.0% |
| fields | 218.746 | 208.963 | **−4.5%** | +1.0% |
| closures | 199.414 | 191.368 | **−4.0%** | +1.2% |
| globals | 692.798 | 670.085 | **−3.3%** | −0.8% |
| startup | 4.541 | 4.443 | −2.2% | −0.8% |
| loops | 253.591 | 248.913 | −1.8% | +2.8% |
| sorting | 531.074 | 523.156 | −1.5% | −2.0% |
| alloc | 452.067 | 445.581 | −1.4% | +0.7% |
| mapset | 236.897 | 233.613 | −1.4% | +0.6% |
| dispatch | 395.489 | 392.645 | −0.7% | +4.8% |
| strwalk | 9.796 | 9.791 | −0.1% | +1.4% |
| csv | 277.066 | 278.224 | +0.4% | +0.9% |
| calls | 395.440 | 399.663 | +1.1% | +5.6% |
| methods | 401.749 | 406.500 | +1.2% | +1.4% |
| nested | 399.751 | 405.360 | +1.4% | +6.6% |
| strindex | 8.063 | 8.236 | +2.1% | +1.0% |
| options | 483.509 | 494.056 | +2.2% | +6.7% |
| strings | 734.588 | 762.695 | +3.8% | −2.8% |
| **geometric mean** | | | **−2.06%** | **+1.65%** |

**The five programs that are up are the five that call the most**, and the one load `CallMethod` now
makes into `Unit.wide` is the candidate: `options`, `nested`, `methods` and `calls` are between +1.1%
and +2.2%, and every program that is down by more than 3% is one whose inner loop is arithmetic, a
slot read or a field access. `strings` at +3.8% is the one number this page cannot explain; it was
−2.8% in the other build, which is the shape of a program whose time is in `Join` and the allocator
rather than in the dispatch.

Against the yardsticks, `bench/run.sh -n 5` on the branch: **2.9x lua, 2.2x node --jitless, 1.8x qjs,
1.5x CPython**.

## The sixteen-byte build, and why it lost

The item asked for sixteen bytes, which needs the span out of the instruction. That build put every
chunk's spans in one `Unit.spans` buffer, gave `Chunk` and `Frame` a `span_base`, and replaced the
head's `val at = ins.at` with `u.spans.at(span_base + here_pc)` at the eighty-seven places an arm
uses a span. It works, it is correct — every test in the suite passes on it — and it reached exactly
what the item wanted:

| | dev | 16-byte build |
|---|---|---|
| `sizeof(Ins)` | 56 | **16** |
| head instructions | 22 | **13** |
| the stride | `madd` by 56 | `lsl #4` |
| geometric mean | | **+1.65%** |

**The premise was that almost nothing reads a span, and the premise is false.** A span is not only
what a fault points at — it is an ARGUMENT, passed eagerly to the leaf an arm calls so that the leaf
can build a fault if it needs one. Every arithmetic operator passes one. `GetField` and `SetField`
pass one. `AddStoreSlot` passes one, and it is 20% of `loops`. A call passes one **per argument**,
inside the loop that checks each argument is keepable — which is why `funcs` (+7.0%), `options`
(+6.7%), `nested` (+6.6%), `calls` (+5.6%) and `dispatch` (+4.8%) are the programs that lost most.

Fetched with the instruction, a span costs nothing at the arm: it is already in two registers. Fetched
from a second buffer it is an address, a bounds check that cannot be hoisted or sunk because it may
trap, and a load — paid on the hot path to save it on the cold one. **Nine instructions off the head
do not pay for four or five instructions in every arm that does any work**, and the second buffer
costs the locality the narrower stride had just won.

**What this re-prices.** Profile 5 said the span load at `+556` was the hottest PC in eighteen of
nineteen programs and read that as the span being expensive. It is not: that PC is where the cache
miss on the instruction's own line is attributed, and the line is what the narrower stride fixes.
**A hot sample on the last load of a multi-load fetch says the FETCH is expensive, not the field.**
The same argument applies to profile 5's item 5, the register machine: its claim is fewer instructions
dispatched, and this page's two builds together say the head's instruction count is worth roughly
0.2% per instruction while the bytes fetched per instruction are worth much more.

**The eighty-seven call sites are the other half of the answer, and a cheaper version exists.** An arm
that uses a span more than once could bind it once, and a leaf that only wants it for a fault could
take the unit and an index and materialise it on the error path alone. That is a change to thirty-odd
helper signatures across `arith.sysl`, `index.sysl` and the rest, and it is the only way the sixteen
bytes could be got back. Nothing here says it would win; it says the version that does not do it
loses.

## What the answers say

`bench/check.sh ./slate`: **all twenty-three programs answer what they answered before**, on slate,
lua, node and python3.

**Instruction counts are identical to the instruction.** `SLATE_PROFILE=1` on `fib`, `branches`,
`loops`, `arith`, `methods` and `calls`, built `--features profile` on both sides, differ in nothing
but wall time and the microseconds attributed to `print`. That is the check that says the narrowing
is a layout change and nothing else: no instruction was added, removed, fused differently, or
executed a different number of times.

## Tests

- `tests_site_cache.sysl` — `sizeof(Ins) == 32`, with the reason; this is the pin that was `56`.
- `code.sysl` — `@assert(sizeof(Ins) == 32, …)`, which fails the BUILD rather than a test.
- `tests_site_cache.sysl` — a method call with a named argument, a hundred thousand times, which
  exercises all three of `CallMethod`'s operands in `Unit.wide` including the argument-names index
  that is zero in every ordinary call.
- `tests_slots.sysl` — a slotted annotation and a slotted destructuring in a hundred-thousand-turn
  loop, plus the sentence a failing annotation writes, which is made of the two operands a passing
  check never reads.
- `tests_fused.sysl` — the fusion edge: `2147483647` folds, `2147483648` does not, and the unfolded
  pair still answers.
- `tests_frames.sysl` — a fault after fifty returns points at the caller's own line, and three
  programs whose fault is at a different depth each point at their own.
