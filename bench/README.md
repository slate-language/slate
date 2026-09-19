# The benchmarks, and what the first profile says

Twenty programs, each written four times -- in slate, in Lua, in JavaScript and in Python -- and a
profiler for the interpreter that runs them. **Nothing here makes slate faster.** It exists so that
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

`check.sh` runs all four implementations of all twenty and diffs every answer against
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
| `sorting` | `sorted` over 20,000 numbers, two hundred times |
| `csv` | the realistic mix: generate a comma-separated text, split it, convert and add |

**Each is sized so that Lua takes roughly a fifth of a second**, which is long enough to measure and
short enough that slate finishes in a couple. **`strindex` is deliberately outside that band**: sized
for Lua it would run for hours under slate, and sized for slate the other three finish before their
own start-up is over. That gap is the measurement.

**Every twin says in its header where it differs from the slate program** -- Lua has no set, no
destructuring and no `match`; JavaScript has one number type and sorts by string unless told
otherwise; Python's integers are arbitrary precision and its `+=` on a string may be linear where
everybody else's is quadratic. Where a language cannot do the same thing, the twin does the nearest
honest thing and says so rather than the slate program being bent to match.

## The results

Taken 2026-09-18 on this machine, slate at `bench-lua` off `dev` `26a7721` (0.0.56), best of 5,
under `caffeinate`, box at 97.6% idle. Lua 5.5.1, node v24.14.0, Python 3.14.7. Milliseconds of
process wall time.

|  | slate | lua | node --jitless | python3 | slate/lua | slate/node-jl | slate/py | *node+jit* |
|---|---|---|---|---|---|---|---|---|
| startup | 4.6 | 1.8 | 14.2 | 13.1 | 2.6x | 0.3x | 0.4x | *14.2* |
| arith | 1474.6 | 48.4 | 113.3 | 306.6 | 30.5x | 13.0x | 4.8x | *26.5* |
| reals | 1473.5 | 59.8 | 133.7 | 249.0 | 24.6x | 11.0x | 5.9x | *25.8* |
| globals | 2603.5 | 110.7 | 77.9 | 380.0 | 23.5x | 33.4x | 6.9x | *25.7* |
| funcs | 1542.1 | 50.6 | 98.1 | 155.3 | 30.5x | 15.7x | 9.9x | *20.2* |
| fib | 2811.5 | 78.8 | 173.5 | 204.2 | 35.7x | 16.2x | 13.8x | *35.7* |
| calls | 1561.7 | 154.2 | 80.1 | 140.0 | 10.1x | 19.5x | 11.2x | *21.3* |
| methods | 2462.6 | 144.0 | 165.1 | 190.2 | 17.1x | 14.9x | 12.9x | *19.6* |
| closures | 1228.3 | 47.8 | 80.9 | 137.3 | 25.7x | 15.2x | 8.9x | *20.8* |
| nested | 1877.3 | 135.0 | 477.7 | 201.1 | 13.9x | 3.9x | 9.3x | *26.3* |
| loops | 1080.6 | 122.7 | 519.5 | 152.2 | 8.8x | 2.1x | 7.1x | *28.2* |
| options | 1943.1 | 87.1 | 111.4 | 219.8 | 22.3x | 17.4x | 8.8x | *23.1* |
| fields | 1379.2 | 63.1 | 79.9 | 212.7 | 21.8x | 17.3x | 6.5x | *23.1* |
| alloc | 1553.5 | 164.6 | 83.3 | 215.6 | 9.4x | 18.7x | 7.2x | *20.7* |
| arrays | 1484.1 | 93.7 | 163.0 | 197.4 | 15.8x | 9.1x | 7.5x | *43.7* |
| mapset | 947.5 | 17.6 | 86.9 | 106.3 | 53.8x | 10.9x | 8.9x | *34.1* |
| dispatch | 2217.1 | 90.3 | 149.2 | 216.8 | 24.5x | 14.9x | 10.2x | *22.2* |
| strings | 894.0 | 376.4 | 25.3 | 652.4 | 2.4x | 35.3x | 1.4x | *22.4* |
| strindex | 2547.0 | 2.6 | 18.5 | 14.7 | 987.2x | 138.0x | 173.8x | *17.2* |
| sorting | 768.9 | 578.9 | 818.9 | 396.1 | 1.3x | 0.9x | 1.9x | *555.4* |
| csv | 612.4 | 301.4 | 134.0 | 85.4 | 2.0x | 4.6x | 7.2x | *99.8* |
| **geomean** | | | | | **17.4x** | **12.4x** | **8.3x** | |

