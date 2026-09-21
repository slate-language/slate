# A module's blocks are asked whether they declare anything — shortlist item 2, `de4e7c4`

Taken 2026-09-19 on this machine, both locks held, under `caffeinate`, box at 89.8% idle before and
97.7% after. **Both binaries were built in this session from the two ends of one merge**: `dev` is
**`c31e658`** — which already carries items 1, 4 and 8 — and `item 2` is that same tree with this
change and nothing else on it.

**THE NEIGHBOUR IS NAMED RATHER THAN WAITED OUT.** A `mimic` conformance run held one slate process at
about a quarter of one core throughout, on an eighteen-core box that stayed above 89% idle. It is in
both columns equally and the ratios against Lua, taken in the same passes, are what carries the
reading.

**The instruction counts are the evidence and they are exact.** A count is an increment where a time
is a measurement, and this item's whole claim is visible in one pair of rows:

| `globals.sl`, 6,000,000 turns | dev `c31e658` | item 2 |
|---|---|---|
| instructions | 126,000,020 | **114,000,020** |
| instructions per loop turn | 21 | **19** |
| `PushScope` | 6,000,000 | **0** |
| `PopScope` | 6,000,000 | **0** |
| allocator steps | 5,998,602 | **0** |
| collections | 4,285 → 4,288 | **0** |
| collector | 46,643 us | **0 us** |

**The twelve million instructions that went are exactly the six million pairs**, which is checkable
rather than asserted: 126,000,020 − 114,000,020 = 12,000,000, and no other kind moved by a single
execution. **A loop at the top of a file now allocates nothing**, so the benchmark that ran four
thousand collections for a body declaring no name runs none.

**`arith` is the control and did not move** — 190,000,026 both sides — its loop being inside a
function, where the question was already asked. `loops` and `nested` each lose 2,000 instructions and
609 allocator steps, which is their thousand-turn module-level **setup** loop and nothing they
measure.

| wall clock, best of 5 | dev `c31e658` | item 2 | change | dev/lua | item 2/lua |
|---|---|---|---|---|---|
| globals | 2215.7 | **1888.5** | **-14.8%** | 21.8x | **18.1x** |
| loops | 930.1 | 943.4 | *+1.4%* | 8.0x | 8.0x |
| nested | 1741.1 | 1756.9 | *+0.9%* | 13.4x | 13.7x |
| strindex | 11.3 | 11.3 | — | 4.6x | 4.8x |
| strwalk | 13.0 | 13.2 | — | 0.1x | 0.1x |

Those five are the only benchmarks with a loop at module level at all, and **`globals` is the only one
whose module-level loop does any work**; the other four put theirs in a function and keep a thousand
turns of setup outside it, which is why the counts move and the clocks do not.

**Over the whole set, best of 3, run ITEM FIRST so the order favours the baseline** — a box that
quietens across twenty minutes buys the second pass a few percent, and here the second pass is `dev`:

| | against lua | against node --jitless | against python3 |
|---|---|---|---|
| dev `c31e658` | 9.5x | 7.8x | 5.3x |
| item 2 | **9.5x** | **7.7x** | **5.3x** |

**THE GEOMETRIC MEANS DO NOT MOVE AND THAT IS THE HONEST READING OF THIS ITEM, not a disappointment.**
The shortlist said *`globals` only*, and it was right: one benchmark of twenty-two going 21.8x to
17.6x (its whole-set figures) moves a mean of twenty-two rows by about a tenth of one, which rounds
away. **What the item buys is not on this page's mean at all** — it is that every top-level script,
which is what most slate programs are until they grow a function, stops paying a heap object and a
collection schedule for every turn of every loop. `bench/` measures twenty-one programs written to
put their work in functions; the ordinary script is the case with no benchmark.

