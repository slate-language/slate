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

### `if`, `match` and `try` as statements — item 1's remainder, and `bench/` CANNOT SEE IT — 2026-09-20

Item 1 deliberately left these three alone: written as a statement, each still compiled as the
expression it is, so every branch produced a value — a `PushNull` where the branch had none — and
the far side of the join met a `Discard`. They are compiled to produce no value now, and the
language rule is unchanged: where somebody reads the answer they are the expressions they were.

**THE HEADLINE IS NOT A NUMBER, IT IS THAT NINETEEN OF THE TWENTY-TWO PROGRAMS HERE CONTAIN NO `if`,
`match` OR `try` AT ALL.** The three that do are `fib`, whose `if` is an expression on one line, and
`mapset`, `strindex` and `strwalk`, each of which writes one `if x then y` in a loop. So the exact
instruction counts, taken with `--features profile` on the two ends of one commit, are these — and
**seventeen of the twenty-two did not move by a single execution**:

| benchmark | before | after | change |
|---|---|---|---|
| `strindex` | 429,042 | 387,042 | **-9.8%** |
| `strwalk` | 443,042 | 400,042 | **-9.7%** |
| `mapset` | 50,030,044 | 50,027,044 | -0.006% |
| the other nineteen | — | — | **not one execution** |
| all twenty-two | 1,914,283,331 | 1,914,195,331 | -0.005% |

**So the timing run measures the machine and nothing else, and it is reported as such.** Best of 5
under `caffeinate`, box at 98.2% idle, no neighbour but `syslogd`, both locks held — the two that
could move and two controls, in milliseconds of process wall time:

| | before | after | lua |
|---|---|---|---|
| `arith` | 1253.8 | 1248.6 | 46.7 |
| `loops` | 934.2 | 941.3 | 117.1 |
| `mapset` | 806.3 | 808.0 | 16.6 |
| `strindex` | 11.4 | 11.1 | 2.4 |
| `strwalk` | 12.8 | 12.9 | 147.9 |

**The geometric means on this page are untouched**, no full run having been taken: an item whose
instruction counts are flat on nineteen programs cannot move a mean, and a mean re-measured from a
partial run would be a statement about the afternoon.

**WHAT IT IS WORTH IS MEASURED ON TWO PROGRAMS WRITTEN FOR IT**, each two million turns of a loop
with one construct in statement position. They are not benchmarks — they have no `.lua`, `.js` or
`.py` twin and no line in `expected.txt` — and they are reported here because they are the only
measurement of this item there is:

| probe | instructions before | after | change | wall before | wall after |
|---|---|---|---|---|---|
| an `if` with no `else` and an `if`/`else` | 72,666,695 | 63,666,695 | **-12.4%** | 1021.1 ms | **975.2 ms** (-4.5%) |
| a three-armed `match` | 64,000,020 | 60,000,020 | **-6.3%** | 897.5 ms | 899.2 ms (—) |

**The `match` probe is the honest half and says what these instructions are worth.** Four million
executions went and the clock did not move: a `PushNull` pushes a constant and a `Discard` pops one,
which are the two cheapest things the machine does, so a share of the instruction count is an upper
bound on the share of the time. The `if` probe moves because it loses a `Jump` per turn as well —
a branch with no `else` no longer has a null to jump over.

**THE GAP IS WORTH MORE THAN THE MEASUREMENT: THERE IS NO BENCHMARK HERE IN WHICH A PROGRAM MAKES A
DECISION.** Every one of the twenty-two is a straight-line loop, so this page cannot see this item,
cannot see item 3 (`Tick`), and would not see a branch-prediction or a dispatch change either. A
`branches` benchmark with its three twins would close it, and is not written here because the set
these means are taken over is shared and several items are measuring against it this week.

### `branches` — the missing benchmark that makes a decision, 2026-09-20

