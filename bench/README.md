# The benchmarks, and what the first profile says

Twenty-three programs, each written four times -- in slate, in Lua, in JavaScript and in Python -- and
a profiler for the interpreter that runs them. **Nothing here makes slate faster.** It exists so that
the next thing that does can be chosen from a number rather than from an opinion, and so that the
claim afterwards can be checked.

**Lua is the goal the user set: plain PUC-Rio Lua, no JIT.** `node --jitless` and `python3` are
context rather than targets -- the first is V8's Ignition bytecode interpreter with every compiler
tier switched off, which is the nearest thing to slate's own design that anybody ships, and the
second is a stack machine with a much larger object model, which is the other direction. `node` with
its compilers on is reported in its own column and is **not** a yardstick; it is there because
slate's own JavaScript back end runs under exactly that.

## Running them

```
bench/check.sh ./slate
bench/run.sh ./slate
bench/run.sh -n 9 --tsv ./slate arith fib mapset
```

`check.sh` runs all four implementations of all twenty-two and diffs every answer against
`expected.txt`. **A twin that has drifted from its slate program shows up there** -- a loop bound
edited on one side, a 1-based index off by one, an integer that stopped being exact in a double --
rather than as a benchmark that quietly measures something else.

`run.sh` reports the **best of N** wall times (N = 5; `-n` changes it), the ratio against each
yardstick, and the geometric mean of those ratios. `--tsv` writes the same thing tab-separated.

- **The clock is `CLOCK_MONOTONIC` through `perl -MTime::HiRes`** (`timeit.pl`). `/usr/bin/time -p`
  reports hundredths of a second, which is all of a start-up measurement; `gdate` is GNU coreutils
  and is not on this machine. Perl is on every macOS.
- **The figure is the whole process, and nothing is subtracted** -- fork, exec, start-up, the work,
  the exit. `startup` is the same measurement of a program that does nothing, so a reader can see how
  much of a short run was never the program; it is reported beside the rest and never taken off it.
- **Best of N rather than the mean**, because a slow run is always something else on the machine.

**A RESULT IS ONLY COMPARABLE TO ANOTHER TAKEN ON THE SAME MACHINE, IN THE SAME STATE.** Before
running: `pgrep -x java` must be empty, no `sysl test` or `slate test` may be running, and
`top -l 2 -n 0 -s 1 | grep "CPU usage" | tail -1` must say better than 85% idle. **Run under
`caffeinate -dimsu`** -- this box sleeps for about fourteen seconds a minute otherwise, which lands
wherever it lands and is indistinguishable from a benchmark being slow.

## What each one stresses

| file | what it is for |
|---|---|
| `startup` | a program that does nothing, in each of the four |
| `arith` | a tight integer loop: two locals read and written per turn, nothing else |
| `reals` | the same loop over reals, which is the other number type slate carries |
| `globals` | `arith`'s loop at MODULE level, where the names cannot be slots |
| `funcs` | a call to a plain function of fixed arity, with everything else taken out |
| `fib` | recursion, which is the call benchmark that also measures depth |
| `calls` | a method call that allocates, once per turn |
| `methods` | method dispatch on a class instance with nothing allocated |
| `closures` | a small closure reading one captured name |
| `nested` | a loop inside a chunk that keeps a scope for one captured name |
| `loops` | a `for` over an array with a destructuring head |
| `options` | an options object taken apart with defaults, half the calls leaving a name out |
| `fields` | reading and writing a field of a plain object |
| `alloc` | three million short-lived two-field objects |
| `arrays` | an array built by pushing, then read by index, then walked |
| `mapset` | a `Map` and a `Set` written to and read back |
| `dispatch` | `match` on a string, against a chain of comparisons and a `switch` |
| `strings` | a string built a piece at a time by concatenation |
| `strindex` | reading a 16,000-character string one character at a time BY INDEX |
| `strwalk` | the same walk over text that is NOT one byte a character, where a position cannot be arithmetic |
| `sorting` | `sorted` over 20,000 numbers, two hundred times |
| `csv` | the realistic mix: generate a comma-separated text, split it, convert and add |
| `branches` | ordinary decision-making code: a bare `if`, an `if`/`elif`/`elif`/`else` chain with a nested `if`, an early `continue`, a five-armed `match`, an `if` used as an expression, and a rare `try`/`catch` |

