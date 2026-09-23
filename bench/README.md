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

**A fifth runtime, `qjs` (QuickJS-ng), is a yardstick alongside `lua`, `node --jitless` and
`python3`** — `brew install quickjs-ng` (`sudo -n -u work -H /opt/homebrew/bin/brew install
quickjs-ng` on this machine; the binary lands on `PATH` as `qjs`). It runs the same `.js` files
already used for `node`/`node --jitless`, no shim needed.

**`bench/pgo.sh [out-dir]` builds the profile-guided binary, and the release tarball is built with
it.** Every build already gets `-O2` and thin LTO from `package.hocon`; a profile is the third lever
and is not a manifest key, being one machine's measurement. The script builds an instrumented slate
(`--lto thin --profile-generate`), runs it once over every `bench/*.sl`, merges the counters with the
`llvm-profdata` the compiler names (`clang -print-prog-name=llvm-profdata` — the one on the `PATH`
may be a different LLVM and refuses the raw format), rebuilds with `--profile-use`, and prints the
path of the result (`pgo/slate` by default, ignored). It measured **−22.2%** on the geometric mean
against a plain `-O2` build ([sysl 0.0.128](results/2026-09-23-sysl-0-0-128.md)). **Compare like with
like**: an item's control and branch are both plain `sysl build .`, never one of them profile-guided.

```
bench/pgo.sh
bench/check.sh pgo/slate
```

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

## Sampling every program at once

**`bench/profile.sl` takes a sampled profile of every benchmark and writes one Markdown report** --
a section per program with its top twelve symbols by self time (symbol, samples, %), read from macOS
`sample`'s own "Sort by top of stack, same collapsed" section. Each program is started under
`--binary` (default `./slate`), handed to `sample` for `--duration` seconds at one sample every
`--interval` milliseconds (defaults 10 and 1), and killed once the sample is in hand, one at a time;
the programs are the bare arguments, or every `*.sl` directly under `bench/` where none is named. A
program that ends before `sample` attaches (`startup`) gets a section saying so. The percentages are
of the samples that section lists, which leaves out any symbol `sample` saw fewer than five times.
macOS only, and under the same quiet-box rule as a timing.

```
caffeinate -dimsu ./slate bench/profile.sl --out=bench/results/profile.md
./slate bench/profile.sl --out=one.md --duration=15 bench/arrays.sl bench/csv.sl
```

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

**Superseded below — this table is sysl 0.0.122 at dev `ebf08c5`, before shortlist items 3 and 4
(`vm-param`, `inline-caches`) and this page's own sysl 0.0.123 item had landed.** Kept for the record
of what 0.0.122 alone moved; read the section after it for where slate stands now.

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

### The CURRENT measured position: dev `0669746`, sysl 0.0.123 — `bench/run.sh -n 5`

**This is the table to read.** It is dev `0669746`, which already carries shortlist items 3
(`vm-param`) and 4 (`inline-caches`) on top of the 0.0.122 table above, plus item 1
([`sysl-0-0-123`](results/2026-09-21-sysl-0-0-123.md), struck through above): the compiler alone
moved this same commit **-16.6%** on the alternating best-of-9. Full detail, and the alternating
before/after table against 0.0.122, is in that write-up.

| program | slate (ms) | vs Lua | vs node --jitless | vs CPython | vs QuickJS-ng |
|---|---|---|---|---|---|
| startup | 4.5 | 1.7 | 14.3 | 13.0 | 2.2 |
| arith | 284.5 | 47.8 | 111.7 | 306.0 | 124.6 |
| reals | 358.9 | 58.7 | 133.1 | 247.3 | 128.2 |
| globals | 1103.9 | 95.6 | 74.2 | 369.6 | 58.3 |
| funcs | 243.4 | 49.0 | 93.8 | 153.2 | 106.2 |
| fib | 540.9 | 79.2 | 167.1 | 202.4 | 165.7 |
| calls | 551.8 | 152.3 | 76.8 | 136.5 | 168.7 |
| methods | 550.2 | 142.0 | 160.3 | 186.1 | 208.6 |
| closures | 245.8 | 47.2 | 78.1 | 133.3 | 87.3 |
| nested | 505.2 | 131.4 | 464.6 | 194.5 | 550.3 |
| loops | 300.9 | 119.7 | 507.5 | 148.9 | 638.4 |
| options | 585.2 | 83.1 | 108.5 | 217.0 | 186.4 |
| fields | 267.6 | 63.0 | 79.8 | 209.1 | 85.3 |
| alloc | 604.1 | 159.1 | 82.1 | 216.3 | 206.5 |
| arrays | 435.1 | 93.0 | 156.7 | 194.5 | 156.3 |
| mapset | 249.5 | 17.6 | 83.4 | 103.4 | 3370.8 |
| dispatch | 484.0 | 90.3 | 148.5 | 214.3 | 277.7 |
| strings | 714.3 | 365.1 | 24.6 | 621.9 | 16.8 |
| strindex | 8.7 | 2.2 | 16.9 | 13.7 | 3.0 |
| strwalk | 10.2 | 147.0 | 17.3 | 13.6 | 2.8 |
| sorting | 518.8 | 566.0 | 801.8 | 378.1 | 1169.1 |
| csv | 365.2 | 304.8 | 130.4 | 84.5 | 169.0 |
| branches | 334.6 | 102.3 | 313.8 | 386.1 | 447.9 |
| **geomean** | | **3.5x** | **2.7x** | **1.8x** | **2.2x** |