**Added because of the gap named directly above**: nineteen of the twenty-two programs here held no
`if`, `match` or `try` at all, so nothing on this page could see a branch misprediction, a `match`'s
arm search, or `Tick`'s cost against real control flow rather than a straight-line loop. `branches`
loops two million turns inside a function and every turn runs a bare `if`, an `if`/`elif`/`elif`/`else`
chain with a nested `if` inside one arm, an early `continue`, a five-armed `match` on a small integer,
an `if` used as an expression whose value is read, and — every thousandth turn — a `try`/`catch`
around a call that faults on a rare input. The input is a Park-Miller LCG written out in-program, so
all four twins walk the identical deterministic sequence and print the same checksum,
`1064937133`. Twins: `dispatch.lua`'s `if`-chain style for Lua's missing `match`, a `switch` for
JavaScript, Python's own `match`/`case`, `goto` for Lua's missing `continue`, and `pcall` / `try-except`
/ `try-catch` for the rare fault.

Taken 2026-09-20 on this machine, `slate` built from `dev` `6d0342b`, best of 5, under `caffeinate`,
both locks held, box at 85.66% idle before and 98.79% after, `pgrep -x java` empty (no neighbour).
Milliseconds of process wall time.

| | slate | lua | node --jitless | python | slate/lua | slate/node-jl | slate/py |
|---|---|---|---|---|---|---|---|
| `branches`, solo (`-n 5`) | 1345.8 | 100.7 | 312.1 | 388.7 | 13.4x | 4.3x | 3.5x |
| `branches`, in the full run | 1331.5 | 100.4 | 309.7 | 384.1 | 13.3x | 4.3x | 3.5x |

**The geometric mean, both ways, from the same run** (the previous twenty-two programs — the 21 timed
rows plus `startup` — against all twenty-three with `branches` added):

| | against lua | against node --jitless | against python3 |
|---|---|---|---|
| the previous twenty-two | 8.71x | 7.03x | 4.77x |
| all twenty-three, with `branches` | **8.88x** | **6.88x** | **4.70x** |

One benchmark added to a mean of twenty-one moves it by about the same tenth of one that the shortlist
items above already found — `branches` is 13.3x off Lua, near the middle of the existing spread, so it
nudges the mean rather than shifting it. **The value is not in this mean**: it is that a change to
`Tick`, to `match`'s arm search, or to branch prediction now has one place on this page to show up,
where before it had none.

### A string carries its own character count — shortlist item 4, `7478d4b`

Taken 2026-09-19 on this machine, best of 5, under `caffeinate`, box at 95.8% idle, `pgrep -x java`
empty, both locks held. **Both columns are binaries I built and kept**, and each is named: `0.0.57`
is `dev` at `e3ed5ff`, which is this branch's own starting point, and `item 4` is that same commit
with this change and nothing else on it. Measuring the two ends of one commit is what keeps the
figure this item's rather than the week's.

|  | 0.0.57 | item 4 | change | 0.0.57/lua | item 4/lua |
|---|---|---|---|---|---|
| `strindex` | 2506.1 | **13.2** | **190x faster** | 980.1x | **5.5x** |
| `strwalk` | 4830.8 | **15.0** | **322x faster** | 30.3x | **0.1x** |
| `strings` | 883.1 | 939.8 | — | 2.4x | 2.4x |

**`strings` did not move and the two figures either side of it say why.** Lua read 365.5 and 386.8 on
the same two runs, `node --jitless` 24.9 and 26.8, `python3` 625.6 and 646.8 — the whole second
column is about 5% up, which is the machine and not the build. The RATIO is 2.4x in both, and a
ratio is what this table is for: `strings` concatenates and never asks a position, so nothing here
reaches it.

**`strwalk` IS NEW AND IT IS THE HALF `strindex` COULD NOT SEE.** `strindex` walks ASCII, where a
character is one byte and a position can be arithmetic; `strwalk` walks 20,000 characters of
Japanese, where it cannot. **Lua is NOT the yardstick on that one** — it has no character indexing at
all, and the idiomatic `utf8.offset` counts from the front, so Lua's own walk is quadratic exactly as
slate's was. That is why the ratio reads 0.1x, and the twin's header says so.

