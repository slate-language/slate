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

### Statement bookkeeping removed — shortlist item 1, `fa327b6`

Taken 2026-09-19 on this machine, best of 5, under `caffeinate`, box at 91.3% idle, `pgrep -x java`
empty. **Both columns were measured in the same session**, so they are comparable to each other and
not to the table above: the `0.0.57` column is the installed release and `item 1` is `fa327b6` on
`unread-values`. Milliseconds of process wall time.

|  | 0.0.57 | item 1 | change | lua | 0.0.57/lua | item 1/lua |
|---|---|---|---|---|---|---|
| startup | 4.7 | 4.7 | -- | 1.8 | 2.6x | 2.6x |
| arith | 1488.4 | **1245.1** | **-16.3%** | 47.6 | 31.1x | 26.1x |
| reals | 1481.6 | **1258.8** | **-15.0%** | 57.7 | 25.6x | 21.8x |
| arrays | 1446.3 | **1216.9** | **-15.9%** | 92.5 | 15.9x | 13.2x |
| loops | 1056.8 | 942.8 | -10.8% | 119.4 | 8.8x | 7.9x |
| alloc | 1497.3 | 1358.0 | -9.3% | 160.0 | 9.6x | 8.5x |
| dispatch | 2125.9 | 1929.9 | -9.2% | 88.3 | 24.7x | 21.9x |
| closures | 1209.0 | 1098.8 | -9.1% | 45.0 | 28.8x | 24.4x |
| options | 1909.1 | 1751.3 | -8.3% | 84.9 | 23.7x | 20.6x |
| funcs | 1479.2 | 1365.6 | -7.7% | 47.4 | 30.4x | 28.8x |
| globals | 2468.1 | 2280.4 | -7.6% | 98.2 | 23.8x | 23.2x |
| fields | 1345.8 | 1257.2 | -6.6% | 60.9 | 21.7x | 20.6x |
| nested | 1843.9 | 1757.6 | -4.7% | 130.0 | 14.1x | 13.5x |
| mapset | 932.0 | 894.5 | -4.0% | 17.4 | 52.8x | 51.4x |
| fib | 2783.1 | 2679.5 | -3.7% | 79.6 | 34.5x | 33.6x |
| methods | 2411.2 | 2327.8 | -3.5% | 141.6 | 16.8x | 16.4x |
| csv | 588.2 | 568.8 | -3.3% | 297.7 | 2.0x | 1.9x |
| calls | 1516.9 | 1468.8 | -3.2% | 146.6 | 9.9x | 10.0x |
| sorting | 754.1 | 750.7 | -0.5% | 560.4 | 1.3x | 1.3x |
| strindex | 2471.9 | 2485.4 | *+0.5%* | 2.3 | 1045.6x | 1062.6x |
| strings | 858.4 | 872.9 | *+1.7%* | 359.0 | 2.4x | 2.4x |
| **geomean** | | | | | **17.6x** | **16.4x** |

Against `node --jitless` the mean went **12.5x to 11.6x** and against `python3` **8.2x to 7.7x**.

**THE THREE THAT MOVED LEAST ARE THE THREE WHOSE WORK IS INSIDE A BUILTIN**, which is finding 5
read from the other end: `strings`, `strindex` and `sorting` run almost no instructions per unit of
work, so taking instructions away buys them nothing and the two small rises are noise at this
sample size. The three that moved most — `arith`, `arrays` and `reals` — are the tight loops where a
quarter of every turn was bookkeeping.

**The instruction counts are exact and are the real evidence**, a time being a measurement and a
count an increment. With a `--features profile` build:

| benchmark | 0.0.57 | item 1 | change |
|---|---|---|---|
| `arith` | 250,000,036 | 190,000,026 | **-24.0%** |
| `loops` | 112,210,055 | 80,174,041 | **-28.6%** |
| `fields` | 135,000,043 | 105,000,033 | **-22.2%** |
| `funcs` | 136,000,040 | 112,000,028 | **-17.6%** |
| all twenty | 2,425,522,165 | 1,925,846,289 | **-20.6%** |

| kind, over all twenty | 0.0.57 | item 1 |
|---|---|---|
| `PushNull` | 249,873,014 | **35,076** |
| `Discard` | 173,086,794 | **4,577,096** |
| `Pop` | 90,356,320 | **9,028,080** |

