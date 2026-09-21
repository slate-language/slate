# What the first profile shows

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
eight are gone as of `fa327b6` — see *Statement bookkeeping removed* above — and **one of the two
`Tick`s went with item 3**: the loop keeps one at its top and neither of its statements carries one.

**AND `BinaryOp` NO LONGER EXISTS**, as of 2026-09-21: it was one instruction carrying the operator's
token and is now one instruction per operator, which took three switches on a compile-time constant
off **15.2% of every instruction executed** and **5.69%** off the geometric mean. The count in the
table is unchanged — the same instructions under twenty names — so nothing above it moved; the
section at the foot of this page has the numbers.

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

