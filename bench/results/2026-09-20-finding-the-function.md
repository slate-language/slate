# 2026-09-20 — FINDING THE FUNCTION, AND THE HEAD IT ENTERS — shortlist items 5 and 6

They are one finding — 7 above — and they landed together because they are the two halves of what an
ordinary call costs that is not the call itself.

**Item 5 — finding the function.** `add3(i, 1, 2)` compiled to a `LoadName`: the spelling hashed and
the scope chain walked, four million times, for an answer that cannot change. A definition written at
a file's own top level is resolved while compiling to a cell of a table the hoisted definition fills,
and the read is `LoadDef`, one array index.

**The rule is one a reader can state, and it is the whole of `defs.sysl`**: *a definition at the
file's own top level, whose spelling nothing else in the file binds or writes*. A parameter, a local,
a caught name, a pattern's names, an import or a nested definition of that spelling puts every read
of it back to the lookup it had.

**AND THE PUTTING BACK IS A FIXUP RATHER THAN A PRE-PASS, WHICH IS THE ONE THING HERE WORTH
REMEMBERING.** Definitions are hoisted, so the body that calls `add3` is compiled before the compiler
has met the local three lines further down that turns out to mean the same spelling — knowing in
advance would take a second walk of the whole file. So a read is emitted resolved where it stands and
written down, and a name something later binds has its reads rewritten before the file is finished.
Two things make that cheap to keep true: `put` is the one place every binding INSTRUCTION passes
through, so an import, a class, a `type` and an `external` say it without a list of them existing
anywhere; and the three bindings with no instruction at all — a parameter, a cell, a pattern's names
— say it where they are claimed.

**Item 6 — the head.** Every function's head opened with one `JumpIfGiven` per parameter, to bind an
absence where no argument arrived. On `add3(a, b, c)` that is three branches on every call, on a
function with no default anywhere in it, whose only work for a call that gave everything is to jump
over the binding. **The frame says it instead**: `lay_frame` pads a parameter cell nobody filled with
exactly that absence, so a required parameter and an optional `b?` are guarded by nothing. An
evaluated default is guarded exactly as before — its expression may not run where the argument
arrived — and a chunk that keeps its scope is untouched, a parameter nobody gave not being bound
there at all. `StoreAbsentSlot` had no emitter left and is gone.

**It is not the sentinel `code.sysl` refuses.** `undefined` is an ordinary slate value meaning what a
missing argument means, so a `LoadSlot` of one needs no check in front of it and reads exactly what
the guarded head used to write.

### The instruction counts, which are the evidence

Exact, taken with `--features profile` on the two ends of one commit.

| benchmark | dev `ff9709e` | call-targets | change |
|---|---|---|---|
| `funcs` | 112,000,028 | **100,000,028** | **-10.7%** |
| `calls` | 62,000,047 | **56,000,046** | **-9.7%** |
| `fib` | 153,977,942 | **142,572,169** | **-7.4%** |
| `closures` | 88,000,034 | **84,000,034** | **-4.5%** |
| `globals` | 114,000,020 | 114,000,020 | **0.0%** |

Per instruction kind, and the two lines tell the two items apart:

| | `funcs` | `fib` | `calls` | `closures` | `globals` |
|---|---|---|---|---|---|
| `JumpIfGiven` | 12,000,000 → **0** | 11,405,773 → **0** | 6,000,001 → **0** | 4,000,000 → **0** | 0 → 0 |
| `LoadName` | 4,000,002 → **1** | 11,405,774 → **1** | 4,000,004 → 4,000,003 | 4,000,002 → 4,000,001 | 24,000,003 → 24,000,003 |

**`globals` DOES NOT MOVE, AND THE SHORTLIST SAID IT WOULD** — item 5 was written down as reaching
"all of `globals`'s 14.8% `LoadName`", and that was wrong. `globals.sl` reads and writes two
module-level `var`s six million times; a `var` is not a definition, and a name a program assigns to
cannot be resolved to a value at all. Reaching those would mean giving every module-level BINDING a
numbered cell and a `StoreDef` beside the scope it still has to keep for an import to read — a
different change, and not this one. What item 5 reaches is a call of a module-level FUNCTION, which
is `funcs` and `fib`.

**`calls` and `closures` keep their `LoadName`s for the same kind of reason**: `calls` looks a method
up and `closures` reads a captured local, and neither is a definition. Their whole improvement is
item 6.

### The timings