**The whole set, with the merged build** (`dev` `a42c2f1` plus this item, so items 1 and 4 together):

| | against lua | against node --jitless | against python3 |
|---|---|---|---|
| the original twenty, 2026-09-18 | 17.4x | 12.4x | 8.3x |
| the original twenty, now | **12.4x** | **8.9x** | **5.9x** |
| all twenty-one, with `strwalk` | 9.9x | 7.9x | 5.4x |

**Of that 17.4 → 12.4, this item is 17.4 → 13.4** — substituting `strindex`'s new ratio into the
September 18 row and changing nothing else — and item 1 and run-to-run drift are the rest. The
twenty-one row is what `bench/run.sh` prints with no names given; the twenty is the comparable one,
and both are here so neither reading has to be worked out from the other.

**WHAT THE COUNT COSTS IS THREE WORDS PER STRING CELL AND NOTHING ELSE.** `StrObj` carries the
character count, the last position it was asked about and that position's byte offset. The count is
written when the cell is made and a string is immutable, so it can never go stale —
`new_str_counted(s, chars)` is the only constructor and takes the number as a parameter, which is
what stops a site forgetting it. Nearly every string is derived from one already counted (a join adds
two counts, a slice subtracts two positions, `repeat` multiplies, a literal is counted when it is
interned), so the one place a walk is owed is text arriving from outside the machine.

**`chars == bytes.len` IS THE TEST FOR "EVERY CHARACTER IS ONE BYTE"** and it falls out of keeping the
count rather than costing a flag. For such a string a position IS a byte offset. For one that is not,
the cursor makes a left-to-right walk cost one step per character instead of one walk per character —
**forward only, because the decoder counts a run of ill-formed bytes as one character and that rule
has no reverse**; a position behind the cursor is walked from the front with the same iterator that
did the counting, so the two can never disagree about where a character begins.

**The evidence that is not a clock is `Vm.chars_scanned`**, every byte the character-position
routines walk over, asserted in `tests_strcount.sysl`. Walking 20,000 one-byte characters by index
now reads **fewer bytes than the string is long**; the same walk over 20,000 three-byte characters
reads the string about once. Before this it was some 200,000,000 bytes for the first.

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

#### Re-measured over the WHOLE set, on the merged branch, 2026-09-19

The pair above measures this change alone against `0.0.57`, on four benchmarks. This one measures it
where it will actually land: both binaries were built in this session from the two ends of one merge,
so `dev` is **`67de3bf`** — which already carries items 1 and 4 — and `map-keys` is that same tree
with this change and nothing else on it. Best of 5, under `caffeinate`, holding both locks, box at
97.3% idle. Milliseconds of process wall time.

