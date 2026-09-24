# 2026-09-24 — A CALL'S ANSWER IS PROVEN PRESENT, AND IT REACHES NOTHING THE BENCHMARKS DO

The follow-up [`never-absent`](2026-09-23-never-absent.md) named in *What is left*: since
`return-undefined` (`ba4b2f0`) a function cannot answer an absence, so a call whose argument is
another call's answer may carry `KeptArgs` too. Control dev `504cfb2`; branch `never-absent-2`.

**A null result, and the write-up is mostly the measurement that says why.** The earlier item
guessed that its unmarked 20% were calls with a call as an argument; the profile says they are not.

## What changed

- **`never_absent`** (`compile_expr.sysl`): a `Call` is proven. Nothing a call reaches answers an
  absence: `Ret` refuses one and `KeepAnswer` refuses one in front of a guarded return, a generator
  falling out answers `null`, a `?.()` lands on `null`, and no builtin answers `undefined` — grep of
  every `Undefined` in the tree finds only field and element reads, parameter padding, and the value
  a bare `next()` sends in, none of them a native's answer. A class's own operator is a function
  whose `return` is checked, so operators were already proven and stay so.
- **The JavaScript back end has one predicate, `answers_present`** (`js_expr.sysl`), where it had
  two: `kept_value` in `js_stmt.sysl` asked a private `never_absent` that knew no operator at all,
  and `returned_value` asked `answers_present`, which knew operators but no `??`/`&&`/`||` and no
  call. It now mirrors the interpreter less the local names (which it does not track): literals,
  interpolation, array/object/`with`/range literals, lambdas, `is`, comparisons, unary and binary
  operators, `a ?? b` where `b` is, `a && b`/`a || b` where both are — and a call. So
  `val x = f(1)`, `val b = 1 < 2` and `return o.m(1)` bind and return without `$.keep`.
- **The JavaScript runtime was AUDITED BY RUNNING IT, not only by reading it.** A build whose `$.call`
  and both builtin paths of `$.method` fault on an `undefined` answer ran the language suite under
  node (892 passed), all 42 `tests/js` corpus programs and the 21 examples: **no builtin answered
  `undefined`**. The static half: every `return undefined` in `js_rt_*.sysl` is an internal helper
  (`strtod`, `temporalArith`, `calendarArith`, `declaredHere`, `signalNumber`) whose caller turns it
  into `null` or a fault, `pop`/`shift` fault on an empty array before answering, `httpTake` answers
  `null` for nothing held, and a host method's answer comes through `inward`, which makes `undefined`
  `null`. The instrumentation was reverted before the commit.

## How many calls it reaches

`SLATE_PROFILE=1`, `--features profile`, the 22 programs (excluding `profile.sl`), control against
branch, counting the four single-instruction rows:

| program | control marked / unmarked | branch marked / unmarked |
|---|---|---|
| `dispatch` | 1 / 5,000,001 | 2 / 5,000,000 |
| `options` | 1 / 4,000,001 | 2 / 4,000,000 |
| `csv` | 680,062 / 1,200,002 | 680,063 / 1,200,001 |
| every other program | its hot calls already marked | + the one `print(f())` at the end |
| **total** | **40,759,843 / 10,202,242 (80.0%)** | **40,759,864 / 10,202,221 (80.0%)** |

**Every program moves by exactly one call — the final `print(...)` of a call's answer.** The loops
`dispatch`, `options` and `csv` leave unmarked pass a **parameter** straight on, which is what
`never-absent`'s own table said; the brief that sent this item took their shape to be a call's
answer, and the profile is what corrected it.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), `pgo/slate` against `pgo/slate`, then again with the
two binaries' order swapped. **The box was not quiet**: 71.5% idle and another session's JVM running
(`pgrep -x java` 15315), so both columns are read for sign agreement only.

| | change |
|---|---|
| **geometric mean, branch after control** | **−0.37%** |
| **geometric mean, swapped (inverted)** | **+0.12%** (the run read −0.12% for the control) |

**Three rows agree across the orderings and none of them can be the change**: `sorting` −10.9% /
−8.2%, `csv` +6.4% / +3.9%, `arith` +2.3% / +5.3% (branch against control both times). The
bytecode those programs run is identical to the control's but for the one final `print`, and
`arith` makes no call in its loop at all — so this is the PGO build laying the interpreter out
differently, the effect `narrow-signal` saw cancel over its rows, and the means cancel here too.
That is the expected answer for a change that reaches one call per program.

## The tests

- **`tests_call_return.sysl`** — `A_CALL_CARRIES_KEPT_ARGS_ONLY_WHERE_NO_ARGUMENT_CAN_BE_AN_ABSENCE`
  moves `answer() = t(lit())` from the unmarked list to the marked one;
  `A_CALL_WHOSE_ARGUMENT_IS_ANY_KIND_OF_CALL_IS_MARKED` pins a function's, a builtin's, a method's, a
  class operator's, a constructor's and a `?.()` call's answer each marked, output asserted;
  `AN_ABSENT_ANSWER_IS_REFUSED_AT_THE_RETURN_BEFORE_THE_MARKED_CALL_IS_REACHED` is the negative
  control — a callee falling out with, or `return`ing, `o.nope` inside a marked call faults in the
  return's sentence and never in the argument's.
- **`tests_js.sysl`** — `A_BINDING_KEEPS_ONLY_WHAT_COULD_BE_AN_ABSENCE`: a call, a method call, a
  negation, `n ?? 0` and `n > 0 && 1` are bound bare; `o.a`, `n ?? o.a` and `n && o.a` still go
  through `$.keep`. Four emitted-text expectations lost their `$.keep` (a comparison, a comparison
  chain, `null ?? 3`, a guarded method call).
- **`tests/lang/absence.sl`**, both back ends — `A_CALLS_ANSWER_IS_HANDED_ON_AS_IT_STANDS` and
  `A_CALLEE_ANSWERING_AN_ABSENCE_IS_REFUSED_BEFORE_ITS_CALLER_PASSES_IT_ON`: the machine's behaviour
  and its sentences unchanged.

## What is left

The unmarked fifth is **a parameter passed straight on**, as before; proving it still needs the
caller's knowledge that it gave every argument, which a padded slot does not carry. A per-call-site
"this call gave all its parameters" bit read by the callee would be the shape of it, and it would
reach `dispatch`, `options` and `csv` — 10.2 million calls on this suite.
