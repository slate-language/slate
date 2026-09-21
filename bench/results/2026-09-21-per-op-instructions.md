# 2026-09-21 — ONE INSTRUCTION PER OPERATOR: THE LARGEST SINGLE WIN ON THIS PAGE

`a + b` emitted `BinaryOp(Plus)`, an instruction carrying the operator's token, and the token was
then matched three more times on the way to the addition: the dispatch matched the instruction,
`on_values` matched the token for `==` and `!=`, `arith` tested it for the string join, and
`int_arith` matched it again over seventeen arms. Three calls and three switches, all to reach an
operator the emitter had picked out while the program was being compiled. CPython's
`BINARY_OP_ADD_INT` is the same move.

`Op` now carries `Add`, `Sub`, `Mul`, `Div`, `IntDiv`, `Rem`, `Less`, `LessEq`, `Greater`,
`GreaterEq`, `Equal`, `NotEqual`, `BitAnd`, `BitOr`, `BitXor`, `ShiftLeft`, `ShiftRight`, `Negate`,
`Not` and `Complement` — exactly the set `power_of`'s infix table and `prefix` can build, minus the
three that short-circuit into jumps. `op_instruction`/`unary_instruction` in `code.sysl` are the one
place a token becomes one of them, and `run_arith.sysl` holds one function per operator: two machine
integers answered in place, everything else handed to `arith`, `same` or `unary` exactly as before,
and an overflow or a zero divisor handed to `int_arith` with the same token so the promotions and the
`LeastLong` edges are the ones already written rather than a second copy.

Control `c44eff0`, branch `per-op-instructions`. **It landed on `dev` as `c26567e`.**

### Instructions: the same count, under twenty names instead of one

**`--features profile` reports an IDENTICAL total on every program** — `arith` 180,000,027,
`branches` 166,149,022, `loops` 80,171,042, each to the instruction — because nothing was added or
taken away. What changed is only which name the count is filed under, so the instruction count cannot
say anything about this item at all and **the wall clock is the whole of the evidence**. `arith`'s
one `BinaryOp 50000001 27.7%` line is now `Add 20000000 11.1%`, `Less 10000001 5.5%`,
`Mul 10000000 5.5%` and `Sub 10000000 5.5%`, which is the same fifty million.

That is also the reading of finding 2 above: `BinaryOp` was **15.2% of every instruction executed**
across the whole set, and every one of them paid for three switches on a constant.

### Wall time

Alternating best-of-9 on `bench/timeit.pl`, control and branch back to back, nine times, lowest of
each kept — the method the `expr-safe-point` section above had to fall back on, and for its reason.
Box 94.6% idle, `pgrep -x java` empty, under `caffeinate`. The `/lua` columns use the best Lua time
across the two `bench/run.sh -n 5` passes taken beside it.

| | dev `c44eff0` | per-op-instructions | change | dev/lua | branch/lua |
|---|---|---|---|---|---|
| arith | 1271.0 | **1109.6** | **-12.7%** | 26.9x | 23.5x |
| alloc | 1288.6 | **1152.2** | **-10.6%** | 7.9x | 7.1x |
| branches | 1363.7 | **1226.3** | **-10.1%** | 13.2x | 11.9x |
| arrays | 1276.9 | **1153.4** | **-9.7%** | 13.7x | 12.4x |
| funcs | 951.0 | 880.4 | -7.4% | 19.6x | 18.1x |
| fib | 1664.0 | 1541.3 | -7.4% | 21.1x | 19.5x |
| loops | 942.2 | 876.1 | -7.0% | 7.9x | 7.4x |
| methods | 1925.4 | 1797.0 | -6.7% | 13.8x | 12.9x |
| closures | 850.5 | 795.3 | -6.5% | 17.9x | 16.8x |
| nested | 1435.2 | 1343.2 | -6.4% | 10.9x | 10.2x |
| fields | 1228.9 | 1151.0 | -6.3% | 19.3x | 18.0x |
| options | 1437.8 | 1346.7 | -6.3% | 17.1x | 16.0x |
| globals | 1918.4 | 1798.5 | -6.3% | 19.9x | 18.7x |
| dispatch | 1500.8 | 1407.8 | -6.2% | 16.8x | 15.7x |
| reals | 1261.5 | 1191.1 | -5.6% | 21.7x | 20.5x |
| mapset | 586.7 | 554.7 | -5.4% | 34.7x | 32.8x |
| strindex | 11.5 | 11.2 | -3.2% | 5.2x | 5.1x |
| calls | 1155.9 | 1125.6 | -2.6% | 7.4x | 7.2x |
| sorting | 834.3 | 821.2 | -1.6% | 1.4x | 1.4x |
| strwalk | 12.9 | 12.7 | -1.3% | 0.1x | 0.1x |
| csv | 509.3 | 504.9 | -0.9% | 1.7x | 1.7x |
| strings | 787.7 | 781.6 | -0.8% | 2.1x | 2.1x |
| startup | 4.9 | 4.9 | +1.6% | 2.9x | 2.9x |
| **geometric mean** | | | **-5.69%** | **8.305x** | **7.833x** |