**Each is sized so that Lua takes roughly a fifth of a second**, which is long enough to measure and
short enough that slate finishes in a couple. **`strindex` and `strwalk` are deliberately outside
that band, and `strwalk` is the one benchmark here Lua is not a yardstick for** -- Lua has no
character indexing at all, so its own twin is quadratic in the same way slate's used to be, which the
twin's header says. `strindex` is the ASCII case: sized
for Lua it would run for hours under slate, and sized for slate the other three finish before their
own start-up is over. That gap is the measurement.

**Every twin says in its header where it differs from the slate program** -- Lua has no set, no
destructuring and no `match`; JavaScript has one number type and sorts by string unless told
otherwise; Python's integers are arbitrary precision and its `+=` on a string may be linear where
everybody else's is quadratic. Where a language cannot do the same thing, the twin does the nearest
honest thing and says so rather than the slate program being bent to match.

## Current measured position

Every individual measurement -- the original baseline and every landed shortlist item -- is
in `bench/results/`, one file per write-up, newest first in the index below.

### The new measured position: `bench/run.sh -n 5` on the default (`-O2`) build

| program | slate (ms) | vs Lua | vs node --jitless | vs CPython |
|---|---|---|---|---|
| startup | 4.6 | 2.57 | 0.31 | 0.34 |
| arith | 414.6 | 8.68 | 3.69 | 1.35 |
| reals | 488.4 | 8.25 | 3.68 | 1.97 |
| globals | 1256.8 | 12.25 | 16.98 | **3.36** |
| funcs | 333.0 | 6.87 | 3.55 | 2.20 |
| fib | 710.9 | 8.93 | 4.26 | **3.53** |
| calls | 679.6 | 4.37 | 8.86 | **4.99** |
| methods | 765.9 | 5.56 | 4.79 | **4.09** |
| closures | 312.1 | 6.76 | 3.95 | 2.29 |
| nested | 632.5 | 4.84 | 1.40 | 3.25 |
| loops | 380.9 | 3.20 | 0.75 | 2.54 |
| options | 705.7 | 8.56 | 6.53 | 3.19 |
| fields | 574.2 | 9.36 | 7.13 | 2.74 |
| alloc | 704.9 | 4.36 | 8.61 | 3.18 |
| arrays | 522.3 | 5.54 | 3.30 | 2.67 |
| mapset | 304.0 | 17.99 | 3.56 | 2.92 |
| dispatch | 621.4 | 6.99 | 4.18 | 2.91 |
| strings | 745.4 | 2.05 | 30.59 | 1.20 |
| strindex | 9.4 | 3.95 | 0.55 | 0.69 |
| strwalk | 10.8 | 0.07 | 0.60 | 0.77 |
| sorting | 527.7 | 0.91 | 0.66 | 1.40 |
| csv | 400.4 | 1.32 | 3.03 | **4.75** |
| branches | 447.9 | 4.36 | 1.45 | 1.15 |
| **geomean** | | **4.34x** | **3.35x** | **2.29x** |

**Down from 7.2x Lua / 5.5x node --jitless / 3.8x CPython**, the numbers this page's superinstructions
write-up recorded for this same dev tip (`ebf08c5`) built with sysl 0.0.121 at `-O1` — the default at
the time. **The five worst against CPython** (highest `slate/python` ratio): `calls` 4.99x, `csv`
4.75x, `methods` 4.09x, `fib` 3.53x, `globals` 3.36x — all builtin- or call-heavy, the shape the
`sysl.buf` finding above says is still 46.5% of the wall clock even after the borrowed-read fix,
because a positional call's `InPlace` path and a method dispatch both still read a `Chunk`/entry
through `Buf.at` on the hot path.

**Nothing in `dev/` changed for either of these tables.** The whole of this section is `package.hocon`
plus a newer compiler.

## The ranked shortlist for 0.0.58 and after

Every line points at a number above. **Nine have landed since** — 1, 2, 3, 4, 5, 6, 7, 8 and 11, each
struck through with what it measured; the ranking of what is left is unchanged.

**THE RANKING BELOW HAS BEEN SUPERSEDED TWICE, AND THE SECOND SAMPLED PROFILE IS THE LIVE ONE — read
[the second sampled profile (dev `76128bf`)](results/2026-09-21-sampled-profile-2.md) before proposing
any of it.** The table here was read off instruction COUNTS, and the sampler says the time is not
where the counts are; the first sampled profile
([dev `c26567e`](results/2026-09-21-sampled-profile.md)) then had its own headline closed by sysl
0.0.122, so its ranking is history as well. **The current ranking, with ceilings, is the table at the
end of the second profile.** In one line each:

| | candidate | weighted share | ceiling |
|---|---|---|---|
| 1 | inline `Buf.push` the way 0.0.122 inlined `Buf.at` (**sysl's `buf.sysl`, not slate's**) | 18.5% | 10–15% |
| 2 | a register machine instead of a stack machine | 15.5% | 10–15% |
| 3 | ~~stop re-asking `current()` in the hot helpers (`_tlv_get_addr`)~~ — **DONE 2026-09-21, [`vm-param`](results/2026-09-21-vm-param.md): -4.06% geometric mean**, `dispatch` -12.3%, `arith` -11.8%, `fib` -8.0%; `_tlv_get_addr` on `fib` 4.4% → **0.4%** | was 4.3% | 3–4%, and it took 4.1% |
| 4 | inline caches for a field or a method | 6.5% | 3–4% |
| 5 | module-level `var` cells, `StoreDef` | 3.7%, ~30% of `globals` | 0.5% of the mean |
| 6 | `match_walk` — `for` heads, `match` arms, destructuring — **new** | 3.8% | 2–3% |
| 7 | what `calls` and `csv` allocate per call — **an open question, not yet an item** | 8.9% | unknown |
| 8 | a narrower `Value`, or NaN-boxing | 15.5% | 5–8% |
| — | ~~borrowed reads / `Buf.at` retaining~~ | was 46.5%, now **0.6%** | **DONE in sysl 0.0.122** |
| — | ~~the second bounds check inside `Buf.at`~~ | 2 instructions of a 20-instruction dispatch head | **STRUCK, under 1% of wall** |

**AND ONE THAT WAS ON NO LINE AT ALL TURNED OUT TO BE THE LARGEST OF THEM: one instruction per
operator** (2026-09-21, **-5.69%** of the geometric mean, `arith` -12.7%, twenty-two of twenty-three
programs faster; landed as dev `c26567e`). It is not here because the profile above counts *instructions* and this one changed
none — `BinaryOp` was 15.2% of every instruction executed and each of them re-asked, three times, an
operator the compiler had already picked. **The lesson generalises, and is the reason to say so
here: a shortlist read off an instruction count cannot see what an instruction DOES.** The remainder
of item 11 — `methods_of` looking a method up by name at every call — reads as the same shape and is
**not**: both sampled profiles put it under 0.5% of wall, visible on `mapset` alone.

