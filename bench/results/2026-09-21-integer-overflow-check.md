# 2026-09-21 — AN INTEGER STOPPED WRAPPING, AND WHAT THE OVERFLOW CHECK COSTS

**This is the first entry here that is not an optimisation.** A slate integer has no width now: `+`,
`-`, `*`, `<<`, unary `-`, `abs` and `pow` on two machine integers are *checked*, and where an
answer does not fit 64 bits the operands are read again as `sysl.math.bigint` `BigInt`s. That is a
language decision the user took, and what this section is for is saying what it cost rather than
whether it was worth it.

**Both binaries built in this session from the two ends of one branch**, so the control is dev
**`2703d0b`** and the branch is that tree with this change and nothing else. `bench/run.sh -n 5` per
binary, box 94.4% idle at the start, `pgrep -x java` empty, nothing else building or timing.
**Every figure is the MEAN OF BOTH ORDERINGS** (control→branch and branch→control), whichever binary
runs second reading slower on this box. Milliseconds of process wall time.

| | dev `2703d0b` | big-integers | change | dev/lua | big-integers/lua |
|---|---|---|---|---|---|
| arith | 1209.8 | 1277.6 | **+5.6%** | 25.2x | 27.0x |
| reals | 1217.0 | 1275.2 | **+4.8%** | 21.2x | 21.8x |
| branches | 1285.6 | 1327.2 | +3.2% | 12.5x | 12.9x |
| closures | 826.3 | 851.6 | +3.1% | 17.4x | 17.4x |
| funcs | 913.1 | 940.4 | +3.0% | 18.3x | 19.6x |
| fib | 1555.0 | 1602.3 | +3.0% | 19.6x | 20.1x |
| sorting | 795.8 | 819.5 | +3.0% | 1.4x | 1.5x |
| fields | 1177.9 | 1211.7 | +2.9% | 19.2x | 19.2x |
| methods | 1855.2 | 1900.6 | +2.4% | 12.8x | 13.2x |
| arrays | 1231.7 | 1260.8 | +2.4% | 12.9x | 13.5x |
| options | 1387.1 | 1420.2 | +2.4% | 16.6x | 17.1x |
| dispatch | 1428.4 | 1460.0 | +2.2% | 15.8x | 16.6x |
| globals | 1917.2 | 1957.3 | +2.1% | 18.7x | 18.9x |
| mapset | 571.6 | 582.5 | +1.9% | 33.5x | 34.6x |
| alloc | 1245.8 | 1261.4 | +1.2% | 7.8x | 8.1x |
| calls | 1131.1 | 1137.4 | +0.6% | 7.3x | 7.4x |
| nested | 1395.2 | 1402.3 | +0.5% | 10.5x | 10.8x |
| strings | 768.1 | 770.9 | +0.4% | 2.1x | 2.1x |
| csv | 501.1 | 500.8 | -0.1% | 1.7x | 1.6x |
| loops | 936.3 | 936.4 | **0.0%** | 7.8x | 7.9x |
| strindex | 11.2 | 11.2 | 0.0% | 4.8x | 4.9x |
| strwalk | 12.6 | 12.9 | +2.4% | 0.1x | 0.1x |
| **geometric mean vs lua** | **8.35x** | **8.55x** | **+2.4%** | | |
| geometric mean vs node --jitless | 6.5x | 6.55x | | | |
| geometric mean vs python3 | 4.4x | 4.5x | | | |

**The overflow check costs about 2.4% on the geometric mean, 5.6% on `arith` and 3.0% on `fib`.**
Those two are the honest figures for it: `arith` is a loop of nothing but `+`, `-` and `*` on
integers, and `fib` is a loop of `+` under a call. Everything from `branches` down sits in this
machine's run-to-run spread — a code-layout shift moves any of them two or three percent, which the
`native-args` section below documents with four readings of `globals` spanning 100 ms — so the set
of benchmarks that genuinely measure this item is two, and they read +5.6% and +3.0%.

**`loops` is the control that could have disagreed and did not**: 936.3 against 936.4, a tenth of a
millisecond over both orderings, on a program whose inner loop is a counter. A loop counter is an
addition like any other, so a change that put a cost on every addition should have moved it; that it
did not says the check is genuinely three instructions and a branch that is never taken, and that
what `arith` is reading is the density of arithmetic rather than a per-operation tax that shows
everywhere.

**Two mitigations were measured and both are in the landed tree.**

- **`arith`'s dispatch became two matches from six.** The first cut asked `is_number(a)`,
  `is_number(b)`, `is_int(a)`, `is_int(b)` and then `as_int` twice — six matches over the `Value`
  union on the commonest path in the interpreter, and eight for a pair carrying a real. It is now a
  single nested match on the two operands that also unpacks them. Measured against the same control
  over both orderings: `arith` **+6.3% → +5.6%**, `reals` **+7.0% → +4.8%**, `fib` **+4.4% → +3.0%**.
  `reals` is the one worth reading, because nothing about a real overflows: the whole of its +7% was
  the dispatch in front of it, and two thirds of that came back.
- **The test for `+` and `-` is written out rather than asked of `sysl.math`'s `checked_add`.** Both
  are the same fact about a two's-complement sign bit — a sum overflows exactly when the operands
  agree in sign and the answer does not — but through a function answering an `Option` they are a
  call and a tagged value on the two commonest operations a program does. `checked_mul` is still
  asked, its test being three routes and a division rather than two exclusive-ors, and a program
  multiplies far less than it adds.

**No instruction count moved, and that is a fact about the change rather than a missing measurement.**
The one instruction this item adds is `PushBig`, emitted only for a whole literal too wide for 64
bits, and not one of the twenty-three programs here contains one — so the instruction mix under
`--features profile` is the control's exactly. What changed is what `BinaryOp` *does*, not how many
of them run, which is why the wall clock is the only instrument that can see this item at all.

**This is not on the ranked shortlist and nothing there is struck through.** The shortlist is
optimisations; this is a language change that spends some of what those bought. The mean against Lua
goes 8.35x to 8.55x, which is roughly what shortlist item 3 won back in September, and the way to
read the two together is that an integer that never wraps costs about one item's worth of work.

