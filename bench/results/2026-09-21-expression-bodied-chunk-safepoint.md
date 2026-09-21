# 2026-09-21 — AN EXPRESSION-BODIED CHUNK GAINED A SAFE POINT, AND WHAT THE GUARANTEE COSTS

**This is the hole the section above left open, closed.** A chunk whose body is one expression —
`down(n) = n > 0 && down(n - 1)`, `(v) -> v * scale` — never goes through `compile_stmts`, so it
carried no `Tick` at all: a recursion through such functions could be neither collected nor
interrupted however deep it went, the ceiling and the collector's schedule both being read at a safe
point and nowhere else. `compile_chunk` emits one at the head of such a chunk now, in front of the
defaults, so a default that calls back into the chunk is inside the guarantee too. A block-bodied
chunk gains nothing, its first statement's safe point already standing at the head. **The rule reads:
every chunk passes a safe point before it can recurse.**

**It is the interpreter's alone** — no `js*.sysl` file mentions `Tick` or `safe_point`, the JavaScript
back end having no such instruction — so nothing about `slate js` moved.

### Instructions

Both binaries built with `--features profile` from the two ends of one branch; control is dev
**`78c43d8`**, the commit this branch merged. Counts are exact and need no quiet box.

| | control | branch | change |
|---|---|---|---|
| all 23 programs | 1,952,577,154 | **1,992,982,930** | **+2.07%** |
| `Tick` among them | 107,774,395 (5.52%) | **148,180,171 (7.44%)** | **+37.5%** |

**Every added instruction is a `Tick` and only SEVEN programs have one** — the other sixteen are
byte-for-byte identical, which is what makes them the controls the timing below is read against.
`fib` **+8.00%** (11,405,775 `Tick`s to 22,811,548 — its `fib` is expression-bodied, so the count
doubles), `calls` +7.41%, `nested` **+6.24%** (`weigh = (v) -> v * scale`, called six million times),
`closures` +5.00%, `methods` +4.76%, `funcs` +4.17%, `dispatch` +3.03%.

### Wall time, and the instrument that had to be thrown away first

**`bench/run.sh -n 5` per binary in both orderings said the branch was FASTER, which is impossible
for a change that only adds instructions** — geometric mean against Lua 8.8x for the control and
8.6x for the branch, `strings` **-38%** and `strwalk` -14% on instruction counts that are identical
and collector figures that are unchanged. The section above found the same thing and said so; this
run is the second witness. Averaging the two orderings cancels a first/second effect and does not
cancel drift over the four passes.

**So the table is alternating best-of-9 on `bench/timeit.pl`, the timer `run.sh` itself uses**:
control and branch run back to back, nine times, lowest of each kept, so the two are never more than
one run apart. Box 86% idle, `pgrep -x java` empty, under `caffeinate`. Milliseconds of process wall
time; the `/lua` columns are against the best Lua time seen across the four `run.sh` passes, so they
are comparable to each other and not to the page's other tables.

| | dev `78c43d8` | expr-safe-point | change | dev/lua | branch/lua |
|---|---|---|---|---|---|
| fib | 1618.1 | **1656.5** | **+2.4%** | 20.0x | 20.5x |
| methods | 1957.2 | **2002.1** | **+2.3%** | 13.6x | 13.9x |
| arrays | 1284.4 | 1307.2 | +1.8% | 13.8x | 14.1x |
| nested | 1424.9 | 1447.8 | +1.6% | 11.0x | 11.1x |
| fields | 1224.2 | 1242.3 | +1.5% | 19.4x | 19.7x |
| dispatch | 1498.9 | 1519.1 | +1.4% | 16.9x | 17.1x |
| startup | 4.9 | 5.0 | +1.1% | 2.6x | 2.6x |
| loops | 948.8 | 958.3 | +1.0% | 7.9x | 8.0x |
| arith | 1295.2 | 1303.8 | +0.7% | 27.0x | 27.2x |
| calls | 1165.1 | 1173.1 | +0.7% | 7.7x | 7.8x |
| branches | 1344.8 | 1352.1 | +0.5% | 12.9x | 12.9x |
| strindex | 11.6 | 11.7 | +0.5% | 4.8x | 4.9x |
| sorting | 843.0 | 846.5 | +0.4% | 1.4x | 1.4x |
| reals | 1297.9 | 1302.9 | +0.4% | 23.1x | 23.1x |
| alloc | 1309.8 | 1314.8 | +0.4% | 8.1x | 8.1x |
| mapset | 594.5 | 596.5 | +0.3% | 34.4x | 34.5x |
| closures | 871.9 | 869.3 | -0.3% | 17.9x | 17.9x |
| options | 1450.4 | 1446.2 | -0.3% | 17.2x | 17.1x |
| funcs | 960.9 | 955.4 | -0.6% | 19.9x | 19.7x |
| csv | 523.2 | 519.7 | -0.7% | 1.7x | 1.7x |
| strwalk | 13.4 | 13.2 | -0.9% | 0.1x | 0.1x |
| globals | 1994.5 | 1972.1 | -1.1% | 19.2x | 19.0x |
| strings | 805.5 | 791.3 | -1.8% | 2.1x | 2.1x |
| **geometric mean** | **8.265x** | **8.305x** | **+0.49%** | | |

**THE SIXTEEN UNCHANGED PROGRAMS ARE THE NOISE FLOOR AND THEY SAY IT IS ±1.8%.** `arrays` reads
+1.8% and `strings` -1.8% on instruction counts that did not move by one, so no single row under
that is evidence of anything. **Only `fib` (+2.4%) and `methods` (+2.3%) stand above it**, and both
are programs whose instruction count rose most; `nested`, whose count rose 6.24%, reads +1.6% and is
inside the floor. The geometric mean over twenty-three programs is what averages the drift out, and
it says **+0.49%** — about a fifth of what the same guarantee would cost if every chunk paid it,
which is the first cut this section's predecessor refused.

**So the price of the rule is half a percent of the geometric mean**, against a recursion that could
previously run to any depth with the collector never asked and the interruption never read.

### The witness a benchmark cannot give

`tests_bookkeeping.sysl` reads the emitted code rather than the clock:
`A_CHUNK_WHOSE_BODY_IS_ONE_EXPRESSION_CARRIES_ONE_SAFE_POINT` asserts **one** `Tick` for an
expression-bodied definition and for a lambda, and **two — unchanged** for a two-statement block
body, which is what says a block-bodied chunk gained nothing.
`A_RECURSION_THROUGH_EXPRESSION_BODIES_IS_STILL_BOUNDED` runs an allocating recursion written
entirely in expression bodies against a one-megabyte heap and requires the ceiling to stop it, with
the dropping twin as the control that must still finish;
`A_RECURSION_THROUGH_EXPRESSION_BODIES_IS_STILL_INTERRUPTIBLE` is
`AN_UNCONDITIONAL_LOOP_IS_STILL_INTERRUPTIBLE`'s twin through a lambda that never ends.
`tests/lang/frames.sl` asks both back ends for a two-thousand-deep expression-bodied recursion.

**A NEGATIVE CONTROL WITH THE PREDICATE INVERTED REDDENS ALL FOUR**, which is how the assertions were
checked: it gives the block-bodied chunk five `Tick`s where four are expected and the
expression-bodied one none where one is, and both heap proofs fail.

