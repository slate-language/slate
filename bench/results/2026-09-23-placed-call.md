# 2026-09-23 — THE ORDINARY CALL ASKS ONE PRECOMPUTED BIT, INLINE

The item `call-return` left open ([its write-up](2026-09-23-call-return.md), *What is left*):
`placed_call` was still out of line, and every ordinary call asked it four flags — `slotted`, not
variadic, not `async`, not a generator — plus the depth limit and the name count, and took its
answer back as a seven-word `CallPlan`. Profile 6 put `placed_call` at 8.6% of `fib`. Control dev
`8bd0c9d` (the `call-return` merge); branch `placed-call-bit`.

## What changed

- **`Chunk.in_place_ok`** (`code.sysl`): the four flags answered once. `compile_chunk` writes it
  beside `slotted`, the last of the four to be known; every other chunk (a module, its declarations
  chunk) is made with it false, which sends a call the buffered way as before.
- **`placing`** (`execute.sysl`, `@inline`): the ordinary question asked where the call instruction
  stands. No names, under the depth limit, a `Fn` whose chunk says `in_place_ok` — answer `InPlace`
  from the chunk's fields; anything else goes to `placed_call`, which answers it exactly as it always
  has. `placed_call`'s own `Fn` arm reads the same bit, so the two cannot disagree about a closure,
  and a constructor still reaches its `new` through it.
- **Both call arms** (`CallFn` and `CallMethod`) ask `placing` instead of `placed_call`, `InPlace`
  still first. `run_frames.sysl` did not grow (989 lines).

## The disassembly

`otool -tV -p '_dev.slatelang.slate$run_frames'`, the in-place path from the `CallFn` arm's first
instruction to the `InPlace` arm's (the arm itself — `keepable_on`, the shift, `lay_standing`, the
frame push — is unchanged and not counted):

| | control | branch |
|---|---|---|
| in the arm before the plan is known | 29 | 55 |
| `placed_call`, the `Fn` path: prologue, four flags, depth, the fields, epilogue | 59 + `bl`/`ret` | — |
| after the answer, testing its tag | 6 | 7 |
| **total** | **94, one call** | **62, no call** |

The plan was in fact returned in **registers** (`x0`–`x7`), not through memory as the open item
guessed; what was dear was the call itself, `placed_call`'s five-pair prologue and epilogue, and
four byte loads and branches where one does. The branch still carries two things LLVM did not take
away: six spill stores of the callee's words (the slow path wants them after the check fails), and
the inlined plan's tag is set and tested once (`mov w0, #0` then `cmp`/`b.ne` twice) rather than
the fast path jumping straight to the arm. `run_frames` as a whole grew by ~257 instructions, the
inlined question being written into both call arms.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `8bd0c9d` against the branch at `026737d`,
box at 91.9% idle with `pgrep -x java` empty at the start.

| program | control ms | branch ms | change |
|---|---|---|---|
| **funcs** | 141.4 | 128.4 | **−9.2%** |
| **fib** | 273.7 | 253.2 | **−7.5%** |
| **methods** | 286.4 | 272.6 | **−4.8%** |
| **closures** | 120.6 | 115.2 | **−4.5%** |
| globals | 165.6 | 158.1 | −4.5% |
| **nested** | 244.5 | 233.6 | **−4.4%** |
| options | 232.4 | 223.0 | −4.0% |
| startup | 4.7 | 4.5 | −3.8% |
| fields | 151.1 | 148.2 | −2.0% |
| arith | 147.0 | 144.7 | −1.6% |
| **calls** | 266.1 | 263.1 | **−1.1%** |
| reals, arrays, branches, sorting, strwalk, dispatch, loops | | | −1.0% to +0.2% |
| mapset, csv, alloc, strindex, strings | | | +0.6% to +3.4% |
| **geometric mean, all twenty-three** | | | **−1.84%** |

The six call rows the item named all moved the right way. `calls` moves least because its loop is
dominated by what the call ALLOCATES (a string literal and an object per call — the live shortlist's
row 1), not by deciding how to enter. The rises are in programs with no slate call in their loop
(`strings`, `strindex`, `alloc`, `csv`) and sit at this instrument's floor; the box had fallen to
66% idle by the end of the run, which is the more likely reading than layout.

## Instruction counts

No `Op` changed, so the counts are identical to the instruction.

## What was not tried

**The compile-time "never absent" bit** that would let a call skip `keepable_on` per argument. The
previous agent's per-call version lost to layout (+0.3%/+0.9%); a compile-time proof needs a spare
bit in `CallFn`'s eight-byte payload and a per-argument analysis in the emitter, which is its own
item rather than a rider on this one.

## The tests

**`tests_call_return.sysl`** — three new:

- `THE_IN_PLACE_BIT_IS_THE_FOUR_FLAGS_ANSWERED_ONCE_FOR_EVERY_CHUNK` — a program holding an
  ordinary function, a variadic one, an `async` one, a generator, one keeping its scope for a
  lambda, a lambda and the file itself: every chunk's bit equals the four flags, each "no" is there
  for its own reason, and the ordinary one says yes.
- `A_VARIADIC_AN_ASYNC_AND_A_GENERATOR_CALL_STILL_TAKE_THE_BUFFER` — five hundred calls of each
  charge `Vm.args_buffered` at least five hundred, with five hundred ordinary calls as the control
  that charges under a hundred; each program's output is asserted.
- `AN_ORDINARY_CALL_AT_THE_DEPTH_LIMIT_IS_REFUSED_WITH_THE_ORDINARY_SENTENCE` — a function and a
  method recursing past `MaxCallDepth` are refused in the one sentence, with a recursion inside the
  limit as the control.

## What is left

The inlined plan's tag test and the six spills above: a fast path that jumped straight to the
`InPlace` arm would take ~10 more instructions off, but sysl has no way to say it short of writing
the arm's body twice. `keepable_on` per argument, and `Ret`'s second bounds check, as before.
