# 2026-09-21 — SUPERINSTRUCTIONS: TWO INSTRUCTIONS RUN AS ONE, AND THE LARGEST WIN ON THIS PAGE

Shortlist item 4, and the second time in two days that an item's estimate was less than half of what
it measured: the ceiling written against it was **4-6%** of the geometric mean and the answer is
**-9.17%**, with twenty-two of the twenty-three programs faster.

**WHAT IS BOUGHT IS THE INSTRUCTION FETCH.** The sampled profile at the head of this page puts
`Buf.at<Ins>` at **12.4% of all sampled time** — an out-of-line call, once per instruction executed,
that retains the code buffer, bounds-checks it twice and copies 56 bytes. Two instructions run as one
pay it once. What goes with it is the push and the pop of the value between them, which on
`AddStoreSlot` and `LessJumpIfFalse` is a `Buf.push<Value>` and a truncate that existed only to move
a number from one instruction to the next.

### The pairs were MEASURED, and three of the five this page guessed are not in the top eighteen

**`profile.sysl` counts adjacent PAIRS and TRIPLES now, under the same `--features profile` the
per-kind counts are under.** A table of instruction kinds cannot tell `LoadSlot; LoadSlot` from two
loads a jump lands between, so it cannot choose a fusion; `run_frames` hands `profile_step` one extra
boolean saying whether this instruction ran directly after the last counted one **in the same chunk
activation** — a position alone is not enough, a return landing one past its call — and the two
tables fall out of that. `SLATE_PROFILE=1` prints the twenty heaviest of each.

Summed over `arith`, `loops`, `fib`, `nested`, `calls`, `methods` and `dispatch` (876M instructions):

| pair | executions | where it is heaviest |
|---|---|---|
| `LoadSlot` `PushInt` | **82.8M** | arith 16.6%, fib 14.8%, calls 10.3%, dispatch 8.8%, methods 6.8% |
| `LoadSlot` `LoadSlot` | **55.0M** | loops 19.9%, nested 17.6%, arith 5.5%, methods 4.5% |
| `Tick` `LoadSlot` | 54.1M | fib 11.1%, methods 6.8%, nested 5.8% |
| `Add` `StoreSlot` | **40.0M** | loops 9.9%, nested 5.8%, dispatch 5.8%, arith 5.5% |
| `StoreSlot` `Jump` | 34.0M | loops 9.9%, nested 5.8%, arith 5.5% |
| `Less` `JumpIfFalse` | **31.4M** | fib 7.4%, arith 5.5%, calls 3.4% |
| `PushInt` `Less` | 31.4M | (subsumed: its head is folded first) |

**The four in bold are what landed.** `Tick`+`LoadSlot` and `StoreSlot`+`Jump` were measured and left
out, and not for being small: a left-to-right scan folds `LoadSlot`+`PushInt` first, so the loop head
`Tick; LoadSlot; PushInt; Less; JumpIfFalse` is already five instructions down to three without them,
and the increment `LoadSlot; PushInt; Add; StoreSlot; Jump` is already five down to three. They would
have bought a fourth arm each and almost nothing.

**Three of the five pairs this page guessed are wrong.** `Dup`+`StoreSlot` and `LoadSlot`+`Ret` are
not in the top eighteen at all, and `PushInt`+`Add` (20.0M) is real but half the size of
`LoadSlot`+`PushInt`, which was on no list. **The lesson is the same one the one-instruction-per-
operator item taught from the other side: a shortlist written from what the code LOOKS like is worth
less than one measurement**, and the instrument cost about forty lines.

### The fusion is legal whatever jumps at it, because the second instruction is LEFT WHERE IT WAS

`fuse` in `emit.sysl` runs over a finished chunk and overwrites **only the first slot** of a pair; the
second stays in the code buffer exactly as the emitter wrote it, and the fused arm steps over it with
an extra `pc += 1`.

**The obvious peephole — delete what you fold and renumber the jumps — is the one that is wrong the
moment a target is missed**, and this chunk has five kinds of them: seven `Jump*` opcodes,
`PushHandler`, `PushDispose`, `IterNext`, and the positions `defs.sysl` writes down to put a resolved
read back. Leaving the tail standing means **no index moves at all**, so:

- a jump into the middle of a group runs the very instruction it always ran and computes what it
  always computed — there is nothing to prove and no set of targets to gather;
- `Handler`'s recorded stack height is right, a fused pair leaving the stack where the two left it;
- `settle_module_defs` finds its `LoadDef` where it left it. **No fusion may name `LoadDef` at either
  end**, and the `match` is the enforcement: every head and every tail is written out.

`tests/lang/fused.sl` has the programs that land a jump inside a group — `(a || c) + d`, where the
short circuit skips `c` and resumes on a load the emitter has already folded onto it — and
`tests_fused.sysl` reads the emitted chunk back and asserts that a jump really is aimed there, a test
that could not have failed being no evidence.

**The span is the FIRST instruction's**, which is the one that can fault in three of the four.
`AddStoreSlot` is the exception: the absence refusal belongs to the store and has to point where the
unfused `StoreSlot` pointed, so the arm hands the value back rather than writing it and the loop reads
that span out of the slot it skipped — on the path where the sum is not a whole number, which was
going to fault or allocate anyway.

### Instructions

Every fused pair removes exactly one dispatch per execution, so the count is the measurement.
`--features profile`, same programs, before and after:

| program | dev `50ec04f` | `superinstructions` | change |
|---|---|---|---|
| arith | 180,000,027 | 130,000,025 | **-27.8%** |
| fib | 153,977,942 | 119,760,624 | **-22.2%** |
| loops | 80,171,042 | 64,138,039 | **-20.0%** |

`arith` runs 15.3% `LoadSlotInt` and 7.6% each of `LoadSlot2`, `AddStoreSlot` and `LessJumpIfFalse`;
`loops` 12.4% each of `LoadSlot2` and `AddStoreSlot`; `fib` 19.0% `LoadSlotInt` and 9.5%
`LessJumpIfFalse`.

### Wall time

Alternating best-of-9 on `bench/timeit.pl`, control and branch back to back, nine times, lowest of each
kept (`bench/alternate.pl` is that method as a script). Control is a detached build of dev `50ec04f`,
the commit this branched from. Under `caffeinate`, `pgrep -x java` empty, box at 90.5% idle.

| program | dev `50ec04f` | `superinstructions` | change |
|---|---|---|---|
| alloc | 1169.866 | 1048.474 | **-10.4%** |
| arith | 1142.286 | 921.638 | **-19.3%** |
| arrays | 1154.368 | 945.959 | **-18.1%** |
| branches | 1244.762 | 944.927 | **-24.1%** |
| calls | 1067.417 | 1028.214 | -3.7% |
| closures | 729.218 | 607.239 | **-16.7%** |
| csv | 509.209 | 493.086 | -3.2% |
| dispatch | 1307.019 | 1169.257 | **-10.5%** |
| fib | 1295.980 | 1235.853 | -4.6% |
| fields | 1172.883 | 1067.148 | **-9.0%** |
| funcs | 771.471 | 677.487 | **-12.2%** |
| globals | 1819.860 | 1766.983 | -2.9% |
| loops | 901.632 | 808.023 | **-10.4%** |
| mapset | 573.079 | 515.427 | **-10.1%** |
| methods | 1738.999 | 1613.871 | -7.2% |
| nested | 1266.902 | 1195.015 | -5.7% |
| options | 1278.272 | 1220.840 | -4.5% |
| reals | 1227.531 | 997.283 | **-18.8%** |
| sorting | 837.682 | 826.011 | -1.4% |
| startup | 4.887 | 4.695 | -3.9% |
| strindex | 11.230 | 10.844 | -3.4% |
| strings | 805.482 | 817.316 | +1.5% |
| strwalk | 13.113 | 12.211 | -6.9% |
| **geometric mean** | | | **-9.17%** |

`bench/run.sh -n 5` afterwards: geometric mean **7.2x** Lua (was 7.9x), **5.5x** `node --jitless`
(was 6.1x), **3.8x** CPython (was 4.2x).

**THE WINNERS ARE THE PROGRAMS WHOSE INNER LOOP IS ARITHMETIC OVER LOCALS, which is the shape of the
answer rather than an accident.** `branches` -24.1%, `arith` -19.3%, `reals` -18.8% and `arrays`
-18.1% are all `LoadSlot; PushInt; <op>` and `Less; JumpIfFalse` written out several times a turn.
`sorting` -1.4%, `globals` -2.9% and `csv` -3.2% do their work inside a builtin, a table or a hash,
where there is no run of cheap instructions to fold. **`strings` +1.5% is the only program that went
backwards** and it is the one whose time is 78% `_platform_memmove`; the difference is a percent of
a program that folds almost nothing, and two further runs of it landed either side of zero.

### What was deliberately NOT done, so nobody proposes it again without new evidence

- **A fused TRIPLE.** `LoadSlot LoadSlot PushInt` is 15.0M and `LoadSlot PushInt Less` 31.4M — but
  the second is already two instructions once its head is folded, and the first saves one dispatch
  over the pair that already covers it. A triple costs an arm and a three-slot scan for the same
  instruction a pair removes.
- **A fused arm per OPERATOR.** `Sub`+`StoreSlot` and `Mul`+`AddStoreSlot` both show up in the
  after-profile at 8-10M, and folding each of the twenty operators onto a store would be twenty more
  arms in the hottest `match` in the project. `Add` is folded because it is four times the next one;
  a second should wait for a program that shows it.
- **Carrying the operator IN the fused instruction**, which would be one arm instead of twenty and is
  exactly what `per-op-instructions` took OUT for -5.69%. Do not put the switch back.
- **Overlapping the scan.** A run of three loads becomes one `LoadSlot2` and one `LoadSlot`, not two
  groups sharing an instruction, because the second group's head would be a slot this pass has just
  overwritten.

### The tests, and the file that had to be cut first

`tests_fused.sysl` reads emitted chunks back: the four pairs are folded, each fused instruction is
directly followed in the buffer by the instruction it folded, three loads leave one standing, and a
jump really is aimed inside a group. `tests/lang/fused.sl` asks both back ends the same twelve
questions — the JavaScript one compiles from the tree and has no superinstructions, so it is the
control — covering the order two pushes arrive in, an overflow promoted out of a folded sum, a string
join, a class's own `+`, a comparison of two strings, and the three faults.

**`run_frames.sysl` was at 999 lines of a thousand before any of this**, so five arms came out before
four went in: `CheckType`, `CheckResult`, `Unpack`, `IsPat`, `TestPat`, `RotUp` and `DefineDef` are
functions in `run_compose.sysl` now — each one reads the operand stack and `vm.scope` and none of them
touches `pc`, `base`, `code` or `given`, which is that file's own rule — and the fused arms' bodies
are `run_fused.sysl`. It ends at 988.