**NO OTHER KIND MOVED BY A SINGLE EXECUTION, and that is checkable rather than asserted**: the fall
in those three sums to 499,675,876, which is exactly the fall in the total. `Tick` is unchanged at
every benchmark — it is still emitted once per statement, in the same place, and making it cheaper
is item 3.

**`arith`'s loop is 19 instructions a turn where it was 25.** What went is three `PushNull`, two
`Discard` and one `Pop`; what is left computes.

**An `if`, a `match` and a `try` written as statements are DELIBERATELY UNTOUCHED.** Each is
compiled as the expression it is wherever it stands, so both arms still leave a value and the
statement still drops one — three instructions per execution, paid once per `if` rather than once
per turn of anything. Teaching the arms to leave nothing needs its own argument about the two stack
depths meeting at the jump they share, and the benchmarks here do not ask for it: `dispatch`'s
`match` is a function's answer and is read. A **loop** written as a statement is untouched for the
same reason plus one more: `break` gives a loop a value, so the value is genuinely produced and the
one instruction that drops it is paid once per loop, not per turn.

### The table stopped hashing through a hook, and a small one stopped having an index — shortlist item 8, `06b2b6c`

Taken 2026-09-19 on this machine, best of 5, under `caffeinate`, box quiet. **Both columns were
measured in the same session against the same machine state**, so they are comparable to each other
and to nothing else: `0.0.57` is the installed release, which is `dev` `e3ed5ff`, and `item 8` is
`06b2b6c` on `map-keys` off that same commit — so this pair measures THIS change alone and does not
carry item 1's gain. Milliseconds of process wall time.

|  | 0.0.57 | item 8 | change | lua | 0.0.57/lua | item 8/lua |
|---|---|---|---|---|---|---|
| mapset | 925.6 | **834.3** | **-9.9%** | 17.2 | 53.9x | 49.1x |
| alloc | 1481.0 | **1380.5** | **-6.8%** | 157.0 | 9.4x | 8.6x |
| fields | 1349.7 | 1317.7 | -2.4% | 60.4 | 22.3x | 21.6x |
| csv | 592.6 | 594.9 | *+0.4%* | 294.3 | 2.0x | 2.0x |

Per call, read off `SLATE_PROFILE=1 slate bench/mapset.sl` (a profiled run is slower than a plain
one, so these compare only with each other):

| builtin | calls | 0.0.57 | item 8 | per call |
|---|---|---|---|---|
| `Map.set` | 2,000,000 | 232,357 us | 188,637 us | **116 -> 94 ns** |
| `Set.add` | 2,000,000 | 220,005 us | 177,023 us | **110 -> 89 ns** |
| `Map.get` | 1,000 | 116 us | 74 us | **116 -> 74 ns** |
| `Set.has` | 1,000 | 102 us | 71 us | **102 -> 71 ns** |

#### Where the 117 ns went, before anything was changed

Read with `sample` over an eight-second window of a twenty-million-turn `Map`/`Set` loop, 6,725
samples. **Almost none of it was the hash or the probe.**

| what | share | what it is |
|---|---|---|
| the allocator (`malloc`/`free`/`bzero`) | **~17%** | two mallocs per call, one freed immediately |
| `Buf.push<Value>` | ~14% | building those buffers |
| `Buf.at<Value>` | ~11% | reference-count traffic reading the operand stack and the argument buffer |
| `run_frames` + `Buf.at<Ins>` | ~17% | the instruction loop itself |
| `methods_of` | 3% | looking `set` up by name, once per call |
| `find_entry` + `Buf.at<Entry>` | ~4% | **the probe** |
| `hash_at` + `key_hash` | ~1% | **the hash** |

**The two mallocs per call were the finding.** `hash_value` asked `call_hook(v, "hash", …)` of every
key and `same` asked `call_hook(a, "==", …)` of every comparison — and `call_hook`'s first act is to
answer nothing for anything that is not an object. So an integer key built an argument buffer to ask
a question whose answer was already known, and the `==` one pushed a value into it, which is a
malloc and a free per probe. Asking only of an object is the whole of that half.

