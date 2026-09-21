# 2026-09-20 — A LOOP BODY GAVE UP ITS `Tick`s — shortlist item 3

`Tick` stood in front of **every statement in the language**. It asks the collector whether it is
time and reports a heap that has outgrown its ceiling, and it was 9.57% of every instruction this set
executes — two of the nineteen in `arith`'s inner loop.

**A statement in a loop's body is the only kind that runs more than once for having been written
once.** A body of six statements asked the collector six times a turn where the turn is the thing
that repeats; a run of statements outside a loop is as long as it was written, so it runs once per
time it is reached and allocates a bounded amount however long the program runs. **So a loop body's
statements give their safe points up to ONE at the top of the loop, and everything else keeps its
own.** `safe_point` in `emit.sysl` is the whole of it, with `Emit.in_loop` — lexical, so a branch, a
`match` arm or a `try` written inside a loop body is inside the same cycle and covered by the same
instruction, while a lambda in there compiles into a chunk with an `Emit` of its own.

**The placement inside the loop is not free to choose.** It stands at the instruction both the back
edge *and* a `continue` are aimed at — the top for `while`, `loop` and `for`, and the **test** for
`do … while`, whose `continue` goes there rather than to the top. Written at the back edge instead, a
body ending in `continue` would go round for ever without reaching one.

### Why a statement OUTSIDE a loop kept its own, which was the second attempt

The first cut put a safe point at the top of every loop and at the head of every chunk and **nowhere
else**, on the argument that those are the machine's only two cycles. It is sound about cycles and it
broke two things the suite already pinned, both worth writing down:

- **A NAMED HEAP CEILING STOPPED MEANING ANYTHING IN STRAIGHT-LINE CODE.** `heap_limit` is read at a
  safe point and nowhere else, so `val b = toBytes("x".repeat(4194304))` followed by `print(b.length)`
  — two statements, no loop — allocated four megabytes inside a one-megabyte ceiling and finished
  happily. `A_HEAP_LIMIT_A_PROGRAM_NAMED_BOUNDS_ITS_PAYLOAD_AND_NOT_ONLY_ITS_CELLS` in
  `tests_payload.sysl` is what caught it, and an actor's `{ heap: N }` is the promise it would have
  broken.
- **It cost more than it saved on the call-heavy programs.** A body that is one EXPRESSION rather
  than a block never goes through `compile_stmts`, so it carried no `Tick` at all — and a head-of-chunk
  safe point gives one to every such call. `nested`'s `weigh = (v) -> v * scale` is called six million
  times, `methods`' `dot` and `scaled` three million each: those three benchmarks executed 2 to 6%
  MORE instructions, and the whole set came to -3.50% for **no wall time at all**.

Keeping the per-statement safe point outside loops costs nothing measurable — such a statement is
reached once per call — and it is what makes the ceiling real. The set went from -3.50% to **-4.45%**
and from no wall time to about one percent.

**One thing did change and it is a diagnostic rather than a guarantee: a full heap inside a loop now
names the LOOP and not the statement.** There is nothing else left to point at, and the turn is the
thing that repeated. `a_program_that_outruns_the_heap_is_told_rather_than_crashed` asserts the new
sentence.

### Instructions

Both binaries built with `--features profile` from the two ends of one branch; control is dev
**`ff9709e`**, which is where this branch was cut and is **before items 5 and 6 landed** — so every
figure below is this change against that tree and not against the page's newest baseline. Counts are
exact and need no quiet box.

| | control | branch | change |
|---|---|---|---|
| all 23 programs | 2,106,742,555 | **2,012,984,971** | **-4.45%** |
| `Tick` among them | 201,531,979 (9.57%) | **107,774,395 (5.35%)** | **-46.5%** |

**Not one program executes more than it did**, which is the difference from the first cut. The ones
that moved most are the ones with several statements in a loop body — `branches` -13.71% (28,400,197
`Tick`s to 2,003,975), `mapset` -8.00%, `sorting` -8.69%, `alloc` -7.14%, `arith` and `reals` and
`globals` -5.26% each. `fib` and `loops` do not move: `fib`'s body is one statement and `loops`'
inner `for` is one statement in the outer `while`, so there was never a second `Tick` to take.

### Wall time

**`bench/run.sh -n 5` per binary in both orderings gave a mean that could not be trusted at the row
level, and proving that is worth more than the rows.** Two benchmarks whose instruction counts are
*identical* on the two binaries — `fib` and `nested`, 0.00% each — read **-2.7%**, and `strings` read
+8.7% on -4.76% of its instructions with its collector byte-for-byte unchanged (45,627 collections,
597,285 allocator steps, the same high water on both). Averaging the two orderings cancels a
first/second effect and does not cancel drift over the seventy minutes four passes take.