| # | change | reach | kind |
|---|---|---|---|
| 1 | ~~**Stop emitting `PushNull`/`Discard` for a statement whose value nothing reads**~~ — **DONE, `fa327b6`**: 20.6% of all instructions gone, `arith` -24.0%, geometric mean against Lua 17.6x -> **16.4x**. **Its remainder — `if`, `match` and `try` written as STATEMENTS — landed 2026-09-20 and `bench/` cannot see it**: nineteen of the twenty-two programs here hold no conditional at all, so the whole set moved 0.005% while a loop written around an unread `if` moved -12.4% | measured above | INCREMENTAL, and the set is what is missing |
| 2 | ~~**Fix the module-level loop's per-turn scope**~~ — **DONE, `de4e7c4`**: it WAS a defect. A module has no cells, and the `scoped_*` questions read `!e.cells` as "do not ask" rather than as "this chunk binds by name"; a module's blocks are asked `block_declares` now, guarded by the one binding form an expression can hide (`Emit.tests_bind`). `globals` 6,000,000 `PushScope`/`PopScope` pairs, 5,998,602 allocator steps and 4,288 collections all to **zero**, -14.8% wall, 21.8x -> **18.1x** Lua. **The three geometric means do not move** — one benchmark of twenty-two — and the win is in every top-level script instead | measured above | INCREMENTAL, and it was a defect |
| 3 | ~~**Make `Tick` cheaper or rarer**~~ — **DONE, 2026-09-20**: a loop body's statements give their safe points up to ONE at the top of the loop, which is the only place a statement runs more than once for having been written once; everything outside a loop keeps its own, because `heap_limit` is read at a safe point and nowhere else. **4.45% of all instructions gone and `Tick` itself down 46.5%**, geometric mean against Lua **8.63x -> 8.55x (-0.97%)**, confirmed to two decimals on two instruments. `branches` -5.2%, `mapset` -4.7%, `arith` -3.6%; `dispatch` +4.2% on FEWER instructions and no collector at all, which is code layout. A `Tick` costs about a third of an average instruction. **The hole it left — a chunk whose body is one EXPRESSION carried no safe point at all, so a recursion through one could be neither collected nor interrupted — was closed 2026-09-21**, for +2.07% of all instructions and **+0.49%** of the geometric mean; [its write-up](results/2026-09-21-expression-bodied-chunk-safepoint.md) has the numbers | measured above | INCREMENTAL |
| 4 | ~~**Cache a string's character count on the `StrObj`, and index from a cached cursor**~~ — **DONE, `7478d4b`**: the count is CARRIED rather than cached, so `.length` is O(1) always; `strindex` 980x -> **5.5x** Lua (190x faster), the new `strwalk` 30.3x -> **0.1x** (322x faster), geometric mean against Lua over the original twenty **17.4x -> 13.4x** by this item alone | measured above | INCREMENTAL |
| 5 | ~~**Resolve a module-level definition's call target at compile time** so `add3(...)` is not a `LoadName`~~ — **DONE, 2026-09-20, with 6**: a definition at a file's own top level whose spelling nothing else in the file binds or writes is a `LoadDef` into a table, and a read of a spelling something turns out to bind is put back before the file is finished. `funcs` 4,000,002 `LoadName` → **1**, `fib` 11,405,774 → **1**. **The reach claimed here for `globals` was WRONG** — its names are module-level `var`s, which are assigned and so cannot be resolved to a value at all; it moved 0.0% | measured above | INCREMENTAL |
| 6 | ~~**Emit `JumpIfGiven` only for a parameter that can be absent**~~ — **DONE, 2026-09-20, with 5**: the frame is laid with an absence in every parameter cell a call did not fill, so a required parameter and a `b?` are guarded by nothing and an ordinary function has no head at all. **`JumpIfGiven` to ZERO on every benchmark that had one** — `funcs` 12,000,000, `fib` 11,405,773, `calls` 6,000,001, `closures` 4,000,000. Together with 5: `funcs` **-10.7%** of its instructions and **-8.9%** of its wall, `fib` **-7.4%** and **-12.7%**, geometric mean against Lua 8.8x → **8.5x** | measured above | INCREMENTAL |
| 7 | ~~**Raise `Headroom` with the payload, or schedule payload separately from cells**~~ — **DONE, 2026-09-19**: payload is a schedule of its own, with a floor of its own, because a collection costs the OBJECT GRAPH and not the bytes. `strings` 123,925 collections -> **45,627** and 233 ms of collector -> 92 ms, **-12.8%** wall; `alloc` 18,292 -> 3,685. Peak RSS 14.3 MB -> 30.9 MB on `strings` and unchanged on a buffer-dropping program; a 4 MiB floor was measured (-16%, 83 MB) and refused. **The three geometric means do not move** — one benchmark of twenty-two | measured above | INCREMENTAL |
| 8 | ~~**Make `Map`/`Set` cheaper for scalar keys**~~ — **DONE, `06b2b6c`**: the hook lookup was two mallocs a call and is gone; a table under nine entries has no index. `mapset` 53.9x -> **49.1x**, `alloc` -6.8%, `fields` -2.4% | measured above | INCREMENTAL |
| 9 | **A register machine instead of a stack machine** -- `LoadSlot` is 18.0% and `PushInt` 8.6%, and most of both exist only to feed the next instruction. **Sampled: 15.5% of wall**, nearly all of it `Buf.push<Value>` | 26.6% of all instructions, and it would take most of 1, 3 and 5 with it | **STRUCTURAL -- not piecemeal** |
| 10 | **A narrower `Value`, or NaN-boxing**. **Sampled: 5–8%**, down from the first profile's 10–15% now that the read side is inlined | every instruction; nothing here measures it directly | **STRUCTURAL -- not piecemeal** |
| 11 | ~~**Make the CALL PATH cheaper** -- the argument `Buf` is a malloc per call, `Buf.at` retains and releases it on every read~~ — **DONE in two halves**. `call-args` + `ctor-calls`: an ordinary positional call allocates nothing (69 ns off every one of `fib`'s eleven million) and neither does a positional construction (59 ns off every one of `calls`'s two million). `native-args`, 2026-09-20: a BUILTIN reads its arguments through a window onto the stack they are standing on, so the malloc, the free, the copies and the per-argument hold are gone from the call slate makes most of — `mapset` **-25.6%** (47.4x -> **34.1x** Lua), `csv` **-13.5%**, geometric mean against Lua 8.9x -> **8.65x**, and twenty of the twenty-two read zero. **`methods_of` looking a method up by name every time is what is LEFT of this item** | measured above | INCREMENTAL, and both halves have landed |

