# A constructor call stopped copying its arguments — the other half of item 11, 2026-09-20

**A CONSTRUCTION IS AN ORDINARY CALL WITH THE CALLEE LOOKED UP FIRST.** `Counter(3)` is an object
carrying a `new`, and that hook is handed the arguments exactly as they were written — a `new` takes
no receiver, the object it is about to make not existing yet — so they are already standing where its
slots want them and the class comes out from under them with the one shift a closure needs.
`in_place_call` asks `hook_of(callee, "new")`, which is the same lookup `invoke` was already making,
and then asks the chunk it answers the SAME four questions it asks a closure's: `slotted`, not
variadic, not `async`, not a generator, under the depth limit. A named construction, a spread, a
variadic `new` and an object with no callable `new` all stay on the buffered path — the last of them
so that the refusal keeps the sentence it has always had.

Best of 5, under `caffeinate`, holding both locks, box at 93.5% idle before and 93.6% after. Both
binaries were built in this session from the two ends of one merge, so `dev` is **`92f81c7`** and
`ctor-calls` is that tree with this change and nothing else on it. Milliseconds of process wall time.

|  | dev `92f81c7` | ctor-calls | change | dev/lua | ctor-calls/lua |
|---|---|---|---|---|---|
| calls | 1289.2 | **1170.9** | **-9.2%** | 8.4x | 7.5x |
| strings | 826.6 | 810.6 | -1.9% | 2.2x | 2.2x |
| reals | 1287.9 | 1269.4 | -1.4% | 22.1x | 21.4x |
| arrays | 1249.2 | 1233.0 | -1.3% | 13.4x | 13.4x |
| loops | 952.6 | 948.9 | -0.4% | 8.0x | 7.8x |
| methods | 1956.1 | 1950.7 | -0.3% | 13.3x | 13.3x |
| options | 1506.7 | 1506.4 | 0.0% | 17.8x | 17.8x |
| strindex | 11.9 | 11.9 | 0.0% | 4.8x | 4.8x |
| strwalk | 13.1 | 13.1 | 0.0% | 0.1x | 0.1x |
| csv | 593.3 | 593.6 | *+0.1%* | 2.0x | 1.9x |
| arith | 1263.3 | 1265.5 | *+0.2%* | 26.4x | 26.3x |
| sorting | 767.2 | 769.5 | *+0.3%* | 1.3x | 1.3x |
| alloc | 1237.7 | 1242.7 | *+0.4%* | 7.8x | 7.7x |
| closures | 877.0 | 880.5 | *+0.4%* | 18.2x | 18.4x |
| fields | 1204.8 | 1211.7 | *+0.6%* | 19.0x | 19.4x |
| globals | 1922.7 | 1944.4 | *+1.1%* | 19.2x | 19.3x |
| nested | 1454.1 | 1470.1 | *+1.1%* | 11.0x | 10.9x |
| mapset | 813.5 | 824.4 | *+1.3%* | 47.2x | 48.1x |
| fib | 1889.6 | 1916.8 | *+1.4%* | 23.4x | 23.9x |
| funcs | 1040.0 | 1063.5 | *+2.3%* | 21.5x | 21.1x |
| dispatch | 1592.5 | 1646.9 | *+3.4%* | 18.3x | 18.6x |
| **geomean** | | | | **8.8x** | **8.8x** |

**THE GEOMETRIC MEANS DID NOT MOVE AND WERE NEVER GOING TO**: 8.8x against Lua, 7.1x against
`node --jitless` and 4.8x against `python3`, before and after. One benchmark of twenty-two moving 9%
is worth about four tenths of one percent on the mean, which is under what this page can read — and
that is the reading to expect from any item whose *reach* column names a single program.

**`calls` IS THE HONEST NANOSECOND FIGURE HERE, THE WAY `fib` WAS FOR THE OTHER HALF.** Its loop runs
2,000,000 turns and makes exactly one construction a turn, so 118.3 ms is **59 ns off every
construction of one argument** — against the 69 ns the same measurement gave for an ordinary
positional call of one argument. Two figures for one malloc, one free and two copies, taken a day
apart on two benchmarks.

**EVERY ROW THAT ROSE HAS NO MECHANISM, AND LUA'S OWN NUMBERS SAY SO.** Nothing but a construction can
reach this change: the `Fn` arm of `in_place_call` is matched before the new `Object` one and is
untouched, and a call that is not a construction never asks `hook_of` at all. The two largest risers
are `dispatch` (+3.4%) and `funcs` (+2.3%) — and Lua, timed in the same two passes, moved +2.2% on
`dispatch` and +4.1% on `funcs`, with `csv` +3.4% and `loops` +2.8% beside them. The box drifted
upward under the second pass exactly as it did for item 11's first half, and the ratio columns are
what carries the reading.

**THE WITNESS IS `Vm.args_buffered` AND IT IS WHAT SAYS THIS IS THE MECHANISM RATHER THAN THE WEATHER.**
`tests_slots.sysl` asserts that ten thousand positional constructions charge it **nothing**, with a
named construction, a spread construction and a variadic `new` each charging once per construction
beside them — and that a construction which has run out of call depth goes back to the buffered path
and is refused in the sentence every other call is refused with.