|  | dev `67de3bf` | map-keys | change | dev/lua | map-keys/lua |
|---|---|---|---|---|---|
| mapset | 902.0 | **799.3** | **-11.4%** | 54.0x | 46.1x |
| alloc | 1372.1 | **1236.5** | **-9.9%** | 8.0x | 7.8x |
| calls | 1516.8 | **1387.1** | **-8.6%** | 9.9x | 8.8x |
| funcs | 1433.8 | 1361.5 | -5.0% | 28.5x | 28.4x |
| fields | 1239.6 | 1196.4 | -3.5% | 19.8x | 19.3x |
| options | 1777.9 | 1716.7 | -3.4% | 21.1x | 21.0x |
| arith | 1293.2 | 1254.2 | -3.0% | 26.5x | 26.5x |
| fib | 2768.1 | 2688.9 | -2.9% | 34.1x | 33.2x |
| globals | 2320.5 | 2265.4 | -2.4% | 23.3x | 23.4x |
| loops | 957.6 | 937.0 | -2.2% | 8.0x | 7.7x |
| dispatch | 1963.3 | 1924.8 | -2.0% | 22.3x | 21.7x |
| methods | 2385.1 | 2339.6 | -1.9% | 16.2x | 16.8x |
| closures | 1121.0 | 1101.1 | -1.8% | 22.2x | 24.6x |
| nested | 1775.0 | 1748.7 | -1.5% | 13.5x | 13.5x |
| arrays | 1226.3 | 1208.1 | -1.5% | 13.1x | 12.9x |
| sorting | 759.3 | 751.9 | -1.0% | 1.3x | 1.3x |
| reals | 1274.1 | 1272.5 | -0.1% | 23.1x | 21.8x |
| csv | 568.9 | 569.7 | *+0.1%* | 1.9x | 1.9x |
| strings | 852.6 | 864.0 | *+1.3%* | 2.4x | 2.4x |
| strindex | 11.8 | 11.2 | -- | 5.0x | 4.7x |
| strwalk | 13.9 | 13.1 | -- | 0.1x | 0.1x |
| startup | 5.1 | 4.7 | -- | 2.7x | 2.8x |
| **geomean** | | | | **9.9x** | **9.7x** |

Against `node --jitless` the mean went **7.9x to 7.8x** and against `python3` **5.4x to 5.3x**.

**FOUR OF THESE HAVE A MECHANISM AND THE REST DO NOT, AND SAYING WHICH IS THE WHOLE VALUE OF THE
TABLE.** `mapset` is the hook lookup; `alloc` and `fields` are object literals no longer allocating an
index; and **`calls` is the one that was not predicted** — it builds two million `Counter` instances,
each of which used to take an eight-slot index before its one field was written, so the change moves
it as hard as it moves a benchmark about tables. `methods` declares a class too and moves far less,
its loop making one instance rather than one per turn.

**Everything under about 3% has no mechanism in this diff and should be read as code layout.**
`funcs` allocates nothing, holds no `==` and has no object in it, and it moved 5% in two independent
passes; `arith`, `fib`, `globals` and `loops` are the same case. A change to `obj.sysl` and
`table.sysl` moves every later function in the binary, and the instruction loop is sensitive to where
it lands. **Do not build an explanation for these rows.**

**THE ORDER THE TWO PASSES RAN IN WAS CONTROLLED FOR, and it had to be**: the whole set was measured
before-then-after, and a machine that quietens across twenty minutes buys the second pass a few
percent for nothing. Re-run with the binaries in the **opposite** order, `map-keys` still wins every
one, and Lua moved the other way in that pass (`calls` 159.5 ms beside `map-keys` against 154.7 beside
`dev`), which is the control saying the conditions favoured `dev` there:

| | map-keys (first) | dev (second) | change |
|---|---|---|---|
| mapset | **773.5** | 876.4 | **-11.7%** |
| alloc | **1202.6** | 1338.2 | **-10.1%** |
| calls | **1357.9** | 1456.5 | **-6.8%** |
| funcs | 1323.2 | 1389.0 | -4.7% |
| fields | 1166.5 | 1215.8 | -4.1% |

**START-UP IS ALREADY GOOD AND IS THE ONE COLUMN slate WINS.** 4.6 ms against node's 14.2 and
Python's 13.1, and only 2.8 ms behind Lua -- so a short program's wall time is mostly the work, and
nothing here is a start-up artefact. It also means the ratios above are honest at this size: at a
fifth of a second of Lua, start-up is under 1% of every figure but `strindex`'s.

**The spread matters more than the mean.** slate is within a factor of two and a half of Lua on
`sorting`, `csv` and `strings`, and thirty times off on `arith`, `funcs` and `fib`. The line between
those two groups is exactly whether the work happens inside a builtin or inside the instruction loop
-- which is what the profile below says in numbers.

### An ordinary call stopped copying its arguments — shortlist item 11, half of it, 2026-09-19