**THE RANKING BELOW ITEM 1 IS UNCHANGED, AND THE PROFILE THAT WOULD HAVE CHANGED IT DID NOT.** Item
1 took away instructions and moved none, so every other line's absolute count is exactly what it
was and only its SHARE rose — `Tick` from 7.1% of all instructions to 9.0%, `LoadSlot` from 18.0% to
22.6%, `JumpIfGiven` from 2.5% to 3.1%, `LoadName` from 2.7% to 3.3%. Nothing overtook anything, and
items 2 and 4 are still the two cheapest large wins on the page.

**1 through 8 can ship one at a time**, each with a benchmark that says whether it worked. **9 and 10
must not be done piecemeal**: a register instruction set changes every arm of `run_frames`, both
back ends' agreement about what a chunk is, and the slot work that `CLAUDE.md` documents at length;
the value representation reaches the collector, the tables, both back ends and every native. Neither
is a thing to start because a benchmark looked bad.

**The honest summary of the gap**: slate is 17.4x off plain Lua on the geometric mean, and about a
third of that is instructions that compute nothing (findings 2 and 7), a third is the per-instruction
cost of a stack machine over a register machine (finding 9), and a third is that slate's builtins and
containers are doing genuinely more work than Lua's (findings 4 and 5). The first third is ordinary
engineering and can be had one release at a time.


## Write-ups