**The other half is that a table under nine entries now has no index at all.** One table serves
`Map`, `Set`, every object literal and every class instance, and `new_object` allocated an
eight-slot index before a single field was written — so `{ x: 1, y: 2 }` cost 64 bytes of index it
would never probe. Below `SmallTable` a lookup walks the entries comparing the hash each carries,
`obj_get_name` compares the name outright and never hashes it, and passing the line builds the index
once. That is Ruby's `Hash` up to eight and Scala's `Map1`..`Map4` up to four, and it is what moved
`alloc` and `fields`; `bench/mapset` holds a thousand keys and is helped by none of it.

After the change the allocator is **~5%** of the same loop and `same_in` and `call_hook` are off the
profile entirely.

#### AND THE REST OF `Map.set` IS THE BUILTIN CALL PATH, WHICH IS A DIFFERENT ITEM

What is left in the sample is the interpreter and the call, not the table: `Buf.at<Value>` 12%,
`Buf.push<Value>` 8% (the argument buffer, still one malloc per builtin call), `run_frames` and the
instruction fetch 17%, `methods_of` 3%, `call_native`/`run_native`/`takes_n`/`keepable` 5%.

Measured another way, against a control: a loop of four million `m.get(k % 1000)` runs in 1030.6 ms
and the same loop calling `abs(k)` instead runs in 833.0 ms. So **208 ns of every turn is the loop
and the call, and 49 ns is everything the table does** — the table is no longer where `mapset`'s
time is. That is shortlist item 11 below and is a bigger piece of work than this one.

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

*This section is the FIRST profile and is kept as the reading that chose the shortlist.* Six of those
eight are gone as of `fa327b6` — see *Statement bookkeeping removed* above — and the two `Tick`s are
item 3.

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
| 1 | ~~**Stop emitting `PushNull`/`Discard` for a statement whose value nothing reads**~~ — **DONE, `fa327b6`**: 20.6% of all instructions gone, `arith` -24.0%, geometric mean against Lua 17.6x -> **16.4x** | measured above | INCREMENTAL |
| 2 | **Fix the module-level loop's per-turn scope** (finding 3) | `globals` only -- but it is 6M allocations and 4,285 collections for nothing, and every top-level script pays it | INCREMENTAL, and possibly a defect |
| 3 | **Make `Tick` cheaper or rarer** -- a counter tested every N statements, or folded into the back edge of a loop rather than emitted per statement | 7.1% of all instructions | INCREMENTAL |
| 4 | **Cache a string's character count on the `StrObj`, and index from a cached cursor** (finding 4) | `strindex` 987x -> ~2x; every `s.length` in every program; `arrays`'s 15% | INCREMENTAL |
| 5 | **Resolve a module-level definition's call target at compile time** so `add3(...)` is not a `LoadName` (finding 7) | 2.7% of all instructions, 2.9% of `funcs`, all of `globals`'s 14.8% `LoadName` | INCREMENTAL |
| 6 | **Emit `JumpIfGiven` only for a parameter that can be absent** at a call the checker has already counted (finding 7) | 2.5% of all instructions, 8.8% of `funcs` | INCREMENTAL |
| 7 | **Raise `Headroom` with the payload, or schedule payload separately from cells** (finding 6) | `strings` 27%; any program building text | INCREMENTAL |
| 8 | ~~**Make `Map`/`Set` cheaper for scalar keys**~~ — **DONE, `06b2b6c`**: the hook lookup was two mallocs a call and is gone; a table under nine entries has no index. `mapset` 53.9x -> **49.1x**, `alloc` -6.8%, `fields` -2.4% | measured above | INCREMENTAL |
| 9 | **A register machine instead of a stack machine** -- `LoadSlot` is 18.0% and `PushInt` 8.6%, and most of both exist only to feed the next instruction | 26.6% of all instructions, and it would take most of 1, 3 and 5 with it | **STRUCTURAL -- not piecemeal** |
| 10 | **A narrower `Value`, or NaN-boxing** | every instruction; nothing here measures it directly | **STRUCTURAL -- not piecemeal** |
| 11 | **Make the BUILTIN CALL PATH cheaper** -- the argument `Buf` is a malloc per call, `Buf.at` retains and releases it on every read, and `methods_of` looks a method up by name every time | measured on `mapset` after item 8: ~208 ns of every turn is the loop and the call against ~49 ns of table work; `Buf.push`/`Buf.at`/`methods_of`/`call_native` are ~28% of that benchmark | INCREMENTAL, but it reaches `call_native`, `method.sysl` and `run_frames` together |

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