**EVERY CALL WITH AN ARGUMENT USED TO MALLOC.** `CallFn` copied each argument off the operand stack
into a fresh `Buf`, truncated the stack, and `lay_frame` pushed the very same values back on — at the
very cells they had just been standing in, because a frame's `base` *is* where the stack top is once
the callee and its arguments have come off. So a slate-to-slate call cost one malloc, one free and two
copies of every argument to move nothing anywhere.

**The ordinary positional call now leaves them where they stand.** `in_place_call` in `execute.sysl`
answers whether anything has to look at the arguments before the frame exists — a named call arranges
them against the parameter list, a spread call has them in an array, a variadic callee gathers its
surplus, an `async` or a generator carries them onto a machine of its own, and a chunk that is not
`slotted` binds its parameters by name. Where none of those is true the whole of the move is taking the
**callee** out from under its own arguments, one shift of `argc` cells; `lay_standing` then does what is
left, which is dropping a surplus, padding the rest of the window and setting the mask.

**A DELEGATED METHOD CALL MOVES NOTHING AT ALL.** The receiver is parameter zero and the target is
already sitting directly under the written arguments, so `base` is where it stands and there is nothing
to shift. A method found as the object's own field takes no receiver and is `CallFn`'s case again.

**It is also SAFER rather than merely faster.** A `Value` in a sysl local is not a root (`CLAUDE.md`
says why), and this path never takes one off the stack at all — where the buffered path holds the
window open between `invoke` and `lay_frame` on purpose.

Best of 5, under `caffeinate`, holding both locks, box at 93.6% idle. Both binaries built in this
session from the two ends of one merge, so `dev` is **`c31e658`** and `call-args` is that tree with this
change and nothing else on it. Milliseconds of process wall time.

|  | dev `c31e658` | call-args | change | dev/lua | call-args/lua |
|---|---|---|---|---|---|
| fib | 2676.7 | **1887.1** | **-29.5%** | 33.4x | 24.3x |
| funcs | 1352.2 | **1041.9** | **-22.9%** | 28.0x | 22.2x |
| closures | 1099.3 | **867.0** | **-21.1%** | 24.0x | 20.9x |
| nested | 1743.6 | **1427.4** | **-18.1%** | 13.4x | 11.1x |
| methods | 2343.5 | **1932.5** | **-17.5%** | 17.2x | 14.1x |
| dispatch | 1917.3 | **1605.1** | **-16.3%** | 21.6x | 17.9x |
| options | 1730.6 | **1498.6** | **-13.4%** | 21.1x | 18.7x |
| calls | 1384.1 | **1272.4** | **-8.1%** | 9.2x | 8.5x |
| strings | 868.8 | 857.4 | -1.3% | 2.4x | 2.4x |
| alloc | 1231.0 | 1216.6 | -1.2% | 7.5x | 7.7x |
| arrays | 1217.2 | 1207.5 | -0.8% | 13.4x | 13.1x |
| reals | 1235.6 | 1235.1 | 0.0% | 22.0x | 20.7x |
| loops | 940.7 | 940.7 | 0.0% | 7.9x | 7.9x |
| fields | 1186.7 | 1190.2 | *+0.3%* | 19.3x | 18.8x |
| arith | 1211.6 | 1228.9 | *+1.4%* | 26.0x | 25.6x |
| mapset | 799.7 | 811.7 | *+1.5%* | 45.0x | 48.3x |
| csv | 567.1 | 577.3 | *+1.8%* | 1.9x | 1.9x |
| globals | 2239.8 | 2300.0 | *+2.7%* | 23.1x | 22.4x |
| sorting | 754.4 | 790.3 | *+4.8%* | 1.3x | 1.4x |
| **geomean** | | | | **9.7x** | **9.0x** |

Against `node --jitless` the mean went **7.8x to 7.2x** and against `python3` **5.3x to 4.9x**.

