# 2026-09-23 — A FRAME HOLDS ITS CODE AS AN ADDRESS AND A COUNT — profile 6's item 4

Profile 6's row 4 ([the profile](2026-09-23-sampled-profile-6.md), question 4): on `fib` the `CallFn`
and `Ret` arms are 19% of the executions and **51%** of the loop's machine instructions, with
`placed_call` 8.6%, `lay_standing` 3.7% and `keepable_on` 1.6% out of line — call and return about
half of the program. The page named two suspects, read off the source: `Frame` carrying a counted
`code: Buf[Ins]`, and the `keepable_on` loop over the arguments.

**The first was real, and it was bigger than the call.** The disassembly of `run_frames` at the
control shows it: the ordinary call retained the entered chunk's code into the plan, retained the
leaving chunk's into the `Frame` it pushed, and `Ret` copied the frame out (a retain), truncated the
frame stack (a release), overwrote the loop's local (a retain and a release) and dropped its copy (a
release). **And because the loop's `code` local was counted, every instruction's `code.at(pc)` was a
bounds-checked read of a counted slice.** Control `a59aeee` (dev after `unpack-defaults`); branch
`call-return`.

## What changed

- **`Frame.code` is a `Code`** (`vm.sysl`): the first instruction's address (`*Ins`) and the count.
  It owns nothing, so a frame is plain data — the push is nine stores and no retain, and `Ret` is
  loads. `code_view(buf)` makes one, `null` and 0 for a chunk with no instructions.
  - **What keeps the instructions alive is the unit.** A chunk's `code` is written once when it is
    compiled and never grown or replaced after (a patch writes in place); growing the chunk *table*
    moves the `Chunk` records and not the storage `code` points at; and the three places a unit is
    replaced — `run`, `prepared`, `loaded_and_checked` — all `reset_vm` first, so no frame, parked
    machine or generator outlives its unit. `vm.sysl` states this beside the type.
  - **This is sysl's documented unsafe tier and not a gap**: a `*T` is indexed unchecked
    (`reference/arrays.md`, *A raw pointer is indexed anyway*), which is exactly what was wanted.
- **The loop's head reads `code.ins[pc]` unchecked**, behind the `pc >= code.len` test it already
  made. That test now **panics** rather than pushing null and carrying on: every chunk the compiler
  makes ends in `Ret` (`compile.sysl` and `compile_stmt.sysl` are the three sites), so running off
  the end is a compiler defect, and a test pins that every chunk of a program exercising every kind
  of body ends in `Ret`.
- **`run_frames` reads the entered chunk where it stands** (`&u.chunks.elems[i]`) rather than
  copying the 136-byte `Chunk` out once per `run_frames` — the same move `call-path` made in
  `placed_call`, at the one site it left. `invoke`, `placed_call` and `start_generator` hand a
  `Code` on; `resume_sent` (from `next-undefined`, merged in) reads through the view with its own
  bound check.
- **`lay_standing` takes the machine** rather than asking `machine()` (a thread-local read) and sets
  the mask as one subtraction, `(1 << kept) - 1`, with sixty-four parameters as its own branch.

**`run_frames` went from 9,979 machine instructions to 7,314** (`otool -tV`), and the frame push
after `lay_standing` in the `CallFn` arm is now nine stores with no count touched.

## What was tried and backed out: one `undefined` question per call

`standing_absent(vm, argc)` — a loop of tag compares over the argument cells, with `keepable_on`
called only when it answered yes — in place of `keepable_on` per argument, on both in-place arms.
**It lost.** Against the step-one binary it measured **+0.33%**, and with the refusal marked
`@cold @noinline` **+0.88%**: `fib` −2.2%/−2.7% and `nested`/`options` −2–3%, but `branches`,
`loops`, `arith` and `reals` — programs with no call in their loop — +4–6%. That is code layout in
the one function every instruction runs through, not the check, and it was reproducible across two
builds. `keepable_on` per argument stays; the tests written for the refusal stay with it (below).
**A compile-time proof that an argument cannot be absent** (a literal, an arithmetic result) is what
would take it off without touching the arm's shape, and needs an `Op` bit to carry.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `a59aeee` against the branch at `ce1b54f`
(dev merged in), box at 88.1% idle with `pgrep -x java` empty.