**START-UP IS ALREADY GOOD AND IS THE ONE COLUMN slate WINS.** 4.6 ms against node's 14.2 and
Python's 13.1, and only 2.8 ms behind Lua -- so a short program's wall time is mostly the work, and
nothing here is a start-up artefact. It also means the ratios above are honest at this size: at a
fifth of a second of Lua, start-up is under 1% of every figure but `strindex`'s.

**The spread matters more than the mean.** slate is within a factor of two and a half of Lua on
`sorting`, `csv` and `strings`, and thirty times off on `arith`, `funcs` and `fib`. The line between
those two groups is exactly whether the work happens inside a builtin or inside the instruction loop
-- which is what the profile below says in numbers.

## The profiler

**`SLATE_PROFILE=1 slate program.sl` writes a report to stderr**, leaving stdout exactly as it was,
so a profiled run can still be diffed against its expected output.

**An environment variable and not a flag, and that is forced by a decision already made**: everything
after a program's name on the command line belongs to the program (`main.sysl` says so), so slate has
no flag it could add without taking one a script had already claimed.

What it reports:

- **wall time**, by the same monotonic clock everything else here uses;
- **collections run, microseconds inside the collector, allocator steps and heap in use**;
- **calls and microseconds per BUILTIN**, heaviest first;
- **executions per instruction kind**, in a build that has them (below).

```
slate profile
  wall             1172731 us
  instructions     not counted in this build
  collections      1
  collector        26 us
  allocator steps  1
  heap in use      312840 bytes
  ...
  builtins, by time (7 of them)
    Map.set 2000000 calls 231745 us
```

### Instruction counts are behind `--features profile`, and the reason is a measurement

**Counting instructions needs a branch inside the instruction loop, and that branch is not free.**
Measured by alternating two binaries over this whole set, best of 5, twice:

| build | geomean against `dev` | worst benchmark |
|---|---|---|
| the branch live in the loop | **1.024x** | `arith` 1.081x |
| the same tree with the branch folded away | **0.999x** | -- |
| the shipped build, `profile` feature off | **1.001x** | `strindex` 1.014x |

The middle row is the control and it is what makes the first row a finding rather than build noise:
a tree carrying *every* other change -- the builtin timing hook, the collector hook, the whole
`profile.sysl` module, and whatever the code layout did -- measured 0.999, so the 2.4% is the one
line and nothing else.

So `CountingInstructions` is a build-time constant that `--features profile` sets, the optimiser
deletes the branch where it is false, and:

```
sysl build .                      # the shipped build: builtins, collector, allocator, heap
sysl build . --features profile   # all of that plus executions per instruction kind
```

**Everything else the instrument does is in every build**, because it costs 0.1% and a person
profiling their own installed slate should get it. Only the per-instruction count needs the rebuild,
and the report says so in words rather than printing a zero.

**The suite has a third shape because of this.** `sysl test . --features profile` runs the two tests
that assert the instruction counts are exact, beside the existing `sysl test .` and
`sysl test . --no-default-features`.

### What the counts are worth

- **A count is exact and a time is not.** Counting is an increment; timing is two readings of a
  microsecond clock, so a builtin taking a tenth of a microsecond measures as nought or one and only
  the total over many calls means anything.
- **A profiled run is a slower run** -- roughly 2x with instruction counting on, since every
  instruction hashes a name into a table. A builtin's microseconds are comparable to another
  builtin's; they are **not** a share of the unprofiled wall time in the table above. Read shares
  against `run.sh`'s numbers, which is what is done below.
- **A builtin that runs a slate callback is timed inclusively.** `map`, `filter`, `sort` and the rest
  run slate code inside the window being measured.

## What the first profile shows

Every benchmark run under `SLATE_PROFILE=1` with a `--features profile` build; instruction counts
and collector figures from that run, wall times from the table above.

### 1. slate runs 170 million instructions a second at best, and 60 million typically