**TWENTY-TWO OF THE TWENTY-THREE MOVED THE SAME WAY, WHICH IS WHAT MAKES THIS READABLE AT ALL.** The
noise floor the section above measured is ±1.8% on a program whose instruction count did not move,
and sixteen rows here are outside it in one direction. `startup` is the only row that went the other
way, by +1.6% on a 4.9 ms figure that runs no operator at all.

**The size of a row is the share of its instructions that are operators.** `arith` is a loop of
`total = total + i * 2 - 1` and `i = i + 1` — five operators in twenty-five instructions — and it is
the largest at -12.7%; `csv`, `sorting` and `strings` do their work inside a builtin and read under a
percent. `alloc` and `arrays` at about -10% are the surprise and are not one: both index in a loop,
and an index is a comparison and an addition before it is an allocation.

**An independent `bench/run.sh -n 5` pass per binary says the same thing** — geometric mean against
Lua **8.7x -> 8.1x**, against `node --jitless` 6.7x -> 6.3x, against CPython 4.6x -> 4.3x — which is
the coarser instrument agreeing with the fine one rather than a second measurement of it.

### Why it is worth twenty arms in the dispatch

**A switch on a value that is constant at compile time is the cheapest thing to remove and the
easiest to leave in.** Nothing here made an operation faster: `int_arith`'s addition is the addition
it always was, and every diagnostic, every promotion and every operator method is reached by exactly
the path it was reached by before. What was taken away is the *asking*, three times per operator, of
a question the compiler had already answered.

### What the shape of the fix cost, and what was refused

**The integer fast path is a function per operator rather than written out in the arm**, which is
`run_frames.sysl`'s own stated preference read the other way. Twenty arms with their overflow tests
written out take that file two hundred lines past a thousand, which is the user's rule; each of these
is instead a leaf with exactly one caller, which is the shape a compiler inlines. The measurement
above is what says the arrangement is worth what it claims. **`IterInit` and `IterAwaitCheck` moved to
`run_compose.sysl`** to pay for the room — both cold, both touching nothing but the operand stack,
which is that file's rule.

**A `_ -> Add` fallback in `op_instruction` was refused** and `NoOperator` written instead. The token
used to travel with the instruction, so an operator nothing implemented reached `arith`'s last arm and
was refused there by name; a default mapping to addition would have answered a sum to an expression
nobody wrote.

### The witness a benchmark cannot give

`tests_operators.sysl` reads the emitted code rather than the clock. Five tests assert that each
operator emits the instruction named after it and that **no** `BinaryOp` or `UnaryOp` is emitted at
all — including through a compound assignment, a step, and each leg of a comparison chain, which are
the routes that do not go through a written operator. Eight more pin the two paths against each other:
the same arithmetic at machine width and one width up, an overflowing pair growing rather than
wrapping, the most negative integer through negation, `\`, `%`, `-` and `~`, a divisor of zero in both
the written and the compound form, an integer meeting a real through every operator, equality over
every pair the fast path does not take, an operator method, the set algebra and the string join, and
the sentence an operator that applies to neither side says.