| program | control ms | branch ms | change |
|---|---|---|---|
| **dispatch** | 367.9 | 310.9 | **−15.5%** |
| **closures** | 174.9 | 148.1 | **−15.4%** |
| **nested** | 302.4 | 257.3 | **−14.9%** |
| **options** | 287.5 | 245.8 | **−14.5%** |
| **fib** | 398.4 | 342.0 | **−14.2%** |
| **methods** | 392.1 | 336.7 | **−14.1%** |
| **funcs** | 184.4 | 158.8 | **−13.9%** |
| **calls** | 319.6 | 279.9 | **−12.4%** |
| startup | 5.0 | 4.6 | −8.1% |
| strwalk | 9.0 | 8.5 | −4.8% |
| mapset | 215.4 | 206.6 | −4.1% |
| arrays | 252.6 | 243.5 | −3.6% |
| arith | 253.8 | 244.9 | −3.5% |
| branches | 301.0 | 291.0 | −3.3% |
| sorting | 529.3 | 512.6 | −3.2% |
| strindex | 7.5 | 7.3 | −3.2% |
| every other program | | | within ±1.5% |
| **geometric mean, all twenty-three** | | | **−6.76%** |

Nothing is slower than +0.8% (`strings`), which is this instrument's floor.

**By step**, each an alternating best-of-9 against the one before it:

| step | against | geometric mean | the call rows |
|---|---|---|---|
| 1. `Code` in the frame, unchecked head, chunk read in place | control `01434a4` | **−6.38%** | `funcs` −18.3%, `fib` −16.8%, `nested` −16.7%, `dispatch` −16.5%, `closures` −16.4%, `methods` −12.0%, `calls` −10.9% |
| 2. `standing_absent` (backed out) | step 1 | +0.33% | `fib` −2.2%, `branches` +4.5%, `arith` +5.9% |
| 2b. the same, refusal `@cold @noinline` (backed out) | step 1 | +0.88% | `fib` −2.7%, `branches` +5.5%, `loops` +4.6% |
| 2c. `lay_standing` takes the machine, one-subtraction mask | step 1 | **−1.17%** | `fib` −4.8%, `closures` −3.6%, `sorting` −2.6% |

The non-call programs take 3–4% from step 1 too — `arith`, `branches`, `arrays` have no call in
their loop — which is the unchecked head: every instruction lost a bounds check and a counted local.

## Instruction counts

No `Op` changed, so the counts are identical to the instruction.

## The tests

- **`tests_call_return.sysl`** — eight: every chunk of a program holding a function, a lambda, an
  empty body, a generator, an `async` function, a class and a top level ends in `Ret`; a `Code` is
  the buffer's own storage and count, and `null`/0 for an empty one; a three-function mutual
  recursion 300 deep, allocating at every level on a one-megabyte heap, returns through every frame's
  own code (and asserts it collected); a generator parked across collections resumes its own code
  five times; an `undefined` argument is refused first, middle and last, and at a delegated method
  and an own one, with the controls that run; the in-place mask fills defaults and drops a surplus;
  and a function of **sixty-four** parameters takes the in-place path and gets the exact mask both
  ways.
- **`tests/lang/arity.sl`** — `AN_ABSENCE_IS_REFUSED_WHEREVER_IT_STANDS_AMONG_THE_ARGUMENTS`, the
  same positions on both back ends.

## What is left

`placed_call` is still out of line and answers a seven-word `CallPlan` through memory; its four flag
tests could be one precomputed `Chunk` bit. `keepable_on` per argument stays until the compiler can
say an argument is never absent. `Ret` still bounds-checks the frame stack it just tested the height
of.