**The QuickJS-ng column was added 2026-09-21** ([write-up](results/2026-09-21-quickjs.md)) from a
fresh `bench/run.sh -n 5` at dev `b3f22f1` (`0669746` plus only doc/bench commits — nothing under
`dev/` moved in between), so it sits beside the Lua/node/CPython columns above without a separate
`slate (ms)` re-measurement.

(Read this table's Lua/node/CPython columns as their own wall-clock milliseconds — `bench/run.sh`'s
raw output — not as ratios; the geomean row is the ratio.)

## The ranked shortlist for 0.0.58 and after

**THE LIVE RANKING IS [THE SIXTH SAMPLED PROFILE](results/2026-09-23-sampled-profile-6.md) (dev
`9d794de`, v0.1.3)**, and it is the queue agents are launched from. In one line each — ceilings are
on the geometric mean if an item removed ALL its named cost, which none will:

| rank | candidate | measured | ceiling | where |
|---|---|---|---|---|
| 1 | a string literal is ONE cell, and an object literal with literal keys needs none (**queued**: calls/csv allocation) | 37% of `calls`, ~35% of `alloc`; 2 of 3 allocations per construction | 2–3% | `run_frames.sysl` `PushStr`/`MakeObject`, `code.sysl` `Unit`, `run_compose.sysl`, `table.sysl`, `obj.sysl` |
| 2 | ~~a defaulted bare-name object pattern takes `UnpackFixed`~~ — **DONE, [`unpack-defaults`](results/2026-09-23-unpack-defaults.md)**: `UnpackFixed` carries `UnpackSlots`' mask, the defaults' guarded assignments unchanged; `options` **−41.1%/−41.3%**, geometric mean **−4.09%/−3.69%** | ~40% of `options` | ~2% | `match.sysl`, `slots.sysl`, `run_frames.sysl` |
| 3 | the safe point stops being an instruction (**queued**: superinstructions round 2) | `Tick` mean ~9% of executions, 24 instructions each; `maybe_collect_on` 1.79% weighted | 1.5–2.5% | `emit.sysl`, `compile_stmt.sysl`, `run_frames.sysl`, `obj.sysl` |
| 4 | the call and return arms: no counted `Buf[Ins]` in `Frame`, fewer `keepable_on` | ~50% of `fib`; call path 4.60% weighted | 2–3% | `vm.sysl`, `run_frames.sysl`, `execute.sysl` |
| 5 | a proto hit is one look | 27.8% of `methods` | ~1% | `site_cache.sysl`, `table.sysl` |
| 6 | a builtin method call is cached at its site (**queued**: the `methods_of` half) | ~23% of `mapset`; `methods_of` 0.77% weighted | ~1% | `method.sysl`, `index.sysl`, `site_cache.sysl` |
| 7 | the head's reachable switch default and duplicate bounds check — a **sysl** codegen finding | 5 of 17 head instructions | 1–2%, measure first | sysl |
| 8 | a builtin name resolved at compile time | `csv` `LoadName` 8.9% of executions | ~0.5% | `defs.sysl`, `compile_expr.sysl`, `run_frames.sysl` |
| 9 | threaded dispatch — still a sysl gap | the shared `br` | 4–8% | sysl |
| 10 | the four fused arms inline again — re-measure now the head has registers | 9.83% weighted | unknown | `run_frames.sysl`, `run_compose.sysl` |

