# The table stopped hashing through a hook, and a small one stopped having an index — shortlist item 8, `06b2b6c`

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

