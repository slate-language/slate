# 2026-09-23 — A THROWN VALUE LIVES OFF THE `Signal`, AND `Step` IS 64 BYTES AGAIN

slate 0.1.2 measured **+13.3% slower than 0.1.1** on an alternating best-of-9 of the two release
binaries. This is the bisect that found why, and the change that undid it without taking the feature
out.

Control `54c138a` (dev, sysl 0.0.127); branch `signal-slim`.

## The bisect

Every segment an alternating best-of-9 of two built binaries (`bench/alternate.pl 9`), positive meaning
the later commit is slower:

| segment | what it holds | geometric mean |
|---|---|---|
| SEG1 | `4ec2413`, one jump table | −3.1% |
| SEG2 | `ad5ac52`, `freeze` | +0.4% |
| **SEG3** | **`ad5ac52` → `04eee0f`** | **+14.8%** |
| SEG4 | `d62c8ba`, optional chain | −0.4% |
| SEG5 | narrowing `ins` | −1.1% |
| **SEG3a** | **`34d2adf`, throw carrying a value — sysl 0.0.125 both sides, SOURCE ONLY** | **+17.92%** |
| SEG3b | `04eee0f`, the sysl 0.0.126 pickup | −3.57% |

SEG3a is the whole of it and more, SEG3b paying a little back. Every one of twenty-three programs moved
in SEG3a, and the biggest movers were programs that never throw — `mapset` +62.9%, `reals` +57.9%,
`sorting` +50.5% — which is what said the cost was on the path every instruction takes and not on the
path a fault takes.

## The mechanism: `Step` doubled

`34d2adf` gave `Signal.Fail` a fourth field, `value: Option[Value]`, so a `catch NotFound(id)` could
bind the value a program threw. `Value` is forty bytes and its `Option` forty-eight, which made `Fail`
the widest variant by far. Read off `sysl emit-llvm .`:

| | before `34d2adf` | dev `54c138a` | branch |
|---|---|---|---|
| `Signal` | `{ i32, [6 x i64] }` — 56 B | `{ i32, [12 x i64] }` — **104 B** | `{ i32, [6 x i64] }` — 56 B |
| `Step = Result[Value, Signal]` | `{ i32, [7 x i64] }` — 64 B | `{ i32, [13 x i64] }` — **112 B** | `{ i32, [7 x i64] }` — **64 B** |

`run_frames` returns a `Step` by value (`define %enum.sysl$Result…Signal @…run_frames(…)`), and so does
every helper an arm calls through `?`. So every arm of the instruction loop built, copied and returned
an aggregate nearly twice as wide as before, whether or not anything was ever thrown. Nothing else in
the commit touches the ordinary path: the `Raise` arm, `guarded`'s hold and the promise's `thrown` flag
all run only when a fault does.

## What it is now

**`Fail(at: Span, src: u32, carried: u32, message: string)`.** The value lives in `Vm.carried`, a
`Buf[Value]` on the VM, and `carried` is its index plus one — zero meaning the fault carries nothing,
which is every fault the machine raises and every `throw` of a string. `src` narrowed from `usize` to
`u32` so the two share the word `src` had: `Fail` is 48 bytes, exactly what it was before
`34d2adf`, and `Step` is 64 again.

- **`carry(v)` puts a value in, `take_carried(id)` takes it out**, and the table reuses freed entries
  through `carried_free` before it grows. `failure_in(at, src, message, Option[Value])` in
  `runtime.sysl` is the one constructor the rest came down to; `failure` and `value_failure` are it
  with the current file.
- **Taken exactly once, by whatever CONSUMES the fault**: the `catch` in `guarded`, a promise the fault
  rejects (`finish_call`, `finish_generator`), a disposal's own fault suppressed under another, a
  handler fault a window page is told about, and `assertFaults`. A `Signal` is copied freely while it
  travels and only its last stop reads the value.
- **The table is a ROOT**, marked in `roots` beside the shadow stack. That replaced two things
  `34d2adf` needed: `guarded` holding the payload across a `using` release, and `roots` marking what
  `loop_fault` carried. A carried value is reachable wherever the `Signal` naming it has got to — a sysl
  local, `loop_fault`, a machine's `suppressed` — without anybody holding it by hand.