**`fib` IS THE HONEST NANOSECOND FIGURE, BEING NOTHING BUT CALLS.** `fib(33)` makes 11,405,773 of
them, so 2676.7 ms is **234.7 ns a call** and 1887.1 ms is **165.5 ns** — **69 ns off every ordinary
positional call**, which is what one malloc, one free and two copies of one argument cost.

**`calls` MOVED LEAST OF THE CALL BENCHMARKS AND THE REASON WAS A FINDING.** Its loop makes two calls a
turn — `c.bump(1)`, which took the fast path, and `Counter(...)`, which did not: a constructor call is
an `Object` with a `new`, and `invoke` was what resolved that hook, so it went back to the buffered
path and paid what it always had. Half the calls in that benchmark were still allocating. **That half
was closed on `ctor-calls` the next day and the section below is its numbers**, so this paragraph is
kept only to say what the row above was measuring.

**THE FIVE ROWS THAT ROSE HAVE NO MECHANISM AND ONE OF THEM MIGHT.** `arith`, `globals`, `loops`,
`fields` and `reals` make no call this change can reach and moved within the band a code-layout shift
moves things (the `map-keys` section above states that rule and it holds here). `mapset` and `sorting`
are the two where a mechanism is *available*: both are builtin-dominated, and a builtin call now pays
one extra `Option` match and one counter increment on its way to the same buffer. Lua's own `sorting`
moved 564.7 to 568.6 and its `globals` 96.9 to 102.8 across the two passes, so the box drifted upward
under the second one — but `sorting` is +4.8% against a control that moved +0.7%, and that is reported
as a small real cost rather than as noise.

#### THE BUILTIN HALF IS THE REST OF ITEM 11 AND IT IS A BIGGER PIECE OF WORK THAN IT LOOKS

`NativeGo` is `&sync Fn(Buf[Value], Span) -> Step`, so **every builtin takes its arguments as a `Buf`
by the shape of the registry**. Handing one a VIEW of the operand stack instead — a start index and a
count, by index rather than by pointer, since a native that runs a callback pushes onto that same stack
— would take the malloc away and make `call_native`'s hold/release rooting unnecessary, the stack being
a root already. What it costs is the signature: **381 `register(...)` calls across 38 files and 1,083
`args.at(...)`/`args.len()` sites**. That is not a mechanical edit and it is its own item.

**`Vm.args_buffered` IS THE WITNESS AND IT IS A COUNT RATHER THAN A CLOCK**, which is
`Vm.chars_scanned`'s reason: an argument buffer is sysl memory rather than the collected heap, so the
allocator's own counters cannot see it and a benchmark can only say that a program got faster. Every
call that takes the buffered path charges it and `calls_buffered()` reads it, so `tests_slots.sysl`
asserts that ten thousand positional calls charge it **nothing** — and that a named call, a spread call,
a variadic callee and a builtin each charge it once per call, which is the negative control that makes
the first claim worth anything.

### A constructor call stopped copying its arguments — the other half of item 11, 2026-09-20

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

### A module's blocks are asked whether they declare anything — shortlist item 2, `de4e7c4`

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

### Cells and payload are two collection schedules — shortlist item 7, 2026-09-19

**One threshold over cells PLUS payload gave payload a smallest-worth-collecting of 256 KiB**, which
one medium string is already past — so a program whose live set is a string it is growing allocates
about as much per turn as it holds, crosses its own threshold every turn, and collects almost once a
statement whatever headroom it is given. `maybe_collect` in `obj.sysl` now compares each figure
against a threshold of its own: cells against `collect_above` over `CollectFloor` (256 KiB), payload
against `payload_above` over `PayloadFloor` (1 MiB), both raised to `Headroom ×` what survived, and a
collection either question asks for re-schedules both.

Taken on this machine, best of 3, under `caffeinate`, box at 97.6% idle, **both columns measured in
the same session**: `dev` is `9669959` and `item 7` is this branch on top of it. Only `strings`
moves; every other row drifted 2–5% slower across the session and so did lua's own column beside it,
which is the control saying that drift is the machine and not the change.