**The history below is kept for its struck rows and their numbers**; it is not a ranking any more.

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
| 1 | ~~inline `Buf.push` the way 0.0.122 inlined `Buf.at` (**sysl's `buf.sysl`, not slate's**)~~ — **DONE, sysl 0.0.123, [`sysl-0-0-123`](results/2026-09-21-sysl-0-0-123.md): -16.6% geometric mean**, above the 10–15% ceiling; `Buf.push<Value>` on `methods` 16.2% → 1.9% | was 18.5% | **DONE**, above the 10–15% ceiling |
| 2 | a register machine instead of a stack machine | 15.5% | 10–15% |
| 3 | ~~stop re-asking `current()` in the hot helpers (`_tlv_get_addr`)~~ — **DONE 2026-09-21, [`vm-param`](results/2026-09-21-vm-param.md): -4.06% geometric mean**, `dispatch` -12.3%, `arith` -11.8%, `fib` -8.0%; `_tlv_get_addr` on `fib` 4.4% → **0.4%** | was 4.3% | 3–4%, and it took 4.1% |
| 4 | ~~inline caches for a field or a method~~ — **DONE 2026-09-21, [`inline-caches`](results/2026-09-21-inline-caches.md): -2.33% geometric mean**, `fields` -40.2%, `methods` -10.5%; the lookup's self time on `methods` 29.5% → **20.3%** | was 6.5% | 3–4%, and it took 2.3% |
| 5 | module-level `var` cells, `StoreDef` | 3.7%, ~30% of `globals` | 0.5% of the mean |
| 6 | `match_walk` — `for` heads, `match` arms, destructuring — **new** | 3.8% | 2–3% |
| 7 | ~~what `calls` and `csv` allocate per call~~ — **DONE 2026-09-23, [`call-path`](results/2026-09-23-call-path.md): −5.24% geometric mean**. An object's entry table (a malloc, a fill and a free per object — a sweep now keeps it for the next one), `split`'s throwaway list, the method tables asked at every builtin-kind call (now remembered at the site), and a 136-byte `Chunk` copy per call: `calls` −20.2%, `alloc` −21.5%, `csv` −12.7%, `fib` −12.3%, `methods` −7.3% | was 8.9% | took 5.2% |
| 8 | a narrower `Value`, or NaN-boxing | 15.5% | 5–8% |
| — | ~~a `Signal` no wider than it has to be~~ — **DONE 2026-09-23, [`signal-slim`](results/2026-09-23-signal-slim.md): −19.4% geometric mean**. Not on any profile: 0.1.2's throw-with-value put a `Value` inside `Fail`, and `Step` went 64 → 112 bytes under every arm. The value lives in a VM table now and `Step` is 64 again. **The width of `Step` is a cost every arm pays**, which is the argument item 8 makes from the other side | a regression, +17.9% in 0.1.2 | recovered it and 1.5 points more |
| — | ~~a counted loop's head and tail as one dispatch each~~ — **DONE 2026-09-23, [`superinstructions-2`](results/2026-09-23-superinstructions-2.md): −10.18% geometric mean**, chosen off a pair count over all twenty-three with the profiler's post-fusion blind spot fixed: `TickSlotIntLess` (63.6M) and `SlotIntAddStoreJump` (59.0M) fold five instructions each, `SubStoreSlot` (20M) the difference pair; instructions −17.2%, `arith` −36.2%. The heaviest pair, `AddStoreSlot Jump` (78.6M), measured −0.35% alone and was **struck** | the pair table in the write-up | took 10.2% |
| — | ~~link-time optimization and a profile-guided build~~ — **DONE 2026-09-23, sysl 0.0.128, [`sysl-0-0-128`](results/2026-09-23-sysl-0-0-128.md): thin LTO in the manifest −6.56%, plus `bench/pgo.sh` −22.22%** geometric mean against plain `-O2`. On no profile: it is the build, not the interpreter. `fib` −35.8%, `dispatch` −35.1%, `reals` −32.6%; position **2.2x Lua / 1.6x node --jitless / 1.1x CPython / 1.3x qjs** | not a profile line | the release build |
| — | ~~a string built by appending copies everything it holds on every turn~~ — **DONE 2026-09-23, [`string-append`](results/2026-09-23-string-append.md): −15.39% geometric mean**, all of it `strings`: **739.8 → 32.6 ms (−95.6%)**, 44x → **1.9x qjs** and now 19x faster than CPython. A room is shared storage with spare capacity; the tip appends in place and no byte a string can see is rewritten. Needed sysl 0.0.129's `str_view`. `string(n)` of an integer counts its own digits (−5.9% more on `strings`) | the append was n²/2 bytes of copying | took 15.4% |
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
| 11 | ~~**Make the CALL PATH cheaper** -- the argument `Buf` is a malloc per call, `Buf.at` retains and releases it on every read~~ — **DONE in two halves**. `call-args` + `ctor-calls`: an ordinary positional call allocates nothing (69 ns off every one of `fib`'s eleven million) and neither does a positional construction (59 ns off every one of `calls`'s two million). `native-args`, 2026-09-20: a BUILTIN reads its arguments through a window onto the stack they are standing on, so the malloc, the free, the copies and the per-argument hold are gone from the call slate makes most of — `mapset` **-25.6%** (47.4x -> **34.1x** Lua), `csv` **-13.5%**, geometric mean against Lua 8.9x -> **8.65x**, and twenty of the twenty-two read zero. ~~**`methods_of` looking a method up by name every time is what is LEFT of this item**~~ — **DONE 2026-09-23 with row 7 above, [`call-path`](results/2026-09-23-call-path.md)**: a `CallMethod` site remembers a builtin kind's method, and `methods_of` is gone from `csv`'s sampled profile | measured above | INCREMENTAL, and all three parts have landed |

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
| 2026-09-23 | [2026-09-23 — A STRING BUILT BY APPENDING SHARES ONE GROWING BUFFER: `strings` 740 → 33 ms](results/2026-09-23-string-append.md) | **geometric mean −15.39%** on an alternating best-of-9 against dev `b1dc161`, nearly all of it `strings` **−95.6%** (739.8 → 32.6 ms; qjs 16.8, CPython 629). A ROOM is a heap cell holding a buffer with spare capacity and a `used` mark; every string made by appending VIEWS a prefix of it (sysl 0.0.129's `str_view`), the tip appends in place, and a non-tip append copies, so an alias never changes. Charged once at capacity; the recount stays exact. Plus `string(n)` of an integer counting its own digits (−5.9% on `strings`). What is left: `string()`'s `snprintf` ~34%, the collector ~21%, malloc/free ~15%, dispatch ~11%, the append itself ~6% |
| 2026-09-23 | [2026-09-23 — SUPERINSTRUCTIONS, ROUND TWO: A COUNTED LOOP'S HEAD AND TAIL ARE ONE DISPATCH EACH](results/2026-09-23-superinstructions-2.md) | **geometric mean −10.18%** on an alternating best-of-9 against dev `9d794de`. The first round's pairs had become the front halves of two five-instruction runs every counted loop executes once a turn, so the RUN was fused: `TickSlotIntLess` (`Tick LoadSlot PushInt Less JumpIfFalse`, 63.6M) and `SlotIntAddStoreJump` (`LoadSlot PushInt Add StoreSlot Jump` over one slot, 59.0M), plus `SubStoreSlot` (20M). Inner pairs are folded where they stand, so no jump target needs analysis; operands too wide for eight bytes are read lazily from the slots stepped over. Instructions executed **−17.2%** (1.54G → 1.28G); `arith` **−36.2%**, `closures` −20.7%, `fib` −20.4%, `funcs` −20.0%, `reals` −19.7%, `fields` −17.3%, `dispatch` −17.1%; `globals` +1.6%, `strings` +0.8%. **The heaviest pair, `AddStoreSlot Jump` (78.6M on twenty programs), measured −0.35% on its own and was STRUCK.** The profiler never counted a pair that began after a fused instruction (`op_width` fixes it), and under sysl 0.0.127 the dispatch is ONE jump table over every tag, so the cold-block line no longer marks a second table. `check.sh` unchanged |
| 2026-09-23 | [2026-09-23 — sysl 0.0.128: thin LTO in the manifest, and a profile-guided release build](results/2026-09-23-sysl-0-0-128.md) | **geometric mean −6.56% for `lto = "thin"` alone and −22.22% with `bench/pgo.sh`'s profile on top**, alternating best-of-9 against the same dev `5240032` built plain `-O2` with the same compiler. The floor moves to 0.0.128 because an older compiler silently ignores the `lto` key. LTO leads with `methods` −17.4%, `options` −13.8%, `nested` −13.3%; the profile with `fib` −35.8%, `dispatch` −35.1%, `reals` −32.6% — the dispatch loop laid out around the arms actually taken — and every one of the 23 programs faster. **Position 2.2x Lua / 1.6x node --jitless / 1.1x CPython / 1.3x qjs** (`run.sh -n 5` on the PGO binary); faster than CPython on eight programs. The PGO binary is the smallest of the three (5,811,064 bytes against 5,914,776 plain); build 251 s against 111 s. `check.sh` unchanged. The release tarball is built with `bench/pgo.sh` from now on |
| 2026-09-23 | [2026-09-23 — A ROW OF NAMES WITH DEFAULTS TAKES THE INSTRUCTION — profile 6's item 2](results/2026-09-23-unpack-defaults.md) | profile 6's item 2: **a default is not a half-match**, so `UnpackFixed` takes `{ width = 10, height, scale = 2 }` and `[a, b = 7]` too, leaving `UnpackSlots`' mask for the unchanged `JumpIfSet` guarded assignments — a non-constant default needs them anyway, so nothing is precomputed. `options` **505 → 297 ms, −41.1%/−41.3%**; geometric mean **−4.09%/−3.69%** over two alternating best-of-9 runs; counts one-for-one (4M `UnpackSlots` → `UnpackFixed`); `run_frames.sysl` two lines shorter; `check.sh` unchanged |
| 2026-09-23 | [2026-09-23 — THE CALL PATH STOPS ALLOCATING: A TABLE PER OBJECT, A LIST PER SPLIT, AND THE METHOD TABLES PER CALL](results/2026-09-23-call-path.md) | the shortlist's row 7 and the rest of item 11: **geometric mean −5.24%** on an alternating best-of-9, `calls` **−20.2%**, `alloc` −21.5%, `csv` **−12.7%**, `fib` −12.3%, `methods` **−7.3%**, nothing slower than +0.5%. An object's `Buf[Entry]` was a malloc of eight entries, a fill and a free per object — a sweep keeps it for the next object now (`Vm.spare_entries`, bounded at 1,024; `dispose_vm` enters the VM it disposes so an actor's teardown cannot touch main's list); `split` stops building a sysl list it threw away; a `CallMethod` site remembers a builtin kind's native (`method_kind_code`); and `placed_call` reads the chunk's fields in place instead of copying the 136-byte `Chunk`. `sample`: `calls` 264 → 181 samples, every `Buf.grow<Entry>`/malloc/free frame gone. Position **2.7x Lua / 2.0x node --jitless / 1.4x CPython / 1.7x qjs** |
| 2026-09-23 | [A sixth sampled profile: the head is seventeen instructions, and the arm term is back (dev `9d794de`, v0.1.3)](results/2026-09-23-sampled-profile-6.md) | **the live ranking.** The dispatch head is **17** instructions (profile 5: 22) and **30–47%** of what the loop executes (was 38–62%), ~12 points of weighted wall; the fit's arm term is back for the first time in four pages (`D = 0.36, E = 1.56 ns`, single-term **1.44 ns**, was 1.65). **The new item 1 is a literal**: `PushStr` builds a fresh string cell every run, so two of the three allocations in every constructor call are its key strings — `calls` and `alloc` both 3.0 allocator steps per object, **37% of `calls`** in allocation, malloc and construction. `options` spends ~40% in the matcher because a DEFAULT keeps `{ width = 10, height }` off `UnpackFixed`; `Tick` is the head of the top pair on nine programs; call/return is half of `fib`. Sampled with the quiet check before every program — a first pass under another agent's JVM was discarded. LTO is not in this binary: sysl 0.0.127 has no flag for it |
| 2026-09-23 | [2026-09-23 — A THROWN VALUE LIVES OFF THE `Signal`, AND `Step` IS 64 BYTES AGAIN](results/2026-09-23-signal-slim.md) | **the 0.1.2 regression, found and undone: geometric mean −19.42%** on an alternating best-of-9 against dev `54c138a`. A bisect of 0.1.1 → 0.1.2 put +17.9% on `34d2adf` alone (throw carrying a value, same compiler both sides) and −3.6% on the sysl 0.0.126 pickup beside it. **The mechanism is width**: `Fail` gained an `Option[Value]`, so `Signal` went 56 → 104 bytes and `Step = Result[Value, Signal]` 64 → **112** — the aggregate every arm of `run_frames` answers, fault or no fault. `Fail` now names its value by a 32-bit index into `Vm.carried`, packed with a 32-bit `src` into the word `src` had; `Step` is `{ i32, [7 x i64] }` again. Every program moves: `reals` −39.4%, `mapset` −36.9%, `sorting` −33.1%, `arith` −31.4%, `strings` −0.4%. The feature is unchanged and `tests/lang/faults.sl` passes unedited on both back ends |
| 2026-09-23 | [2026-09-23 — A PROPERTY READ HANDS THE NATIVE THE RECEIVER WHERE IT STANDS — profile 5's new item](results/2026-09-23-property-reads.md) | profile 5's newest row, found under the struck `mach_absolute_time` one: `xs.length` is a **builtin call** (`length` IS `NLen`) whose only argument is the value being read from, and `native-args` left that one path on the argument buffer — a malloc, a push, a copy, a truncate and a free **per read**, 5,000,010 of them in `arrays.sl`. The receiver is already standing on the operand stack when a field instruction reads it, so `read_field_of_kind` takes a `standing` flag and `standing_property` hands the native a one-cell window; the instruction's own truncate-and-push is the cut, exactly as `standing_native`'s caller geometry. **Geometric mean −2.59%** on an alternating best-of-9: `arrays` **−27.8%**, `strwalk` **−8.7%**, `csv` −5.2%, `strindex` −4.7% — `while i < s.length` being ordinary slate with no way round it, `len(x)` having been removed. Position **3.4x Lua / 2.6x node --jitless / 1.8x CPython / 2.2x qjs**, `arrays` alone 5.5x → **4.0x** Lua. **`SLATE_PROFILE` could not see this and says so**: `length`'s ~197,000 µs does not move, the per-builtin timer bracketing `run_native` while the `Buf` sat outside it in `call_native_buf`. The witness is `sample` — 369 main-thread samples to **269**, the whole `free` node (14.1%) and every malloc frame **gone**, `grep -c` over the report 10 → 0. Counts unchanged (no `Op` touched), `check.sh` unchanged |
| 2026-09-23 | [2026-09-23 — `sh.sysl.gc` 0.2.5: the classifier is free, `alloc_raw` reaches one constructor, and `arrays` was never timing itself](results/2026-09-23-gc-0-2-5.md) | **three questions and all three answered no, which is why the page is worth reading.** gc 0.2.5's two changes — a `leading_zeros` size-class classifier and `alloc_raw`, worth 6.7% and 6.4% on the package's own allocate-and-drop — are **worth zero here**: geometric mean **+0.51%** and **−0.09%** over two alternating best-of-9 runs, with fifteen of twenty-three programs changing SIGN between them, and `alloc`/`calls` (gc 0.2.4's −18.8%/−15.5%) straddling zero. A share of a function already down to 2.06% is not a share of the mean. **`alloc_raw`'s contract reaches ONE of slate's ten constructors**: its second condition forbids assigning a counted member into uncleared storage, and every slate heap object but `WeakRefObj` owns a sysl `string`, `Buf` or `Map` by design — so `new_weak_ref` landed on it (two tests over a 256 KiB heap, 480 collections, blocks provably reused) and the rest stay on `alloc`; what gc needs for the hot ones is a prefix-clearing entry point, slate's counted members being the leading fields. **And profile 5's `arrays` row was struck for the wrong reason**: that program reads no clock and neither does any twin — `sample` puts `mach_absolute_time` under **`_xzm_free`**, macOS's own allocator, with the whole `free` node at 16.6% and no `gc` symbol in the profile at all. Under it is a real item nobody had: a builtin **property** read still mallocs and frees a one-element `Buf` per call, **5,000,010** of them in `arrays.sl`, which `native-args` took off every other builtin call. Counters identical to the instruction on five programs, `check.sh` unchanged. **Measured against dev `5484870`, before `for-head` landed** |
| 2026-09-23 | [2026-09-23 — A ROW OF BARE NAMES IS TAKEN APART BY THE INSTRUCTION — profile 5's item 4](results/2026-09-23-for-head.md) | profile 5's item 4, the last of the matcher items: **a pattern that is a row of BARE NAMES cannot half-match**, so `UnpackFixed` checks the subject's kind and its length or its keys and writes the cells straight out of it — no `match_walk`, no `match_array`, no `match_leaf` per name, nothing pushed onto the operand stack and no `lay_bindings` copy down. An array of `n` names, closed, and an object of `n` keys, each with no default, no `?`, no rest and nothing nested; **everything else still walks**, and a subject that does not fit gets `unpack_complaint`'s own sentence, the instruction keeping the pattern index for exactly that. It is a **binding site's** rule and not a `for` head's, so `val { a, b } = p` and an unpacking parameter take it too. **Geometric mean −3.16%/−2.99%** over two alternating best-of-9 runs against a 1–1.5% ceiling, with the two rows the item named taking far more than their share of the mix: `loops` **−30.6%/−33.1%**, `nested` **−15.1%/−13.7%**, `branches` −3.3%/−5.6% — what came off is a call graph rather than an instruction. Counts identical to the instruction (`UnpackSlots` → `UnpackFixed`, 8M on `loops`, 6M on `nested`). `loops` goes 2.6x lua to **1.7x**, `nested` 3.8x to 3.1x; position 3.5x lua / 2.7x node --jitless / 1.8x CPython / 2.2x qjs |
| 2026-09-23 | [2026-09-23 — A NARROWER `Ins` — profile 5's item 1](results/2026-09-23-narrow-ins.md) | profile 5's item 1, and **half of it wins while the other half loses**. `Op` goes 40 bytes to **16** — no variant's payload may exceed eight, two operands being a pair of `u32` (seventeen variants) and the six that carry three or four holding a `u32` into a new `Unit.wide` (`CheckSlot`, `CallMethod`, `CheckType`, `DeclareCell`, `DefineDef`, `UnpackSlots`), with `LoadSlotInt` folding a 32-bit literal and leaving a wider one as the pair it was. `Ins` is **56 → 32 bytes**, the stride is a `lsl #5` instead of a `mov`+`madd` by 56, the head is **22 → 18** instructions and **all three spill reloads of the code base and length are gone** — the loop finally has registers. **Geometric mean −2.06%** on an alternating best-of-9: `fib` −9.2%, `arith` −7.1%, `arrays` −5.8%, `branches` −5.8%, `reals` −4.9%, `funcs` −4.6%, `fields` −4.5%. **The item's OTHER half — the span out of the instruction, which is what sixteen bytes needs — was built, measured at +1.65% and BACKED OUT.** It reached 16 bytes and a 13-instruction head and lost on every call-heavy program (`funcs` +7.0%, `options` +6.7%, `nested` +6.6%, `calls` +5.6%), because a span is an ARGUMENT and not only a fault's address: every operator passes one to its leaf, and a call passes one PER ARGUMENT. **A hot sample on the last load of a multi-load fetch says the FETCH is expensive, not the field** — which re-prices item 5 as well. Counts identical to the instruction, `check.sh` unchanged. Position 2.9x lua / 2.2x node --jitless / 1.8x qjs / 1.5x CPython |
| 2026-09-23 | [2026-09-23 — sysl 0.0.126: a by-value counted parameter is BORROWED, and the caller decides](results/2026-09-23-sysl-0-0-126.md) | **the largest compiler pickup yet: geometric mean −4.48%/−4.58%** over two alternating best-of-9 runs on dev `6779890`, `package.hocon`'s floor and the two `SYSL_VERSION` pins being the whole diff. A callee no longer retains a by-value counted parameter at entry — the CALLER decides, so a temporary, a literal and an unexposed local cost nothing and only a memory place pays, at the call. The interpreter is built out of that case (`Buf.at`/`push`/`len` all take `self` by value off a `*Buf` field), so the call-heavy programs take it: `methods` **−12.8%/−12.8%**, `options` **−12.2%/−12.3%**, `csv` **−11.8%/−11.9%**, `nested` −9.4%/−10.7%, `closures` −8.7%/−8.9%; `strings` and `sorting` read slower, their loops being inside a builtin. Position **3.0x Lua / 2.3x node --jitless / 1.6x CPython / 1.9x qjs**. **There is no ARC frame to sample** — sysl inlines retain/release, `grep -c arc` is 0 on all four samples — so the witness is that `methods` takes 312 main-thread samples where the control took 394, `field_here` folds into `read_field_site`, and the malloc family does NOT move (`_xzm_free` 3.2% → 2.8%): the count pairs never reached the allocator. Instruction counts identical to the instruction on both programs, collections/allocator steps/high water identical, binary +3.1%. `sysl vendor .` fixed and confirmed (17 packages into a scratch target) |
| 2026-09-22 | [2026-09-22 — ONE JUMP TABLE INSTEAD OF TWO — profile 5's item 2](results/2026-09-22-one-jump-table.md) | profile 5's item 2, and **the cause was not the one that page guessed**: the back end folds the first **forty-two** arms of a `match` into one switch and every arm after them shares a second, so which instructions get the single-level table is decided by the order the ARMS ARE WRITTEN IN and by nothing else. The old first table's forty-two were exactly the arm list's first forty-two lines — `SealData`, the constants, the checks, the handlers — while `Jump`, `JumpIfFalse`, `Equal`, `Mul`, `Rem`, `Pop`, `CallFn`, `Ret`, `TestSlots`, `Tick` and all four fused pairs paid nine extra instructions and a second unpredictable indirect branch. Proved by moving fifteen cold arms out of the head and watching the boundary stay at forty-two, at 100% density. The fix is the arm list in two blocks plus eight variants moved in `Op`: `Tick` and the four fused pairs up (they held 105–109, above any range the hot arms could span, and are 38.8% of the mix between them) and `PushNull`/`PushUndefined`/`PushBool` down (they held tags 0–2, are 0.001% of the mix, and a cold variant below every hot one costs a `sub` on **every** dispatch — **worth 1.4% measured on its own**). **Geometric mean −2.69%** on an alternating best-of-9, against a 1–2% ceiling: `methods` −11.5%, `fib` −9.2%, `dispatch` −9.0%, `funcs` −7.7%, `strindex` −5.4%. Instruction counts identical op by op, `bench/check.sh` unchanged, no new test (rule 4-0). **`loops` is +3.0% in both runs and is not explained** — it is the program the four fused ops carry, every counter says it should have won, and what is left is code layout |
| 2026-09-22 | [2026-09-22 — A FIFTH SAMPLED PROFILE, AND THE DISPATCH FINALLY HAS A NUMBER](results/2026-09-22-sampled-profile-5.md) | **the dispatch HEAD — the instruction fetch and the indirect jump — is about HALF of `run_frames`, which four profiles could not say.** Two instruments agree and neither is new: `sample`'s leaf offsets put BOTH hottest program counters inside a 22-instruction block on **18 of the 19** programs where the loop is sampled (`+556`, the last 16 bytes of the 56-byte `Ins`; `+508`, a spilled length reloaded for a bounds check that cannot fail), and **reading the jump tables out of the binary** against the executed instruction mix puts the head at **38–62% of the loop's machine instructions, 46% unweighted**. So ~14 points of weighted wall is fetch and decode: 3 spill reloads, 4 bounds-check instructions, 4 loads pulling all 56 bytes whatever the arm wants, and a **two-level** jump table — `Op` splits at tag 27 and every tag above it pays a second indirect branch. `D = 1.67 ns, E = −0.03 ns`, the third page running with no arm term. The five items since profile 4 are all legible: lookup 7.41% → 4.43%, allocation 11.88% → 7.78%, the name path 3.91% → 1.78%, `match_walk` 4.49% → 1.79%. **The shortlist is now entirely the head** — a narrower `Ins` (2–4%), one jump table instead of two (1–2%, cheap), threaded dispatch (4–8%, **blocked: a sysl gap — no labels-as-values, `@tailrec` is self-only**), the `for`-head instruction (1–1.5%), and a register machine re-priced UP for the first time. `gc.alloc`'s remaining 2.06% is a size-class classifier, not the header write |
| 2026-09-22 | [2026-09-22 — `sh.sysl.gc` 0.2.4: THE ALLOCATOR STOPS WALKING THE BIN ARRAY](results/2026-09-22-gc-0-2-4.md) | **the `gc-alloc` proposal, built in the package and picked up here**: `struct Heap` grows a two-word bitmap of the non-empty size classes and the search for the next one is a shift and a `trailing_zeros` instead of up to 87 dependent loads. **geometric mean −2.46%** on an alternating best-of-9, with the three programs the investigation named taking it — `alloc` **−18.8%**, `calls` **−15.5%**, `csv` **−11.9%** — against a predicted 20–28% each and ~6% of the mean. `gc$alloc`'s sampled self time on `alloc.sl` goes **25.9% → 9.8%** over three runs a side, and it is no longer the top of that program's profile. Position **3.2x Lua / 2.5x node --jitless / 1.7x CPython / 2.0x qjs**. Nothing under `dev/` moved — `package.hocon`'s version and one `sysl.sum` line are the whole diff, instruction counts are identical to the instruction on all three programs, and **`alloc_steps` is identical too because it counts blocks EXAMINED rather than bins walked**, so the counter the proposal wondered about could never have seen this |
| 2026-09-22 | [2026-09-22 — `gc.alloc` IS ONE LOOP, AND THE LOOP IS A LINEAR SCAN OF THE BIN ARRAY](results/2026-09-22-gc-alloc.md) | **an INVESTIGATION, and the 6.2% has a name**: `sample` prints a leaf frame with a byte offset, so the samples inside one function can be read against `otool -tv` — and 95 of `alloc.sl`'s, 78 of `calls.sl`'s and 49 of `csv.sl`'s `gc$alloc` samples are in ONE node whose two hottest PCs are both in `take_larger`'s six-instruction bin scan, walking up to **87 size classes per allocation**. `rebuild_free` coalesces dead cells into LARGE blocks and `split` returns the remainder to a large class, so slate's exact small class stays empty and the walk is the steady state, not a warm-up. **The fix is `sh.sysl.gc`'s** — a two-word bitmap of the non-empty classes and a `trailing_zeros`, ceiling ~6% of the mean — and is written up as a proposal with the exact functions. What landed here is slate's half: **an allocation reads the VM once** instead of three times (`vm-param`'s pattern on `alloc_or_collect`/`charge_on`), **−0.62%/−0.28%** geometric mean over two alternating best-of-9 runs, the short allocation-dense programs agreeing (`startup` −2.1/−3.1%, `strwalk` −2.4/−4.4%, `fields` −1.1/−1.1%) |
| 2026-09-22 | [2026-09-22 — A MODULE'S OWN `val` AND `var` GET A CELL — profile 4's item 4](results/2026-09-22-module-cells.md) | profile 4's item 4: a module never slots, so a name written at a file's own top level was ten hashes of its spelling per turn of a loop — four `lookup`s and two `assign_name`s, and an `assign_name` asks `has`, `get_or` and `put`. The table `LoadDef` already reads is opened to a top-level `val` and `var`: `LoadCell`/`DeclareCell`/`StoreCell`, an empty cell reading `Undefined` (the one value a program may not keep) and falling back to the lookup, the module's scope written through on every store so an import and `declared_here` still see it. **`globals` −35.8%/−36.1%, geometric mean −1.82%/−1.87%** over two alternating best-of-9 runs, against a 0.6–0.9% ceiling; `globals` goes 19x qjs to 12.1x. The whole `Map<string, *>` read path falls off its sampled profile. **The suite found an older bug on the way**: a binding `is` never called `shadowed_pattern`, so `if v is tag` read the file's `def tag` instead of what it had just bound |
| 2026-09-22 | [2026-09-22 — A LEAF PATTERN IS ANSWERED WHERE IT IS REACHED — profile 4's item 3](results/2026-09-22-match-walk.md) | profile 4's item 3: `match_walk` is entered once per pattern AND once per pattern inside it — three times a turn for `for [a, b] in pairs`, once per arm tried for a `match` on strings — and `-O2` prices its 496-byte frame and seven register pairs off the deepest arm the dispatch has. `match_leaf` answers the shapes with no pattern inside them (a name, a wildcard, a literal) in an 80-byte frame and hands everything else to the walk unchanged. **`loops` −9.8%/−8.0%, `dispatch` −3.3%/−5.0%, `nested` −1.5%/−3.1%, geometric mean −0.59%/−0.89%** over two alternating best-of-9 runs; `match_walk` falls off `dispatch`'s sampled profile entirely. **Cutting the dispatch up was tried FIRST and measured +0.69%** — the inlined compound arms are worth more than a smaller function, so what to cut is how often it is entered |
| 2026-09-22 | [2026-09-22 — THE HIT PATH OF A FIELD READ IS ONE LOOK AT THE ENTRY — profile 4's item 2](results/2026-09-22-lookup-hit-path.md) | profile 4's item 2: the inline caches were right and were reading the entry TWICE — once to compare the key and once for the value — and comparing the key where the stored hash already settles it. `field_here`/`set_here` answer both questions from one read, the hash is compared first, and an own-field hit is answered inside `read_field_site` without calling `field_from_site` at all. **`fields` −9.1%/−9.7%, `methods` −12.1%/−10.8%, geometric mean −0.60%/−0.75%** over two alternating best-of-9 runs. `field_from_site` falls off `fields`' sampled profile entirely; the lookup group on `methods` goes 1,394 samples to 1,150 |
| 2026-09-22 | [2026-09-22 — THE FOUR FUSED ARMS GO BACK OUT OF LINE, AND THE COLD-ARM MOVE STAYS — profile 4's item 1](results/2026-09-22-unfuse.md) | profile 4's item 1 undone: **−0.70% geometric mean** over the twenty (`branches` −6.7%, `closures` −3.2%, `funcs` −2.6%), three binaries from one worktree timed alternating best-of-9 twice. The variant that keeps the seven cold arms in `run_compose.sysl` and the full revert differ by 0.09–0.26%, which is inside the instrument, so the cold-arm move is **worth nothing either way** and stays. `nm`: the four `fused_*` bodies are back with one `bl` each and no `@noinline` is needed — external linkage from the file split is what keeps them out of line |
| 2026-09-22 | [A fourth sampled profile, and where the missing 2% went (dev `f36f35e`, sysl 0.0.125)](results/2026-09-22-sampled-profile-4.md) | **the live ranking**: the missing 2% is an INTERACTION, not a leak — rebuilt with one compiler and timed alternating best-of-9, `inline-fused` now costs **+1.19% geometric mean** (`branches` +6.7%) because sysl 0.0.124 inlined `Buf.push` into a `run_frames` that already used every callee-saved register and a 1,504-byte frame; the loop got **18% SMALLER** (49,232 → 40,300 bytes) and slower, and the allocator spills three of its own parameters at entry. New item 1 is a **revert**. `run_frames` 35.3% weighted with the fused arms absorbed, `Buf.push<Value>` 0.88% → 0.17%, the arm term of the fit still zero (D = 2.10 ns, E = −0.11 ns) |
| 2026-09-22 | sysl 0.0.125 picked up, no bench | `@inline` attribute and `sysl.process.run`/`capture`'s `timeout` parameter — neither touches the interpreter, so no measurement is owed; the `timeout` is what bounds the differential corpus's `node` child (see the 0.0.125 pickup commit) |
| 2026-09-22 | [2026-09-22 — sysl 0.0.124: `Buf.push` inlines outright for a counted element](results/2026-09-22-sysl-0-0-124.md) | mechanism confirmed (`Buf.push<Value>` self time 3.2% → 0% on the witness) but a WASH on wall time after `inline-fused` landed underneath it (+0.06%/+0.16% on dev `24a2cb0`, vs -2.08% on the pre-merge tree); position 3.5x/2.6x/1.8x/2.2x |
| 2026-09-21 | [2026-09-21 — THE FOUR SUPERINSTRUCTION ARMS ARE WRITTEN OUT IN THE DISPATCH — shortlist item 1](results/2026-09-21-inline-fused.md) | profile 3's item 1: **-1.96% geometric mean**, `fib` -6.4%, `arith` -5.3%, `fields` -4.5%; all four `fused_*` symbols gone from the binary and the instruction counts identical. **Why `-O2` never inlined them: `private` in sysl is per FILE, so a body called across one lowers to EXTERNAL linkage and the inliner's single-caller bonus cannot apply** — a fast path that has to be inline belongs in its caller's file |
| 2026-09-21 | [A third sampled profile, after sysl 0.0.123, the VM parameter and the inline caches (dev `a642e9f`)](results/2026-09-21-sampled-profile-3.md) | **the live ranking**: `Buf.push<Value>` 15.3% → 0.9% (closed), `_tlv_get_addr` 4.3% → 1.3% (closed), `run_frames` 29.1% and it is the DISPATCH — fitted at a flat 1.30 ns/instruction with 0.00 ns of arm dependence; the four `fused_*` superinstruction arms are **out-of-line calls** at 7.4% and are the new item 1 |
| 2026-09-21 | [2026-09-21 — a fifth runtime: QuickJS-ng, and slate's geomean against it](results/2026-09-21-quickjs.md) | `qjs` added as a fifth comparison runtime (bench tooling only); geomean vs QuickJS-ng 0.16.2 is 2.2x, between `node --jitless` (2.7x) and CPython (1.8x) |
| 2026-09-21 | [2026-09-21 — sysl 0.0.123: `Buf.push`'s grow path moves out of line — shortlist item 1](results/2026-09-21-sysl-0-0-123.md) | shortlist item 1: -16.6% geometric mean, `Buf.push<Value>` on `methods` 16.2% → 1.9%; new position 3.5x/2.7x/1.8x |
| 2026-09-21 | [2026-09-21 — A FIELD READ REMEMBERS WHERE IT LOOKED — shortlist item 4](results/2026-09-21-inline-caches.md) | shortlist item 4: -2.33% geometric mean, `fields` -40.2%, `methods` -10.5%, the lookup on `methods` 29.5% → 20.3% |
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