| benchmark | instructions | ns per instruction |
|---|---|---|
| `arith`, `reals` | 250,000,036 | **5.9** |
| `arrays` | 191,000,788 | 7.8 |
| `dispatch`, `fields` | 215,000,040 / 135,000,043 | 10.3 / 10.2 |
| `funcs` | 136,000,040 | 11.3 |
| `methods`, `fib` | 159,000,087 / 176,789,492 | 15.5 / 15.9 |
| `globals`, `mapset` | 162,000,026 / 58,038,060 | 16.1 / 16.3 |
| `calls` | 74,000,059 | 21.1 |
| `csv` | 21,161,426 | 28.9 |

5.9 ns is about 20 cycles for a stack machine's fetch, dispatch and two operand pushes. **The
interesting number is not the floor, it is how few of those instructions do arithmetic.**

### 2. A quarter of every instruction executed is statement bookkeeping

Across all twenty benchmarks, 2,425,522,161 instructions:

| kind | count | share |
|---|---|---|
| `LoadSlot` | 436,021,964 | 18.0% |
| `BinaryOp` | 367,909,397 | 15.2% |
| **`PushNull`** | **249,873,013** | **10.3%** |
| `PushInt` | 209,243,568 | 8.6% |
| **`Discard`** | **173,086,793** | **7.1%** |
| **`Tick`** | **173,086,773** | **7.1%** |
| `StoreSlot` | 127,499,480 | 5.3% |
| `Jump` | 92,048,167 | 3.8% |
| `JumpIfFalse` | 90,655,045 | 3.7% |
| **`Pop`** | **90,356,320** | **3.7%** |
| `LoadName` | 64,376,880 | 2.7% |
| `JumpIfGiven` | 60,405,836 | 2.5% |