| date | write-up | headline |
|---|---|---|
| 2026-09-21 | [2026-09-21 — THE VM IS HANDED DOWN INSTEAD OF BEING ASKED FOR AGAIN — shortlist item 3](results/2026-09-21-vm-param.md) | shortlist item 3: -4.06% geometric mean, `_tlv_get_addr` on `fib` 4.4% → 0.4% |
| 2026-09-21 | [A second sampled profile, after 0.0.122 and the superinstructions (dev `76128bf`)](results/2026-09-21-sampled-profile-2.md) | **the live ranking**: `Buf.at` 32.4% → 0.6% (closed), `Buf.push<Value>` now 15.3%, `run_frames` 21.9%, `current()` through `_tlv_get_addr` 4.3% |
| 2026-09-21 | [2026-09-21 — sysl 0.0.122: the borrowed-read fix, and `-O2` becomes the default](results/2026-09-21-sysl-0-0-122.md) | sysl 0.0.122 borrowed-read fix + -O2 default: -35.5% then -6.52%; new position 4.34x/3.35x/2.29x |
| 2026-09-21 | [2026-09-21 — SUPERINSTRUCTIONS: TWO INSTRUCTIONS RUN AS ONE, AND THE LARGEST WIN ON THIS PAGE](results/2026-09-21-superinstructions.md) | superinstructions: -9.17% geometric mean, the largest single win on the page |
| 2026-09-21 | [2026-09-21 — cheaper frames: the chunk is read once per call and never on a return (`chunk-per-call`)](results/2026-09-21-chunk-per-call.md) | cheaper frames, chunk read once per call: -3.02% geometric mean |
| 2026-09-21 | [2026-09-21 — `-O2` against `-O1` (dev `4820c05`)](results/2026-09-21-o2-vs-o1.md) | -O2 vs -O1: -2.3% geometric mean, adopted as the default |
| 2026-09-21 | [What the sampled profile shows (dev `c26567e`)](results/2026-09-21-sampled-profile.md) | sampled profile (dev c26567e): Buf.at<Value> 14.3%, run_frames 12.6%, Buf.at<Ins> 12.4% |
| 2026-09-21 | [2026-09-21 — ONE INSTRUCTION PER OPERATOR: THE LARGEST SINGLE WIN ON THIS PAGE](results/2026-09-21-per-op-instructions.md) | one instruction per operator: -5.69% geomean, arith -12.7%, 22/23 programs faster |
| 2026-09-21 | [2026-09-21 — AN EXPRESSION-BODIED CHUNK GAINED A SAFE POINT, AND WHAT THE GUARANTEE COSTS](results/2026-09-21-expression-bodied-chunk-safepoint.md) | expression-bodied chunk gains a safe point: strings -38%, strwalk -14% on instruction counts |
| 2026-09-21 | [2026-09-21 — AN INTEGER STOPPED WRAPPING, AND WHAT THE OVERFLOW CHECK COSTS](results/2026-09-21-integer-overflow-check.md) | checked integer arithmetic costs ~2.4% geomean, arith -5.6%, fib -3.0% |
| 2026-09-21 | [2026-09-21 — `/` ANSWERS A REAL AND `\` IS THE INTEGER DIVISION: TIMED NEUTRAL](results/2026-09-21-div-real-vs-integer-division.md) | `/` real division, `\` integer division: timed neutral |
| 2026-09-20 | [2026-09-20 — A LOOP BODY GAVE UP ITS `Tick`s — shortlist item 3](results/2026-09-20-loop-body-ticks.md) | shortlist item 3: -4.45% of all instructions, Tick down 46.5%, geomean 8.63x -> 8.55x Lua |
| 2026-09-20 | [2026-09-20 — FINDING THE FUNCTION, AND THE HEAD IT ENTERS — shortlist items 5 and 6](results/2026-09-20-finding-the-function.md) | shortlist items 5+6: funcs -10.7% instructions, calls -9.7%, geomean 8.8x -> 8.5x Lua |
| 2026-09-20 | [2026-09-20 — A BUILTIN STOPPED COPYING ITS ARGUMENTS — the other half of shortlist item 11](results/2026-09-20-native-args.md) | builtin calls stop copying arguments: mapset -25.6%, csv -13.5%, geomean 8.9x -> 8.65x Lua |
| 2026-09-20 | [2026-09-20 — CUTTING `run_frames.sysl` IN TWO IS TIMED NEUTRAL](results/2026-09-20-run-frames-split.md) | run_frames.sysl cut in two: timed neutral |
| 2026-09-20 | [A constructor call stopped copying its arguments — the other half of item 11, 2026-09-20](results/2026-09-20-ctor-calls.md) | shortlist item 11 (constructor calls): calls -9.2%, 59ns off every construction |
| 2026-09-20 | [`branches` — the missing benchmark that makes a decision, 2026-09-20](results/2026-09-20-branches-benchmark.md) | new `branches` benchmark added: 13.3-13.4x Lua, mean nudges 8.71x -> 8.88x |
| 2026-09-20 | [`if`, `match` and `try` as statements — item 1's remainder, and `bench/` CANNOT SEE IT — 2026-09-20](results/2026-09-20-if-match-try-statements.md) | item 1's remainder: -12.4% on a synthetic if/else probe, whole set moved 0.005% (bench/ cannot see it) |
| 2026-09-19 | [Cells and payload are two collection schedules — shortlist item 7, 2026-09-19](results/2026-09-19-cells-payload-schedules.md) | shortlist item 7: strings -12.8% wall, 123,925 collections -> 45,627 |
| 2026-09-19 | [A module's blocks are asked whether they declare anything — shortlist item 2, `de4e7c4`](results/2026-09-19-module-block-scopes.md) | shortlist item 2: globals -14.8% wall, 6,000,000 PushScope/PopScope pairs -> 0 |
| 2026-09-19 | [An ordinary call stopped copying its arguments — shortlist item 11, half of it, 2026-09-19](results/2026-09-19-call-args.md) | shortlist item 11 (ordinary calls): fib -29.5%, 69ns off every positional call, geomean 9.7x -> 9.0x |
| 2026-09-19 | [The table stopped hashing through a hook, and a small one stopped having an index — shortlist item 8, `06b2b6c`](results/2026-09-19-table-hashing-small-index.md) | shortlist item 8: mapset -9.9%, alloc -6.8%; per-call Map.set 116ns -> 94ns |
| 2026-09-19 | [A string carries its own character count — shortlist item 4, `7478d4b`](results/2026-09-19-string-character-count.md) | shortlist item 4: strindex 190x faster, strwalk 322x faster, geomean 17.4x -> 13.4x by this item alone |
| 2026-09-19 | [Statement bookkeeping removed — shortlist item 1, `fa327b6`](results/2026-09-19-statement-bookkeeping.md) | shortlist item 1: -20.6% of all instructions, arith -16.3%, geomean 17.4x -> 16.4x Lua |
| 2026-09-18 | [What the first profile shows](results/2026-09-18-first-profile-findings.md) | the first profile's seven findings that chose the shortlist |
| 2026-09-18 | [The profiler](results/2026-09-18-profiler-instrumentation-cost.md) | SLATE_PROFILE report format; --features profile costs 2.4% (control measured 0.999x) |
| 2026-09-18 | [The results](results/2026-09-18-baseline-results.md) | baseline geomean 17.4x Lua / 12.4x node --jitless / 8.3x CPython (dev 26a7721, 0.0.56) |