**So the table below is alternating best-of-7**: control and branch run back to back, seven times,
lowest of each kept, so the two are never more than one run apart. Box 92% idle, nothing else
running. Milliseconds of process wall time.

| | dev `ff9709e` | tick-rarer | change | dev/lua | branch/lua |
|---|---|---|---|---|---|
| branches | 1438.6 | **1364.0** | **-5.2%** | 13.5x | 12.8x |
| mapset | 608.0 | **579.3** | **-4.7%** | 34.4x | 32.7x |
| arith | 1298.8 | **1251.5** | **-3.6%** | 26.2x | 25.2x |
| reals | 1289.5 | 1246.6 | -3.3% | 21.6x | 20.8x |
| strwalk | 13.4 | 13.0 | -3.0% | 0.1x | 0.1x |
| arrays | 1281.3 | 1249.6 | -2.5% | 13.7x | 13.4x |
| startup | 4.7 | 4.6 | -2.1% | 2.5x | 2.4x |
| fields | 1243.6 | 1223.7 | -1.6% | 20.6x | 20.2x |
| csv | 536.6 | 528.6 | -1.5% | 1.7x | 1.7x |
| alloc | 1286.5 | 1268.4 | -1.4% | 7.8x | 7.7x |
| fib | 1925.1 | 1901.9 | -1.2% | 22.7x | 22.4x |
| closures | 882.6 | 872.4 | -1.2% | 19.0x | 18.8x |
| calls | 1206.9 | 1194.7 | -1.0% | 7.6x | 7.6x |
| globals | 1944.3 | 1939.2 | -0.3% | 18.0x | 17.9x |
| sorting | 776.5 | 775.9 | -0.1% | 1.3x | 1.3x |
| options | 1499.5 | 1499.2 | -0.0% | 17.6x | 17.6x |
| nested | 1426.0 | 1430.2 | +0.3% | 10.6x | 10.6x |
| loops | 932.1 | 938.1 | +0.6% | 7.7x | 7.7x |
| funcs | 1060.4 | 1069.5 | +0.9% | 20.6x | 20.8x |
| strindex | 11.3 | 11.4 | +0.9% | 4.2x | 4.2x |
| strings | 783.5 | 794.1 | +1.4% | 2.1x | 2.1x |
| methods | 1904.1 | 1934.0 | +1.6% | 13.2x | 13.4x |
| dispatch | 1622.4 | 1690.1 | **+4.2%** | 17.3x | 18.1x |
| **geometric mean vs lua** | **8.628x** | **8.545x** | **-0.97%** | | |

**The two instruments agree on the MEAN and not on the rows**, which is the reading to keep:
`run.sh -n 5` over both orderings gave **8.783x → 8.697x (-0.98%)** against Lua, **6.609x → 6.544x
(-0.98%)** against `node --jitless` and **4.531x → 4.487x (-0.97%)** against python3 — the same
answer to two decimal places from a measurement whose individual rows were a quarter of them wrong.
A geometric mean over twenty-three programs averages drift out; one row does not.

**`dispatch` is the one real regression and it is code layout.** It executes 2.86% FEWER instructions,
its collector never runs at all on either binary, and it read +4.2% here and +5.4% on the other
instrument — the same effect as the `match`-arm ordering that was worth 3% on `funcs` in the
`native-args` work. The interpreter's hot loop is sensitive to where its arms land, and nothing in
this change touched them.

### What was deliberately NOT done, so nobody proposes it again without new evidence

**Folding the safe point into the CALL instructions**, so entering a chunk ticks with no dispatch at
all, was designed and refused. It would close the one hole this cut left — a body that is ONE
EXPRESSION carries no safe point, so `down(n) = n > 0 && down(n - 1)` can be neither collected nor
stopped however deep it goes — and it would put the guarantee somewhere `CLAUDE.md` already warns
about: **there are five ways into a chunk** (`CallFn`, `CallMethod`, `CallSpread`,
`CallMethodSpread` and `apply`), and a sixth grown later that forgot to tick would be a chunk
nothing could interrupt, with no test to fail.

**THE HOLE ITSELF IS CLOSED — the honest way, a `Tick` at the head of such a chunk, 2026-09-21** —
and the section at the foot of this page has what it cost. What is refused above is the *cheap* way
of closing it, and that refusal stands.

**A counter in the VM tested every N safe points** was the other half of the item's own wording and is
the weaker half: it leaves the instruction where it is and only makes the arm cheaper. `arith` says a
`Tick` costs about a third of an average instruction — 5.26% of its instructions gone for 3.6% of its
wall — which is dispatch and very little else.

