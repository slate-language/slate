# 2026-09-23 — A CALL WHOSE ARGUMENTS CANNOT BE ABSENT SKIPS THE REFUSAL

The item `call-return` and `placed-call` both left open ([call-return](2026-09-23-call-return.md),
*What was tried and backed out*; [placed-call](2026-09-23-placed-call.md), *What was not tried*):
every in-place call ran `keepable_on` once per argument, and the per-CALL version of the check lost
to layout. What was owed was a proof, made while compiling, that no argument can be an absence, so
the check does not run at all. Control dev `b95fbcf` (the `construction` merge); branch
`never-absent-bit`.

## What changed

- **`KeptArgs`** (`code.sysl`): the top bit of `CallFn`'s and `CallMethod`'s `argc`. No payload
  grew (`Op` stays eight bytes, `Step` 64); `call_argc` takes the bit off before the count is used.
- **`never_absent`** (`compile_expr.sysl`): an argument is proven when it is a literal other than
  `undefined`, a unary or arithmetic or comparison result, an interpolated string, an array, object,
  range, lambda or `with` literal, an `is` test, `a ?? b` with `b` proven, `a && b`/`a || b` with
  both proven, or a read of a slot `declare_name` filled. Everything else is not: a field, an
  element, a `?.` chain, a call's answer (a function **can** return an absence — `g() = o.nope` does,
  and passing it on is refused), `if`/`match`/blocks, `await`/`yield`, a spread, a named argument,
  and a name the file reads by name.
- **`Emit.sure`** (`emit.sysl`, `slots.sysl`): whether each slot, by number, is one `declare_name`
  filled. Such a slot is written only by `DeclareSlot` and `StoreSlot`, both of which refuse
  `undefined`, and before it is declared a lookup cannot reach it. A **parameter's** slot says no —
  a parameter nobody gave reads as the absence `lay_frame` padded it with — and so does a pattern's.
- **Both in-place arms** (`run_frames.sysl`) skip the per-argument loop when the bit is set. The
  buffered path checks every argument whatever the bit says. `run_frames.sysl` 992 → 994 lines.
- **The profile files a marked call apart** (`CallFnKept`, `CallMethodKept`), which is how the reach
  below was counted.

## How many calls it reaches

`SLATE_PROFILE=1` over the 23 programs: **40,759,843 marked calls, 10,201,442 unmarked — 80%**.
Every call in the loops of `fib`, `funcs`, `calls`, `methods`, `closures`, `nested`, `mapset`,
`strings`, `sorting` and `arrays` is marked. The unmarked are almost all three programs:
`dispatch` (5,000,001), `options` (4,000,001) and `csv` (1,200,002) — each passes a **parameter**
straight on, which is the one local the proof cannot cover.

## The disassembly

`otool -tV -p '_dev.slatelang.slate$run_frames'`, the `CallFn` `InPlace` arm's argument check:

| | control | branch, bit clear | branch, bit set |
|---|---|---|---|
| before the loop | 2 (`cbz`, `neg`) | 3 (`tbnz w17, #31`, `cbz`, `neg`) | **1** (`tbnz`, taken) |
| per argument, in the arm | 24 (peek, bounds, 5-word load, set-up, `bl`, `cbnz`, step) | 24 | 0 |
| per argument, `keepable_on` itself | 20 (5 `stp`, `cmp`, `b.eq`, 8 `mov`, 5 `ldp`, `ret`) | 20 | 0 |
| **`fib(n - 1)`, one argument** | **46** | **47** | **1** |

`CallMethod`'s arm is the same shape. **The whole of `run_frames` also changed**: 27,874 lines of
disassembly to 26,234, and references to `sp` from 4,026 to 3,379 — the register allocator, which
works over the whole function, spilling ~650 fewer times. That is the larger part of what follows.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `b95fbcf` against the branch at `694c29d`,
box at 87.2% idle with `pgrep -x java` empty, then **again with the two binaries' order swapped**
(86.9% idle):

| program | control ms | branch ms | change | swapped: change |
|---|---|---|---|---|
| fib | 284.8 | 240.2 | **−15.7%** | −14.2% |
| funcs | 145.9 | 118.7 | **−18.7%** | −21.2% |
| calls | 212.5 | 202.8 | −4.6% | −5.1% |
| methods | 299.9 | 269.2 | **−10.3%** | −11.0% |
| closures | 121.4 | 112.4 | −7.4% | −8.6% |
| nested | 242.7 | 230.7 | −4.9% | −5.8% |
| branches | 296.3 | 232.4 | −21.6% | −18.2% |
| globals | 198.7 | 163.2 | −17.9% | −17.6% |
| dispatch | 296.8 | 262.0 | −11.7% | −10.5% |
| mapset | 188.7 | 190.7 | +1.0% | +0.5% |
| sorting | 498.9 | 504.2 | +1.1% | +1.2% |
| **geometric mean** | | | **−7.83%** | **−7.29%** |

(The swapped column is the second run's change inverted, so both columns read branch against
control.) **Both orderings agree to within a point on every row**, so this is not the box drifting.

**What it is, honestly: two effects of different sizes.** The check skipped is real and is on the
programs with calls in their loop — `fib`, `funcs`, `methods`, `closures`. But `branches`, `globals`,
`arith`, `fields` and `dispatch` make **no marked call in their loop**, and they moved by as much:
that is the register allocation of `run_frames` above, which dropping a `bl` from two arms of a
function the size of the dispatch let LLVM redo. The previous agent's per-call version moved the
same programs the **other** way (+4–6%). So a later change to `run_frames` can give some of this
back without touching calls at all, and anyone measuring an item against this dev should expect the
no-call programs to be sensitive.

## The tests

**`tests_call_return.sysl`** — two new:

- `A_CALL_CARRIES_KEPT_ARGS_ONLY_WHERE_NO_ARGUMENT_CAN_BE_AN_ABSENCE` — one call per function: a
  literal, locals (`val` and `var`), arithmetic and negation, an interpolated string and a
  comparison, `o.a ?? 0`, and a method call with literals are marked; `o.a ?? p`, a field, an
  element, a parameter, a `?.` chain, a call's answer and `1 && o.a` are not; a spread has no count
  at all; `call_argc` gives the written count back. The program's output is asserted.
- `A_LOCAL_THAT_COULD_HAVE_HELD_AN_ABSENCE_REFUSED_IT_BEFORE_THE_MARKED_CALL` — the negative
  control: a `val` bound from, and a `var` written over with, a parameter nobody gave, each followed
  by a marked call of it. Both are refused **at the binding**, in its own sentence, before the call
  is reached; given a value, both calls answer.

**`tests/lang/arity.sl`**, both back ends —
`A_CALL_OF_PROVEN_ARGUMENTS_STILL_REFUSES_THE_ONE_IT_COULD_NOT_PROVE`: `three(o.nope, 2, 3)`,
`three(1, k + 1, o.nope)`, `three(1, k, o?.nope)`, a parameter nobody gave passed on, and
`Tripled(1).plus(o.nope)` are all refused with "cannot be passed to a function"; the proven calls
beside them answer.

## What is left

A parameter passed straight on — `dispatch`, `options`, `csv` — keeps the check. Proving it would
need the CALLER's knowledge that it gave every argument, which a slot's padding does not carry; a
chunk-level "every call site of this function gave all its parameters" is not knowable while
functions are values.