- **A fault nobody takes leaves its entry until the heap is given back** (`reset_heap` →
  `forget_carried`). That is a fault that ended the program, so nothing is lost; a program that throws
  and catches in a loop holds one entry however long it runs, and a test pins that.
- **A promise still carries its rejection's value in `pr.value`**, as `34d2adf` arranged; the value is
  taken out of the table when the promise is settled and put back in when the awaiting machine is
  resumed with the fault.

## The table

Alternating best-of-9, `perl bench/alternate.pl 9 <control> <branch>`, milliseconds, quiet box (89.6%
idle, no JVM):

| program | dev `54c138a` | branch | change |
|---|---|---|---|
| alloc | 524.932 | 438.507 | −16.5% |
| arith | 374.780 | 257.280 | −31.4% |
| arrays | 359.743 | 250.091 | −30.5% |
| branches | 380.853 | 298.478 | −21.6% |
| calls | 449.315 | 392.255 | −12.7% |
| closures | 244.477 | 195.444 | −20.1% |
| csv | 294.306 | 250.089 | −15.0% |
| dispatch | 450.630 | 391.992 | −13.0% |
| fib | 507.836 | 461.668 | −9.1% |
| fields | 279.855 | 208.809 | −25.4% |
| funcs | 270.124 | 206.911 | −23.4% |
| globals | 731.896 | 658.940 | −10.0% |
| loops | 202.121 | 155.924 | −22.9% |
| mapset | 375.912 | 237.177 | −36.9% |
| methods | 525.743 | 417.488 | −20.6% |
| nested | 396.517 | 327.756 | −17.3% |
| options | 537.700 | 491.892 | −8.5% |
| reals | 555.555 | 336.460 | −39.4% |
| sorting | 755.199 | 505.544 | −33.1% |
| startup | 4.600 | 4.325 | −6.0% |
| strindex | 7.668 | 7.113 | −7.2% |
| strings | 713.025 | 710.220 | −0.4% |
| strwalk | 9.370 | 8.425 | −10.1% |
| **geometric mean** | | | **−19.42%** |

**It recovers more than SEG3a lost** (+17.92% is −15.2% the other way). The difference is the
commits since, which were measured against a `Step` already 112 bytes wide and were all paying the
same width. The programs that moved most in SEG3a are the ones that move most here, in the same order:
`mapset`, `reals`, `sorting`.

## The witness

The width itself, which is what the benchmark cannot say: `sizeof(Step)` is 112 on dev and 64 on the
branch, and `A_STEP_IS_NO_WIDER_THAN_IT_WAS_BEFORE_A_FAULT_COULD_CARRY_A_VALUE` in
`tests_carried.sysl` asserts it — a field added to `Fail` or `Skip` that widens `Step` again fails the
suite rather than showing up as a slower release.

No `Op` changed, so instruction counts are identical; the change is below every arm and inside none.

## The tests

`tests_carried.sysl`, beside the tests `34d2adf` added (`tests_syntax.sysl`, `tests/lang/faults.sl` on
both back ends), all of which pass unedited:

- **`A_STEP_IS_NO_WIDER_THAN_IT_WAS_BEFORE_A_FAULT_COULD_CARRY_A_VALUE`** — the width.
- **`A_PROGRAM_THAT_THROWS_AND_CATCHES_IN_A_LOOP_HOLDS_NO_CARRIED_VALUE_AFTERWARDS`** — a thousand
  value faults, every entry given back, the table no bigger than one.
- **`A_REJECTION_CARRYING_A_VALUE_GIVES_ITS_ENTRY_BACK_WHEN_IT_IS_CAUGHT`** — the promise path, both
  through an `async` function's `throw` and through `reject`.
- **`A_RELEASE_THAT_FAULTS_WITH_A_VALUE_WHILE_ANOTHER_TRAVELS_DROPS_ONLY_ITS_OWN`** — a `using`
  release throwing a value of its own while a value fault unwinds past it: the original is caught, the
  release's is dropped from the table.
- **`A_VALUE_FAULT_NOBODY_CATCHES_IS_STILL_REPORTED_BY_WHAT_IT_SAYS`** — the error path.

`a_value_fault_survives_a_collection_while_it_is_unwinding` (`tests_syntax.sysl`) is the one that would
catch a table that was not a root: it runs the same unwind against a one-megabyte heap.