Both binaries built in this session from the two ends of one branch, so the control is dev
**`ff9709e`** and the branch is that tree with this change and nothing else. `bench/run.sh -n 5` per
binary, box 92.9% idle at the start, no build, gate or other timing run going. **Every figure is the
MEAN OF BOTH ORDERINGS** (control→branch and branch→control). Milliseconds of process wall time.

| | dev `ff9709e` | call-targets | change | dev/lua | call-targets/lua |
|---|---|---|---|---|---|
| options | 1632.3 | **1403.9** | **-14.0%** | 18.8x | 16.4x |
| fib | 1896.8 | **1655.5** | **-12.7%** | 23.6x | 20.1x |
| strings | 974.6 | **860.6** | **-11.7%** | 2.4x | 2.3x |
| funcs | 1050.3 | **956.9** | **-8.9%** | 22.2x | 18.6x |
| dispatch | 1594.5 | **1473.9** | **-7.6%** | 17.9x | 16.6x |
| strindex | 12.5 | 11.8 | -6.0% | 4.8x | 4.3x |
| strwalk | 13.8 | 13.2 | -4.4% | 0.1x | 0.1x |
| loops | 996.8 | 956.4 | -4.1% | 7.7x | 8.0x |
| reals | 1295.4 | 1268.3 | -2.1% | 22.2x | 21.7x |
| arith | 1286.9 | 1261.9 | -1.9% | 26.5x | 25.8x |
| fields | 1271.9 | 1254.6 | -1.4% | 20.1x | 20.4x |
| sorting | 780.3 | 775.6 | -0.6% | 1.3x | 1.3x |
| globals | 1949.3 | 1947.1 | -0.1% | 18.7x | 19.3x |
| closures | 862.3 | 863.8 | +0.2% | 17.9x | 18.5x |
| nested | 1414.8 | 1418.5 | +0.3% | 10.6x | 10.7x |
| methods | 1890.1 | 1898.0 | +0.4% | 13.1x | 13.2x |
| alloc | 1279.6 | 1285.8 | +0.5% | 7.9x | 7.8x |
| calls | 1160.4 | 1168.0 | +0.7% | 7.5x | 7.6x |
| branches | 1381.0 | 1397.4 | +1.2% | 13.2x | 13.2x |
| mapset | 606.6 | 619.2 | +2.1% | 33.1x | 33.3x |
| csv | 514.4 | 526.7 | +2.4% | 1.7x | 1.7x |
| arrays | 1219.2 | 1266.6 | +3.9% | 13.1x | 13.6x |
| **geometric mean vs lua** | **8.8x** | **8.5x** | | | |
| geometric mean vs node --jitless | 6.7x | 6.5x | | | |
| geometric mean vs python3 | 4.6x | 4.45x | | | |

**`funcs` AND `fib` ARE THE MEASUREMENT AND THE REST IS THE BOX**, which is what the instruction
counts above are for: those two are the only benchmarks whose instruction count moved by more than
7%, and they are the two that read -8.9% and -12.7%. Both read the same way in both orderings —
`funcs` 940.7 and 973.0 against 1050.0 and 1050.5, `fib` 1606.7 and 1704.2 against 1891.1 and 1902.5
— which is what a real change looks like.

**`options`, `strings`, `dispatch` and `loops` read large and should not be believed at that size.**
The final control pass was slow for everything: `options` read 1495.2 in the first pass and 1769.3 in
the last, and its Lua, `node --jitless` and `python3` columns moved +4%, +14% and +13% between the
same two passes. The mean of both orderings is what the table carries, and it inherits that drift.
`arrays`'s +3.9% is the same drift wearing the other sign — its instruction count is untouched by
either item.

### The witness a benchmark cannot give

Both items are invisible to every question about what a program ANSWERS, so `tests_slots.sysl` asks
the emitted code instead: `given_guards` counts the guards in a named chunk and `resolved_reads`
counts the reads that were resolved. A three-parameter function with no default has a head of zero
instructions, a `b?` adds none, an evaluated default adds exactly one, and a chunk that keeps its
scope still asks the scope about every parameter. A call of the file's own `add3` is one `LoadDef`
and no `LoadName`; **the same call with a local of that spelling written three lines BELOW the
function that makes it is one `LoadName` and no `LoadDef`**, which is the fixup, and without it that
program answers from a table cell while the rest of the file means something else by the name.

`tests/lang/defs.sl` and `tests/lang/arity.sl` are the behaviour, on both back ends: a definition
reached from a function above it, mutual recursion, a local and a parameter and a pattern's name each
shadowing one, a definition inside a function, a definition read through a closure and passed as a
value — and, for item 6, a three-parameter function called with two arguments through a callback,
read as `null`, as `??`'s left side and as a test.