| | dev `9669959` | item 7 | change | lua (dev / item 7) |
|---|---|---|---|---|
| strings | 904.4 | **788.2** | **-12.8%** | 361.2 / 362.6 |
| alloc | 1218.3 | 1224.6 | *+0.5%* | 170.4 / 169.8 |
| csv | 577.9 | 592.4 | *+2.5%* | 298.8 / 302.7 |
| arith (control, no payload) | 1198.0 | 1266.4 | *+5.7%* | 46.4 / 47.8 |
| **geomean** | **8.8x** / 7.1x / 4.8x | **8.8x** / 7.1x / 4.8x | | |

**What the collector was actually doing is the number worth keeping**, and `SLATE_PROFILE=1` is where
it is read:

| | collections | collector | heap high water | peak RSS |
|---|---|---|---|---|
| `bench/strings`, dev | 123,925 | 233,424 us | -- | 14.3 MB |
| `bench/strings`, item 7 | **45,627** | **92,254 us** | 1.58 MB | 30.9 MB |
| `bench/alloc`, dev | 18,292 | 119,281 us | -- | 7.9 MB |
| `bench/alloc`, item 7 | **3,685** | 102,404 us | 1.00 MB | 8.7 MB |
| 200 dropped 1 MB buffers, dev | 200 | -- | -- | 11.0 MB |
| 200 dropped 1 MB buffers, item 7 | 200 | -- | 3.23 MB | 10.9 MB |

**`heap high water` is new on the report** — the largest cells-plus-payload `maybe_collect` ever saw
stand — because a COUNT of collections moves whenever the schedule is tuned and only the peak says
what the schedule let stand. `Vm.high_water` is what `tests_payload.sysl` pins.

**A 4 MiB payload floor was measured and REFUSED, and the refusal is the interesting half.**
`bench/strings` churns 22 GB of string copies over a live set of 383 KB: at 4 MiB it runs 10,964
collections in 761 ms (-16%) and peaks at **83.1 MB** resident, against 45,627 in 788 ms and 30.9 MB
at 1 MiB. Resident memory grows by far more than the floor — the dropped strings are every size the
program grew through — so the larger floor buys 4% of one benchmark for six times the memory, on a
language whose near work is a server holding a heap all day.

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

**FIXED — see *A module's blocks are asked whether they declare anything* above.** The finding is kept
because it is what the fix was chosen from, and because the shape of it recurs: a shortcut that reads
"this chunk cannot be asked the question" where the truth was "this chunk answers it differently".

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

**FIXED — see *A string carries its own character count* above.** The finding is kept because it is
what the fix was chosen from, and because the shape of it recurs: a position in one unit over storage
in another is where a language quietly becomes quadratic.

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

**ADDRESSED by shortlist item 7** -- payload is scheduled separately now, and `strings` collects
45,627 times for 12.8% less wall. The section above has the numbers and the memory it cost.

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

Every line points at a number above. **Five have landed since** — 1, 2, 4, 7 and 8, each struck
through with what it measured; the ranking of what is left is unchanged.

