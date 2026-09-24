# 2026-09-23 — A CALL WHOSE ARGUMENTS CANNOT BE ABSENT SKIPS THE REFUSAL

The item `call-return` and `placed-call` both left open ([call-return](2026-09-23-call-return.md),
*What was tried and backed out*; [placed-call](2026-09-23-placed-call.md), *What was not tried*):
every in-place call ran `keepable_on` once per argument, and the per-CALL version of the check lost
to layout. What was owed was a proof, made while compiling, that no argument can be an absence, so
the check does not run at all. Control dev `c93c580` (the `mapset-sorting` merge, which had just
inlined `keepable_on`'s tag test); branch `never-absent-bit`.

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
  `undefined`, and before it is declared a lookup cannot reach it (a non-parameter slot is padded
  with `null` in any case). A **parameter's** slot says no — a parameter nobody gave reads as the
  absence `lay_frame` padded it with — and so does a pattern's.
- **Both in-place arms** (`run_frames.sysl`) skip the per-argument loop when the bit is set. The
  buffered path checks every argument whatever the bit says. `run_frames.sysl` +2 lines.
- **The profile files a marked call apart** (`CallFnKept`, `CallMethodKept`), which is how the reach
  below was counted.

## How many calls it reaches

`SLATE_PROFILE=1` over the 23 programs: **40,759,843 marked calls, 10,201,442 unmarked — 80%**.
Every call in the loops of `fib`, `funcs`, `calls`, `methods`, `closures`, `nested`, `mapset`,
`strings`, `sorting` and `arrays` is marked. The unmarked are almost all three programs:
`dispatch` (5,000,001), `options` (4,000,001) and `csv` (1,200,002) — each passes a **parameter**
straight on, which is the one local the proof cannot cover.

## The disassembly

`otool -tV -p '_dev.slatelang.slate$run_frames'`, the `CallFn` `InPlace` arm's argument check, with
`keepable_on`'s tag test already inlined on dev (the refusal itself is `absent_refusal`, out of line):

| | control | branch, bit clear | branch, bit set |
|---|---|---|---|
| before the loop | 4 (`cbz`, a spill, `neg`, `mov`) | 4 (`tbnz w17, #31`, a reload, `cbz`, `neg`) | **1** (`tbnz`, taken) |
| per argument | ~20 (bounds-checked peek, tag load, `cmp`/`b.ne`, loop step) | ~20 | 0 |
| **`fib(n - 1)`, one argument** | **~24** | **~24** | **1** |

`CallMethod`'s arm is the same shape.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `c93c580` against the branch at the merge
of that dev, box at 89.8% idle with `pgrep -x java` empty, then **again with the two binaries' order
swapped** (83.1% idle at the start; the swapped column is that run's change inverted, so both read
branch against control):

| program | control ms | branch ms | change | swapped: change |
|---|---|---|---|---|
| funcs | 128.3 | 116.3 | **−9.4%** | −9.1% |
| methods | 278.4 | 265.3 | **−4.7%** | −3.8% |
| calls | 179.1 | 171.8 | −4.1% | −3.6% |
| fib | 252.3 | 243.7 | −3.4% | −3.2% |
| closures | 113.1 | 110.5 | −2.3% | −3.5% |
| nested | 228.0 | 223.3 | −2.1% | −1.5% |
| sorting | 125.6 | 120.1 | −4.3% | −2.1% |
| dispatch | 258.1 | 252.9 | −2.0% | −3.0% |
| arrays | 187.2 | 196.3 | +4.9% | +3.2% |
| arith | 137.1 | 139.7 | +1.9% | +3.1% |
| **geometric mean** | | | **−2.19%** | **−0.93%** |

**The call programs agree in both orderings** (`funcs`, `methods`, `calls`, `fib`, `closures` all
−3 to −9%), and they are the programs whose loop makes a marked in-place call. The no-call programs
scatter both ways by a few percent, which is layout: the branch's `run_frames` makes ~600 more stack
references than the control's (3,339 against 2,735), so the register allocator did not come out
ahead elsewhere. The first measurement, against `b95fbcf` before `keepable_on` was inlined, read
−7.8% with `branches` −21.6% on no call at all; the merge of `mapset-sorting` took that away, and the
numbers above are the ones against the dev this lands on.

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

**A call's RESULT is now provably present** (`return-undefined`, 2026-09-24): `Ret` refuses an
absence, so a slate function cannot answer one and a builtin never did. Marking call results
never-absent in the analysis is the follow-up that reaches the ~20% of calls this item left checked.