`arith`'s loop is the clearest reading of it -- **25 instructions per turn** for `total = total + i *
2 - 1` and `i = i + 1`:

```
BinaryOp 5   PushInt 4   LoadSlot 4   PushNull 3   Discard 2   Tick 2   StoreSlot 2
JumpIfFalse 1   Jump 1   Pop 1
```

**Eight of those twenty-five compute nothing**: every statement pushes a null that the next `Discard`
throws away, and every statement carries a `Tick` that asks the collector whether it is time. On
`arith` that is 32% of the instructions, and `arith` is the benchmark that is 30x off Lua.

### 3. A module-level loop allocates a scope every turn, and a function-level one allocates nothing

`globals.sl` and `arith.sl` are the same loop at two levels:

| | instructions | `PushScope` | allocator steps | collections | collector |
|---|---|---|---|---|---|
| `arith` (in a function) | 250,000,036 | 0 | **0** | **0** | 0 us |
| `globals` (at module level) | 162,000,026 | **6,000,000** | **5,998,601** | **4,285** | 46,042 us |

Six million iterations, six million `PushScope`/`PopScope` pairs, six million heap objects and four
thousand collections -- for a loop body that **declares no name at all**. The rule in `CLAUDE.md`
says a block pushes a scope only where it declares a name into one; a chunk that keeps its scope
appears not to be asking that question. **This reads as a gap rather than as a law**, and it is the
cheapest thing on this page to check.

### 4. `s.length` and `s[i]` are both O(n), so an ordinary character walk is quadratic twice over

`strindex` walks a 16,000-character string once. It is 987x Lua.

| | calls | microseconds | per call |
|---|---|---|---|
| `length` (the loop's own `i < s.length`) | 20,001 | 423,790 | **21.2 us** |
| everything else (the `s[i]` reads) | -- | ~2,100,000 | -- |

**21 microseconds to ask a 20,000-character string how long it is**, which is about a nanosecond a
character: `length` counts characters over UTF-8 every time it is asked. `s[i]` decodes from the
start every time it is asked. So `while i < s.length` is quadratic in the loop *condition* before the
body has done anything -- and the condition is the half nobody would think to look at.

### 5. Where slate is already close to Lua, the work is inside a builtin

| benchmark | wall | in one builtin | share | slate/lua |
|---|---|---|---|---|
| `sorting` | 768.9 ms | `sorted` 759,265 us | **99%** | **1.3x** |
| `mapset` | 947.5 ms | `Map.set` + `Set.add` 466,764 us | 49% | 53.8x |
| `csv` | 612.4 ms | `split` 205,517 us | 34% | 2.0x |
| `arrays` | 1484.1 ms | `length` 219,919 us | 15% | 15.8x |

**`sorting` is 1.3x Lua because the instruction loop runs 586,675 instructions in the whole
benchmark** and everything else is compiled sysl. That is the ceiling this design already reaches
when the loop is out of the way, and it is why the loop is where the work is.

`mapset` is the counter-example that says a builtin is not automatically fast: `Map.set` costs
**121 ns a call** against a Lua table store at roughly 4 ns, because slate's `Map` is the object's
own compact dict, hashing structurally and consulting a class's `==` and `hash`.

### 6. The collector is cheap except where one object's payload is most of the live set

| benchmark | collections | collector | share of wall |
|---|---|---|---|
| `strings` | **123,884** | 239,503 us | **27%** |
| `alloc` | 18,292 | 153,595 us | 9.9% |
| `csv` | 138 | 53,467 us | 8.7% |
| `calls` | 12,345 | 102,218 us | 6.5% |
| `globals` | 4,285 | 46,042 us | 1.8% |
| everything else | 0 to 130 | under 8,000 us | under 1% |

**`strings` collects 123,884 times for 150,000 iterations** -- five collections every six turns. The
schedule is `Headroom x` the live set and the live set is counted as cells **plus payload**; a
program whose live set is one 300 KB string plus the one it is building crosses its own threshold
every turn. The answers are right and the only symptom is speed, which is exactly the shape the
`live_size` fix was written for and a case it does not cover.

`alloc`'s 18,292 collections for three million short-lived objects, on the other hand, is the
schedule working: 9.9% of wall to take away 3,000,000 objects.

### 7. Calling a function by name costs a name lookup, and every parameter costs a branch

`funcs` calls `add3(i, 1, 2)` four million times:

| kind | count | per call |
|---|---|---|
| `LoadName` | 4,000,002 | **1** -- `add3` is a module-level definition, so it is looked up by name |
| `JumpIfGiven` | 12,000,000 | **3** -- one per parameter, to bind an absence where none arrived |
| `CallFn` / `Ret` | 4,000,002 | 1 each |

`JumpIfGiven` alone is 8.8% of everything `funcs` executes, and 2.5% across the whole set, on
functions that have no defaults at all.

## The ranked shortlist for 0.0.58 and after

Every line points at a number above. **Nothing here has been implemented** -- this release is the
instruments.

| # | change | reach | kind |
|---|---|---|---|
| 1 | **Stop emitting `PushNull`/`Discard` for a statement whose value nothing reads** | 17.4% of all instructions; 20% of `arith`, `reals`, `globals`, `funcs`, `fields`, `dispatch`, `closures` | INCREMENTAL |
| 2 | **Fix the module-level loop's per-turn scope** (finding 3) | `globals` only -- but it is 6M allocations and 4,285 collections for nothing, and every top-level script pays it | INCREMENTAL, and possibly a defect |
| 3 | **Make `Tick` cheaper or rarer** -- a counter tested every N statements, or folded into the back edge of a loop rather than emitted per statement | 7.1% of all instructions | INCREMENTAL |
| 4 | **Cache a string's character count on the `StrObj`, and index from a cached cursor** (finding 4) | `strindex` 987x -> ~2x; every `s.length` in every program; `arrays`'s 15% | INCREMENTAL |
| 5 | **Resolve a module-level definition's call target at compile time** so `add3(...)` is not a `LoadName` (finding 7) | 2.7% of all instructions, 2.9% of `funcs`, all of `globals`'s 14.8% `LoadName` | INCREMENTAL |
| 6 | **Emit `JumpIfGiven` only for a parameter that can be absent** at a call the checker has already counted (finding 7) | 2.5% of all instructions, 8.8% of `funcs` | INCREMENTAL |
| 7 | **Raise `Headroom` with the payload, or schedule payload separately from cells** (finding 6) | `strings` 27%; any program building text | INCREMENTAL |
| 8 | **Make `Map`/`Set` cheaper for scalar keys** -- skip the structural hash and the `==`/`hash` lookup where the key is an integer or a string | `mapset` 53.8x, the worst honest ratio here | INCREMENTAL |
| 9 | **A register machine instead of a stack machine** -- `LoadSlot` is 18.0% and `PushInt` 8.6%, and most of both exist only to feed the next instruction | 26.6% of all instructions, and it would take most of 1, 3 and 5 with it | **STRUCTURAL -- not piecemeal** |
| 10 | **A narrower `Value`, or NaN-boxing** | every instruction; nothing here measures it directly | **STRUCTURAL -- not piecemeal** |

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