| # | change | reach | kind |
|---|---|---|---|
| 1 | ~~**Stop emitting `PushNull`/`Discard` for a statement whose value nothing reads**~~ — **DONE, `fa327b6`**: 20.6% of all instructions gone, `arith` -24.0%, geometric mean against Lua 17.6x -> **16.4x**. **Its remainder — `if`, `match` and `try` written as STATEMENTS — landed 2026-09-20 and `bench/` cannot see it**: nineteen of the twenty-two programs here hold no conditional at all, so the whole set moved 0.005% while a loop written around an unread `if` moved -12.4% | measured above | INCREMENTAL, and the set is what is missing |
| 2 | ~~**Fix the module-level loop's per-turn scope**~~ — **DONE, `de4e7c4`**: it WAS a defect. A module has no cells, and the `scoped_*` questions read `!e.cells` as "do not ask" rather than as "this chunk binds by name"; a module's blocks are asked `block_declares` now, guarded by the one binding form an expression can hide (`Emit.tests_bind`). `globals` 6,000,000 `PushScope`/`PopScope` pairs, 5,998,602 allocator steps and 4,288 collections all to **zero**, -14.8% wall, 21.8x -> **18.1x** Lua. **The three geometric means do not move** — one benchmark of twenty-two — and the win is in every top-level script instead | measured above | INCREMENTAL, and it was a defect |
| 3 | **Make `Tick` cheaper or rarer** -- a counter tested every N statements, or folded into the back edge of a loop rather than emitted per statement | 7.1% of all instructions | INCREMENTAL |
| 4 | ~~**Cache a string's character count on the `StrObj`, and index from a cached cursor**~~ — **DONE, `7478d4b`**: the count is CARRIED rather than cached, so `.length` is O(1) always; `strindex` 980x -> **5.5x** Lua (190x faster), the new `strwalk` 30.3x -> **0.1x** (322x faster), geometric mean against Lua over the original twenty **17.4x -> 13.4x** by this item alone | measured above | INCREMENTAL |
| 5 | **Resolve a module-level definition's call target at compile time** so `add3(...)` is not a `LoadName` (finding 7) | 2.7% of all instructions, 2.9% of `funcs`, all of `globals`'s 14.8% `LoadName` | INCREMENTAL |
| 6 | **Emit `JumpIfGiven` only for a parameter that can be absent** at a call the checker has already counted (finding 7) | 2.5% of all instructions, 8.8% of `funcs` | INCREMENTAL |
| 7 | ~~**Raise `Headroom` with the payload, or schedule payload separately from cells**~~ — **DONE, 2026-09-19**: payload is a schedule of its own, with a floor of its own, because a collection costs the OBJECT GRAPH and not the bytes. `strings` 123,925 collections -> **45,627** and 233 ms of collector -> 92 ms, **-12.8%** wall; `alloc` 18,292 -> 3,685. Peak RSS 14.3 MB -> 30.9 MB on `strings` and unchanged on a buffer-dropping program; a 4 MiB floor was measured (-16%, 83 MB) and refused. **The three geometric means do not move** — one benchmark of twenty-two | measured above | INCREMENTAL |
| 8 | ~~**Make `Map`/`Set` cheaper for scalar keys**~~ — **DONE, `06b2b6c`**: the hook lookup was two mallocs a call and is gone; a table under nine entries has no index. `mapset` 53.9x -> **49.1x**, `alloc` -6.8%, `fields` -2.4% | measured above | INCREMENTAL |
| 9 | **A register machine instead of a stack machine** -- `LoadSlot` is 18.0% and `PushInt` 8.6%, and most of both exist only to feed the next instruction | 26.6% of all instructions, and it would take most of 1, 3 and 5 with it | **STRUCTURAL -- not piecemeal** |
| 10 | **A narrower `Value`, or NaN-boxing** | every instruction; nothing here measures it directly | **STRUCTURAL -- not piecemeal** |
| 11 | **Make the CALL PATH cheaper** -- the argument `Buf` is a malloc per call, `Buf.at` retains and releases it on every read, and `methods_of` looks a method up by name every time | measured on `mapset` after item 8: ~208 ns of every turn is the loop and the call against ~49 ns of table work; `Buf.push`/`Buf.at`/`methods_of`/`call_native` are ~28% of that benchmark | **THE SLATE-TO-SLATE HALF IS DONE, `call-args` + `ctor-calls`**: an ordinary positional call allocates nothing (69 ns off every one of `fib`'s eleven million) and neither does a positional construction (59 ns off every one of `calls`'s two million). **The BUILTIN half is still owed**, and the section below says what it would take |

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
