# A sixth sampled profile: the head is seventeen instructions, and the arm term is back (dev `9d794de`, v0.1.3, sysl 0.0.127)

**THE DISPATCH HEAD IS 17 MACHINE INSTRUCTIONS, DOWN FROM PROFILE 5'S 22, AND IT IS NOW 30–47% OF
WHAT THE LOOP EXECUTES RATHER THAN 38–62%.** `narrow-ins` took the three spill reloads and the
`madd` by 56, `one-jump-table` took the second table, and what is left is one spill reload, a
bounds check that repeats the loop condition, a tag range check that cannot fail, a 32-byte fetch
and one indirect jump. **Roughly 12 points of weighted wall is fetch-and-decode**, against profile
5's ~14.

**AND FOR THE FIRST TIME IN FOUR PAGES THE ARM TERM OF THE FIT IS NOT ZERO.** `D = 0.36 ns, E =
1.56 ns`; the single-term figure is **1.44 ns per instruction**, from profile 5's 1.65. With the
head shorter, what an instruction *does* has started to show in what it costs — the programs whose
executions sit mostly in heavy inline arms (`CallFn`, `Ret`, `CallMethod`, `PushStr`) are the
expensive ones per instruction. **That is the argument for the shortlist below**: five of its
items are arms and allocations, not the head.

**THE LARGEST SINGLE FINDING IS A LITERAL.** `PushStr` makes a fresh string cell every time it
runs (`code.sysl` says so, beside `string_chars`), and a constructor's body is an object literal
whose keys are `PushStr`s. So **two of the three allocations in every `Counter(self.n + by)` are
the strings `"proto"` and `"n"`**, allocated, hashed, stored as keys and collected — `calls`
executes 4,000,007 `PushStr` for 2,000,003 `MakeObject`, `alloc` 6,000,000 for 3,000,001, and
the allocator counts agree to the step (below).

### How it was taken

**Identical to profiles 1–5 in instrument, stricter in the quiet check.** macOS `/usr/bin/sample`
at a 1 ms interval, each program started and sampled in one shell call, run serially under
`caffeinate -dimsu`. **The box was checked before EVERY program** —
`top -l 2 -n 0 -s 1` second sample ≥ 86% idle and `pgrep -x java` empty, waiting a minute and
re-asking otherwise — because other agents were building and benching on it the whole afternoon.
A first pass that checked only once, before the whole set, found a JVM running and the box at 57%
idle by its end; it was thrown away and every figure here is from the second.

- **The build is the release shape, and that shape is `-O2`, not `-O1`.** `sysl build .` reads
  `optimization = "2"` from `package.hocon` (it has since sysl 0.0.122). Dev `9d794de`, sysl
  **0.0.127**, `slate-plain`, 5,896,200 bytes.
- **LTO is not in this binary and cannot be.** sysl 0.0.127's `build` takes no `--lto` flag and no
  manifest key for it; LTO and PGO arrive with **sysl 0.0.128**. So this is the profile of the
  pre-LTO binary, and the shares below are the ones LTO starts from.
- **The same twenty of the twenty-three programs** — `startup`, `strindex` and `strwalk` exit
  before the sampler attaches. **5,769 main-thread samples** against profile 5's 6,519: the tree is
  about 11.5% faster in sampled wall.
- **Weights are each program's slate/CPython ratio from `bench/run.sh -n 5` on this binary, taken
  immediately after the samples on a box checked quiet (86.3% idle).** Geometric mean **2.7x Lua,
  2.1x `node --jitless`, 1.4x CPython, 1.7x qjs.**
- Counts are from a `--features profile` build of the same commit, `SLATE_PROFILE=1`.
- `sample` truncates its self table at 5 samples per name, and 91–716 samples per program means a
  single name on one program is good to about ±1.5 points. The weighted aggregate is the steadier
  number.

### (1) The dispatch head, now

`run_frames` is `0x10025fba8`–`0x100269660`, **39,608 bytes**. Fifty-two arms branch back to
`+0x1a0` unconditionally and twenty-one conditionally; from there:

```
+1a0  mov  x19, x21               pc = next
+1a4  cmp  x21, x23               pc against the code's length, held in a register
+1a8  b.hs <run_frames.cold.1>    a bounds panic with its message
+1ac  ldr  x8, [sp, #0x248]       spill reload -- the SAME length, a second copy
+1b0  cmp  x19, x8
+1b4  b.hs <brk #1>               the same bounds check again, which the line above has already answered
+1b8  add  x9, x14, x19, lsl #5   base + pc * 32
+1bc  ldr  w8, [x9]               the tag
+1c0  add  x21, x19, #0x1         pc + 1
+1c4  cmp  w8, #0x6e              tag > 110?
+1c8  b.hi <+1a0>                 a range check an exhaustive match cannot fail
+1cc  ldp  x24, x22, [x9, #0x8]
+1d0  ldr  x28, [x9, #0x18]       the 24 bytes of operands
+1d4  adr  x9, #-76
+1d8  ldrh w10, [x25, x8, lsl #1]
+1dc  add  x9, x9, x10, lsl #2
+1e0  br   x9
```

**Seventeen instructions, one table, one spill.** Against profile 5's twenty-two:

| what | profile 5 | now | note |
|---|---|---|---|
| spill reloads | 3 | **1** | `[sp,#0x248]`, the length again |
| bounds checks | 4 | **4** | two `cmp`/`b.hs` pairs of `pc` against the same length — one copy in `x23`, one spilled — neither of which can fail on generated code; **the second pair and its reload repeat a comparison already made** |
| the `Ins` fetch | 5 | **4** | `lsl #5` for a 32-byte `Ins`, the tag, one `ldp` and one `ldr` |
| the indirect jump | 10 | **8** | including a 2-instruction tag range check whose `b.hi` goes back to the loop top |

**`Step` is 64 bytes again and the head cannot show it**, because `Step` is what `run_frames`
*returns* and the head never touches it. The head's count is the confirmation that `signal-slim`
did not regress the loop itself (17 against `narrow-ins`' 18 — `one-jump-table`'s second table
went in between); `Step`'s width is confirmed by `signal-slim`'s own IR reading, `{ i32, [7 x i64] }`.

**The two removable pieces are a sysl codegen question, not a slate one.** A `match` over every
variant of `Op` lowers to a switch whose default is reachable (`b.hi` to the loop top), and
the fetch checks `pc` against the code's length twice, from two copies of it. An
`unreachable` default and a loop-invariant bounds check are both things LLVM does when told; five
of seventeen instructions are at stake. **Reported as a finding for sysl, not worked around.**

### The head against the arms

Arm length is read from the jump table exactly as profile 5 did: the 111 16-bit entries at
`0x1003b54b8` from the `adr` base `0x10025fd30`, each arm walked from its entry to its first
unconditional exit, weighed by the executed mix. The four `fused_*` arms are a call stub in the
loop plus a body outside it; the stub is counted as their arm.

| program | executed | head | arm / insn | **head share** | out-of-line share |
|---|---|---|---|---|---|
| branches | 121,451,942 | 17 | 18.9 | **47.4%** | 36.8% |
| globals | 102,000,020 | 17 | 19.4 | **46.8%** | 5.9% |
| arith | 130,000,025 | 17 | 20.2 | **45.7%** | 38.5% |
| reals | 130,000,027 | 17 | 20.2 | **45.7%** | 38.5% |
| arrays | 91,000,521 | 17 | 20.6 | **45.3%** | 46.7% |
| dispatch | 140,000,026 | 17 | 20.8 | **44.9%** | 21.4% |
| loops | 64,138,039 | 17 | 21.0 | **44.8%** | 25.0% |
| fields | 75,000,032 | 17 | 22.3 | **43.2%** | 33.3% |
| mapset | 34,015,042 | 17 | 26.1 | **39.5%** | 35.3% |
| options | 86,000,037 | 17 | 26.2 | **39.3%** | 16.3% |
| funcs | 72,000,027 | 17 | 27.6 | **38.1%** | 38.9% |
| methods | 111,000,068 | 17 | 28.1 | **37.7%** | 18.9% |
| alloc | 57,000,025 | 17 | 28.3 | **37.5%** | 36.8% |
| closures | 60,000,033 | 17 | 29.5 | **36.6%** | 40.0% |
| fib | 119,760,624 | 17 | 31.2 | **35.3%** | 28.6% |
| nested | 84,108,048 | 17 | 33.5 | **33.7%** | 21.4% |
| calls | 48,000,046 | 17 | 36.5 | **31.8%** | 20.8% |
| csv | 14,340,921 | 17 | 39.6 | **30.0%** | 17.6% |

**Head share 30.0–47.4%, median about 39%**, from profile 5's 38–62% and median 46%. `run_frames`
is 30.70% of weighted wall, so the head is **~12 points**. The arms that dominate the
straight-line lengths are the call and construction ones: `CallFn` **128**, `Ret` **97**,
`CallMethod` 92, `PushStr` **82**, `MakeClosure` 125 — against `LoadSlot` 6, `Jump` 2, `Tick` 7,
`Add` 43. (A straight-line walk overstates a branchy arm whose cold path falls through; read these
as the order of magnitude the arm costs, which is what the ranking needs.)

### The aggregate

| self time | unweighted | weighted | profile 5 wtd | what it is |
|---|---|---|---|---|
| `run_frames` | 32.89% | **30.70%** | 30.93% | the loop |
| `fused_load_slot_int` | 4.29% | **3.68%** | 2.46% | out of line |
| `_platform_memmove` | 4.51% | 3.29% | 2.50% | 84.5% of `strings` |
| `placed_call` | 2.62% | **2.91%** | 2.67% | the call question |
| `fused_add_store_slot` | 3.26% | 2.73% | 2.43% | out of line |
| `merge_sort` | 2.86% | 2.36% | 1.88% | 57.2% of `sorting` |
| `fused_load_slot2` | 2.69% | 2.04% | 1.45% | out of line |
| `read_field_site` | 2.19% | **2.04%** | 0.61% | now carries the own-field hit `field_here` used to |
| `multiplied` | 2.28% | 1.90% | 1.07% | `Mul`'s arm |
| `maybe_collect_on` | 1.93% | **1.79%** | 1.04% | the safe point — 5.1% of `fib`, 7.1% of `arrays` |
| `_tlv_get_addr` | 1.31% | 1.72% | 1.11% | `current()` from natives: 5.1% `mapset`, 4.6% `csv` |
| `gc.collect` | 0.98% | 1.58% | 1.46% | |
| `gc.take` | 0.92% | 1.48% | (`gc.alloc` 2.06%) | the allocator, renamed in gc 0.2.5 |
| `match_leaf` | 1.31% | 1.44% | 2.07% | 21.6% of `dispatch` |
| `_xzm_free` | 1.17% | 1.41% | 1.59% | |
| `fused_less_jump_if_false` | 1.63% | 1.38% | 0.65% | out of line |
| `added` | 1.64% | 1.37% | 1.07% | `Add`'s arm |
| `_platform_memset` | 0.81% | 1.15% | 1.06% | the collector zeroing a payload |
| `gc.rebuild_free` | 0.68% | 1.12% | 0.50% | |
| `find_entry` | 0.69% | 0.94% | 0.93% | 9.5% of `mapset` |
| `lay_standing` | 0.79% | 0.92% | 0.82% | |
| `methods_of` | 0.57% | **0.77%** | 0.58% | 11.4% of `mapset` |
| `keepable_on` | 0.74% | 0.77% | — | the `undefined` check at a call |
| `Buf.grow<Entry>` | 0.56% | 0.76% | — | a new object's first entry — 7.1% of `alloc` |
| `Buf.at<string>` | 0.72% | 0.76% | — | a name read out of `Unit.strings` |
| `obj_get_name` | 0.55% | 0.75% | — | 9.5% of `options` |
| `obj_put` | 0.54% | 0.74% | — | |

**Rolled up, weighted:**

| group | weighted | profile 5 | in it |
|---|---|---|---|
| **the loop + the four fused arms** | **40.53%** | 37.92% | `run_frames` 30.70 + fused 9.83 |
| **of which the head** | **~12 points** | ~14 | 39% of `run_frames` from the table above |
| **allocation, the collector and malloc** | **10.68%** | 7.78% (narrower list) | take 1.48, collect 1.58, `maybe_collect_on` 1.79, memset 1.15, bzero 0.61, `rebuild_free` 1.12, mark/trace 0.48, `_xzm_free` 1.41, malloc 0.30, `Buf.grow<Entry>` 0.76. On profile 5's own list it is **8.21%** |
| **field and method lookup** | **6.19%** | 4.43% | `read_field_site` 2.04, `find_entry` 0.94, `methods_of` 0.77, `Buf.at<string>` 0.76, `obj_get_name` 0.75, `field_from_site` 0.70, `write_named_at` 0.23 |
| **the call path** | **4.60%** | 5.16% | `placed_call` 2.91, `lay_standing` 0.92, `keepable_on` 0.77 |
| **the pattern matcher** | **2.91%** | 3.86% | `match_leaf` 1.44, `unpacked_fixed` 0.65, `match_walk` 0.41, `compose_unpack_slots` 0.31, `pattern_names` 0.10 |
| **constructing an object** | **1.59%** | not grouped | `obj_put` 0.74, `compose_object` 0.43, `hash_at` 0.29, `key_hash` 0.13 |
| **`Map<string,*>` and `lookup`** | **1.35%** | 1.78% | a name read by spelling |
| **`_tlv_get_addr`** | **1.72%** | 1.11% | |

**Every group except the call path and the matcher ROSE as a share, and nothing rose in absolute
terms** — the denominator is 11.5% smaller, and the dispatch items that landed took it out of the
loop. `for-head` shows as the matcher falling 3.86 → 2.91.

### Per program, the top five

| benchmark | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| arith | `run_frames` 48.9 | `subtracted` 9.7 | `fused_load_slot_int` 9.1 | `multiplied` 6.5 | `fused_less_jump_if_false` 5.9 |
| reals | `run_frames` 40.4 | `arith()` 12.5 | `fused_load_slot_int` 10.6 | `real_arith` 7.8 | `fused_load_slot2` 5.1 |
| globals | `run_frames` 15.1 | `_xzm_free` 11.6 | `<deduplicated_symbol>` 9.5 | `Map.put<string,Value>` 9.2 | `__bzero` 7.0 |
| funcs | `run_frames` 53.8 | `placed_call` 11.2 | `fused_load_slot_int` 9.1 | `lay_standing` 5.6 | `added` 3.5 |
| fib | `run_frames` 60.4 | `placed_call` 8.6 | `maybe_collect_on` 5.1 | `subtracted` 4.8 | `fused_load_slot_int` 4.3 |
| calls | `run_frames` 24.7 | `gc.take` 5.0 | `placed_call` 4.4 | `gc.collect` 4.1 | `Buf.grow<Entry>` 4.1 |
| methods | `run_frames` 41.6 | `read_field_site` 14.1 | `field_from_site` 11.2 | `multiplied` 6.6 | `added` 4.4 |
| closures | `run_frames` 39.1 | `fused_add_store_slot` 9.8 | `fused_load_slot_int` 9.8 | `lookup` 6.8 | `placed_call` 6.8 |
| nested | `run_frames` 50.2 | `fused_load_slot2` 8.3 | `multiplied` 6.7 | `placed_call` 6.7 | `fused_add_store_slot` 5.9 |
| loops | `run_frames` 52.7 | `multiplied` 13.2 | `unpacked_fixed` 12.1 | `fused_load_slot2` 8.8 | `fused_add_store_slot` 7.7 |
| options | `run_frames` 28.6 | `obj_get_name` 9.5 | `match_walk` 6.3 | `<deduplicated_symbol>` 5.3 | `_xzm_free` 5.3 |
| fields | `run_frames` 36.6 | `read_field_site` 21.8 | `added` 9.9 | `write_named_at` 7.7 | `fused_load_slot2` 4.9 |
| alloc | `run_frames` 14.1 | `Buf.grow<Entry>` 7.1 | `read_field_site` 5.6 | `gc.collect` 5.6 | `fused_load_slot_int` 5.4 |
| arrays | `run_frames` 27.9 | `fused_add_store_slot` 15.3 | `fused_load_slot2` 15.3 | `maybe_collect_on` 7.1 | `properties_of` 3.8 |
| mapset | `run_frames` 17.1 | `methods_of` 11.4 | `find_entry` 9.5 | `standing_native` 6.3 | `_tlv_get_addr` 5.1 |
| dispatch | `run_frames` 43.5 | `match_leaf` 21.6 | `compose_test_slots` 5.5 | `placed_call` 4.8 | `fused_load_slot_int` 4.5 |
| branches | `run_frames` 54.3 | `fused_load_slot_int` 13.9 | `compose_test_slots` 8.1 | `remainder_of` 5.4 | `fused_less_jump_if_false` 4.5 |
| sorting | `merge_sort` 57.2 | `arith()` 15.0 | `int_arith` 12.3 | `on_values` 8.7 | `copy_of` 2.2 |
| csv | `gc.collect` 9.8 | `run_frames` 8.8 | `gc.take` 8.2 | `gc.rebuild_free` 6.7 | `_tlv_get_addr` 4.6 |
| strings | `memmove` 84.5 | `trace_env` 5.2 | `mach_absolute_time` 2.0 | `mark_value` 1.8 | `__vfprintf` 1.0 |

### (2) What `calls` and `csv` allocate, and from where

**`calls` (2.9x CPython): three allocations per `c.bump(1)`, and two of them are string literals.**
`SLATE_PROFILE` counts **5,997,568 allocator steps for 2,000,000 turns — 3.0 each** — and the
instruction mix names them: `PushStr` 4,000,007, `MakeObject` 2,000,003, with the pairs
`PushStr LoadCell` and `PushStr LoadSlot` at 2,000,001 each. The path is `CallMethod bump` →
`CallFn Counter(…)` → `ctor-calls`' in-place `new` → the generated constructor's body, which is an
object literal: **`PushStr "proto"`, `LoadCell Counter`, `PushStr "n"`, `LoadSlot`, `MakeObject 2`,
`Ret`**. So per construction:

| allocation | where | constructor path |
|---|---|---|
| a `StrObj` for `"proto"` | `PushStr` arm, `run_frames.sysl:204` → `str_counted` → `new_str_counted` | **a key literal, rebuilt every call** |
| a `StrObj` for `"n"` | the same | **the same** |
| the `ObjectObj` | `compose_object` (`run_compose.sysl:54`) → `new_object` | the one that is the answer |
| **a `malloc`** for the entries | `obj_put` → `entry_push` → `Buf.grow<Entry>` from capacity 0, freed at the finalizer (`_xzm_free`) | outside the collector's count |

What it costs on `calls`: the collector and allocator (`gc.take` 5.0, `gc.collect` 4.1,
`rebuild_free` 3.8, `memset` 3.8, `maybe_collect_on` 1.9) **18.6%**, malloc/free around the
entries (`Buf.grow<Entry>` 4.1, `_xzm_free` 2.5, `malloc_tiny` 2.2) **8.8%**, and building the
object (`obj_put` 2.8, `compose_object` 1.9, `hash_at` 1.9, `key_hash` 1.6, `find_entry` 1.6)
**9.8%** — each key is hashed at run time although `Unit.string_hashes` already holds its hash.
**That is 37% of `calls`**, and `PushStr`'s own arm is 82 machine instructions, 15.4% of what the
loop executes on this program. **`alloc` is the same shape exactly**: 8,997,559 steps for 3,000,001
objects, `PushStr` 6,000,000.

**`csv` (3.1x CPython): 6.2 allocations per line, and one of them is a literal.** 3,722,107 steps
over 600,000 lines. `line.split(",")` makes three strings and an array, the outer `split("\n")`
made the line — five that are the program's data — and **`PushStr ","` is 640,031 executions, one
per line**, a sixth cell for text that never changes. The collector is the largest thing in the
program (`gc.collect` 9.8, `gc.take` 8.2, `rebuild_free` 6.7, memset 3.6, bzero 2.6, `mark_value`
2.6 — **33.5%**), so the literal is about a sixth of a third. The other csv finding is the name path:
**`LoadName` is 1,280,001 executions, 8.9%**, every one `number` looked up by spelling through the
scope chain — a builtin's name is never resolved at compile time the way `LoadDef` resolves the
file's own. And **`_tlv_get_addr` is 4.6%**: `current()` asked from inside the natives.

### (3) What `methods` (2.1x) still pays

**`methods_of` is not on `methods` at all** — `a.dot(b)` finds a *class* method, and that is the
inline-cache path: `read_field_site` **14.1%**, `field_from_site` **11.2%**, `Buf.at<string>`
**2.5%** — **27.8% of the program**, 6,000,000 `CallMethod` all hitting through `proto`. Reading
`site_cache.sysl:93–200`, a proto hit does:

1. `read_field_site` asks `field_here(o, site.own, …)` — the own-field guess, which misses;
2. `field_from_site` asks **the same `field_here` again** and misses again;
3. `obj_index_hashed(o, name, h)` **scans the instance's own table** (three entries) to prove the
   name is not an own field — a miss, so it scans all of them;
4. `field_here(o, site.hop, "proto", …)`, then `field_here(p, site.up, name, …)` — the hit;
5. **`name != "new"`**, a string comparison, on every hit;
6. and `u.strings.at(k)` has retained and will release the name string.

Only step 4 is the answer. **`methods_of` is `mapset`'s** (2.3x): `s.add(x)` and `m.set(k, v)` on
a builtin kind go `builtin_receiver` → `builtin_method` → `methods_of(kind, name)`, which matches
the **kind as a string and the name as a string** on every call — **11.4%** of `mapset`, with
`standing_native` 6.3 and `_tlv_get_addr` 5.1 beside it.

### (4) What `fib` (2.2x) and `funcs` (1.4x) pay in the call and return arms

| | `fib` | `funcs` |
|---|---|---|
| `CallFn` + `Ret` share of **executions** | 19.0% | 11.1% |
| their share of the loop's **machine instructions** (head + arm) | **51.2%** | **32.3%** |
| `placed_call` | 8.6% | 11.2% |
| `lay_standing` | 3.7% | 5.6% |
| `keepable_on` | 1.6% | 3.5% |
| `maybe_collect_on` (the chunk-entry safe point) | 5.1% | — |

**On `fib` the call and return are about half of `run_frames`' 60.4% plus 19% outside it — 50% of
the program.** `CallFn`'s inline arm is 128 instructions straight-line and `Ret`'s 97. Two things
in them that are not the call's work: **`Frame` carries `code: Buf[Ins]`** (`vm.sysl:19`), a
counted buffer, so every push copies one in and every `Ret` copies one out and drops the frame's —
reference-count traffic on the one hot path where the chunk index already names the code (read off
the source; the IR is what should confirm it); and the **`keepable_on` loop over the arguments**,
the `undefined` refusal asked of every argument at run time, which a compile-time proof could skip
where an argument is a literal or an arithmetic result.
**`Tick` is 19.0% of `fib`'s executions** — the expression-bodied safe point — and
`maybe_collect_on` behind it another 5.1%.

### (5) The superinstruction pairs, by count

Pairs from the `--features profile` build, as a share of every instruction the program executed;
"mean" is over the twenty programs above a million instructions.

| pair | where it matters | mean |
|---|---|---|
| **`Tick` + anything** | `Tick` is 1.6–19.0% of executions on every program (fib 19.0, nested 14.2, closures 13.3, calls 12.5, loops 12.4, options 11.6, arrays 11.5, funcs 11.1); **`Tick LoadSlotInt` is the top pair on nine programs** | `Tick LoadSlotInt` **4.03%**, `Tick LoadSlot` 1.69%, `Tick IterNext` 1.54% |
| **`LoadSlot GetField`** | methods **16.2**, fields **13.3**, alloc 5.2, calls 4.1 | 2.05% |
| **`GetField LoadSlot`** | methods 10.8, fields 6.6, calls 4.1 | 1.14% |
| **`TestSlots JumpIfFalse`** | dispatch **12.4**, branches 4.8 | — |
| **`LoadCell PushInt`** | globals **17.6** | — |
| **`PushInt Rem`** | mapset **11.7**, dispatch 3.5, sorting 6.5 | — |
| **`CallMethod Discard`** | mapset 11.7 | — |
| **`Sub CallFn`**, **`LoadDef LoadSlotInt`** | fib 9.5 each, funcs 5.5 | — |
| `Mul Add` | reals 7.7 | 1.40% |
| `UnpackFixed LoadSlot2`, `IterNext UnpackFixed` | loops 12.5, nested 7.1 | 1.03% each |

**`Tick` is the one to read twice.** It is 7 arm instructions behind a 17-instruction head, so each
costs 24 to say "no collection due" — and it is the first half of the heaviest pair on nine
programs. Folding the safe point into the instruction after it (or into the backward `Jump` and
the call arm, which are where a loop and a recursion actually come round) takes the head off every
one of them.

### (6) `mapset` and `options`

**`mapset` (2.3x)**: `run_frames` 17.1, **`methods_of` 11.4**, **`find_entry` 9.5**,
`standing_native` 6.3, `_tlv_get_addr` 5.1, `obj_put` 3.2. Half of it is finding the builtin by
name (item 6 below) and a third is the table's own probe, which is the table doing its job.

**`options` (2.2x)**: `run_frames` 28.6, **`obj_get_name` 9.5**, **`match_walk` 6.3**,
`<deduplicated_symbol>` 5.3, `_xzm_free` 5.3, `compose_unpack_slots` 4.8, `match_leaf` 4.5,
`Buf.grow<string>` 3.3, **`pattern_names` 1.5**. The program is `val { width = 10, height, scale = 2
} = opts`, and **a DEFAULT is exactly what `for-head`'s `UnpackFixed` refuses** — so it goes
`UnpackSlots` → the matcher, which **builds the pattern's name list at run time on every call**
(`pattern_names`, `Buf.grow<string>`, `Buf.push<string>`, the malloc and the free), looks each key
up by spelling (`obj_get_name`), and binds through `JumpIfSet` (9.3% of executions). **About 40% of
`options` is the matcher doing what a fixed-shape instruction would do in three reads.**

### Per instruction, and the fit

`ns per instruction` is `run_frames`' self share of the `run.sh` wall divided by every instruction
executed; **inline share** is the executions whose arm is inside the loop.

| program | instructions | `run_frames` self | ns / instruction | inline share |
|---|---|---|---|---|
| fib | 119,760,624 | 60.4% | **2.43** | 71.4% |
| branches | 121,451,942 | 54.3% | **1.55** | 63.2% |
| funcs | 72,000,027 | 53.8% | **1.61** | 61.1% |
| loops | 64,138,039 | 52.7% | **1.53** | 75.0% |
| nested | 84,108,048 | 50.2% | **2.15** | 78.6% |
| arith | 130,000,025 | 48.9% | **0.98** | 61.5% |
| dispatch | 140,000,026 | 43.5% | **1.27** | 78.6% |
| methods | 111,000,068 | 41.6% | **1.61** | 81.1% |
| reals | 130,000,027 | 40.4% | **1.07** | 61.5% |
| closures | 60,000,033 | 39.1% | **1.38** | 60.0% |
| fields | 75,000,032 | 36.6% | **1.07** | 66.7% |
| options | 86,000,037 | 28.6% | **1.74** | 83.7% |
| arrays | 91,000,521 | 27.9% | **0.80** | 53.3% |
| calls | 48,000,046 | 24.7% | **2.09** | 79.2% |
| mapset | 34,015,042 | 17.1% | **1.22** | 64.7% |
| globals | 102,000,020 | 15.1% | **1.02** | 94.1% |
| alloc | 57,000,025 | 14.1% | **1.13** | 63.2% |
| csv | 14,340,921 | 8.8% | **1.68** | 82.4% |

**`D = 0.36 ns, E = 1.56 ns`; the single-term figure is 1.44 ns** (profile 5: `D = 1.67, E =
−0.03`, single 1.65). Three pages found no arm term because a 22-instruction head everybody paid
drowned whatever the arm did. With the head at 17 and the fused arms back out, the programs whose
work is in long inline arms — `fib`'s and `calls`' `CallFn`/`Ret`, `options`' `JumpIfSet`,
`nested`'s `IterNext` — are the ones at 2 ns and over, and `arith`/`arrays`, whose inline arms are
short, are under 1. **The fit is loose** (`globals` at 94% inline and 1.02 ns is the outlier: its
inline arm is `LoadCell`, 22 instructions), and it should be read as a direction: **the arms are
where the next items are.**

### The re-ranked shortlist

Share is the weighted aggregate unless a program is named. A ceiling is what the geometric mean
over the twenty-three would move if the item removed ALL of the named cost — a program losing a
share `s` moves the mean by about `ln(1 − s) / 23`. **None will take its whole ceiling.** Items
already queued are marked; their numbers are the ones above.

| rank | candidate | measured share | ceiling | files |
|---|---|---|---|---|
| **1** | **A STRING LITERAL IS ONE CELL, NOT ONE PER EXECUTION** — intern the `StrObj` per `Unit` string at compile/load time, rooted by the unit, and have `PushStr` push it. Immutable, carries its count already; the cursor is a benign cache. **Then an object literal with literal keys needs no key cells at all**: a `MakeObject` variant carrying the key indices takes the hash from `string_hashes` and sizes `entries` to `n` up front, which removes `key_hash`/`hash_at` and the `Buf.grow<Entry>` malloc. **QUEUED as the calls/csv allocation item** | `calls` **37%** (18.6 collector + 8.8 malloc + 9.8 construction), `alloc` ~35%, `csv` ~6% (1 of 6.2 allocations), `strwalk`/`strindex` `PushStr Equal` 7.7–7.8% of executions | **2–3%** | `run_frames.sysl` (`PushStr`, `MakeObject`), `code.sysl` (`Unit`), `run_compose.sysl` (`compose_object`), `table.sysl` (`obj_put`/`obj_put_named`), `obj.sysl` (roots) |
| **2** | **A DEFAULTED BARE-NAME OBJECT PATTERN TAKES THE FIXED PATH** — extend `UnpackFixed` to `{ a = 1, b }`: read each key by its interned hash, leave an absent one for the existing `JumpIfSet`. Today the matcher builds `pattern_names` per call | `options` **~40%** (`obj_get_name` 9.5, `match_walk` 6.3, `compose_unpack_slots` 4.8, `match_leaf` 4.5, `_xzm_free` 5.3, `Buf.grow<string>` 3.3, `pattern_names` 1.5, …) | **~2%** from one program; every options-object API in a server | `match.sysl`, `slots.sysl` (the `UnpackFixed` eligibility), `run_frames.sysl` |
| **3** | **THE SAFE POINT STOPS BEING AN INSTRUCTION** — fold `Tick` into the backward `Jump`/`LessJumpIfFalse` and the call arm (the only places a loop or a recursion comes round), or fuse it into its successor. **QUEUED as superinstructions round 2**: `Tick X` is the top pair on nine programs | `Tick` 1.6–19% of executions (mean ~9%), 24 machine instructions each; `maybe_collect_on` **1.79%** weighted, 5.1% of `fib`, 7.1% of `arrays` | **1.5–2.5%** | `emit.sysl`/`compile_stmt.sysl` (where `Tick` is placed), `run_frames.sysl`, `obj.sysl` (`maybe_collect_on`) |
| **4** | **THE CALL AND RETURN ARMS** — `Frame` without its counted `code: Buf[Ins]` (re-read from the chunk index at `Ret`), and `keepable_on` skipped where the compiler can prove an argument is not `undefined` | `fib` **~50%** of the program in call/return (51.2% of the loop's instructions + `placed_call` 8.6 + `lay_standing` 3.7 + safe point 5.1); call path **4.60%** weighted | **2–3%** | `vm.sysl` (`Frame`), `run_frames.sysl` (`CallFn`, `CallMethod`, `Ret`), `execute.sysl` (`placed_call`, `lay_standing`) |
| **5** | **THE PROTO HIT IS ONE LOOK** — a site that has seen a proto hit goes straight to `hop`/`up`; the two own-field misses, the `obj_index_hashed` own scan, `name != "new"` and the name retain all go | `methods` **27.8%** (`read_field_site` 14.1, `field_from_site` 11.2, `Buf.at<string>` 2.5); lookup group **6.19%** weighted. **Needs an answer to "the instance gained that name since"** — a per-object write counter or a shape id; the own scan is what currently proves it | **~1%** | `site_cache.sysl` (`read_field_site`, `field_from_site`), `table.sysl` |
| **6** | **A BUILTIN METHOD CALL IS CACHED AT ITS SITE** — the `(kind, name) → NativeFn` answer stored in the `CallMethod` site cache, so `methods_of`'s two string matches run once per site. **QUEUED with item 1 as the `methods_of` half** | `mapset` **~23%** (`methods_of` 11.4, `_tlv_get_addr` 5.1, `standing_native` 6.3); `methods_of` **0.77%** weighted | **~1%** | `method.sysl` (`methods_of`, `kind_method`), `index.sysl` (`builtin_receiver`), `site_cache.sysl` |
| **7** | **THE HEAD'S TWO REDUNDANT CHECKS — A sysl CODEGEN FINDING.** An exhaustive `match` over `Op` lowers with a reachable default (`cmp #0x6e; b.hi`), and the fetch checks `pc` against the code's length twice, once from a register and once from a spilled copy. 5 of 17 head instructions | ~12 points of weighted wall is head; 5/17 of it | **1–2%**, if the branches are not already free to the predictor — measure before believing | **sysl** — the switch lowering and the loop-invariant check; slate's `run_frames.sysl` only if sysl offers an unchecked read |
| **8** | **A BUILTIN NAME RESOLVED AT COMPILE TIME** — `number(…)` as `LoadDef`-style `LoadBuiltin` where nothing in the file binds the spelling | `csv` `LoadName` 8.9% of executions; name path **1.35%** weighted (half of it is `closures`/`nested` reading a *captured* name, which this does not touch) | **~0.5%** | `defs.sysl`, `compile_expr.sysl`, `run_frames.sysl` |
| **9** | **THREADED DISPATCH — STILL A sysl GAP**, unchanged from profile 5: no labels-as-values, no guaranteed tail calls | the 8-instruction jump sequence and the shared `br` | **4–8%** | sysl |
| **10** | **The four fused arms, inline again?** They are 9.83% weighted out of line, up from 6.99% as a share. `unfuse` measured them inline at +0.70% when the head was 22 instructions and the loop had no registers; `narrow-ins` freed three. **Re-measure, do not assume** | 9.83% weighted | unknown, and it has gone both ways | `run_frames.sysl`, `run_compose.sysl` |

**Off the list, with this page's reason:**

| | candidate | why |
|---|---|---|
| — | ~~A narrower `Ins`~~ | **DONE** (`narrow-ins`): 32 bytes, head 22 → 18 → 17 |
| — | ~~One jump table~~ | **DONE**: one `ldrh`, one `br` |
| — | ~~A `for`-head shape instruction~~ | **DONE** (`for-head`); item 2 is its defaulted sibling |
| — | **A register machine** | still unmeasured; the head is now 39% of the loop, not 46%, so its claim has weakened a little |
| — | **`strings`' `memmove`** | 84.5% of one program at 1.2x CPython; unchanged and not a mean item |
| — | **`_tlv_get_addr` at 1.72%** | real (`mapset` 5.1, `csv` 4.6, `alloc` 2.8) and diffuse — natives asking `current()`; worth a `vm` parameter on the hot natives the way `vm-param` did for the helpers, after items 1 and 6 move the natives it sits under |

### What the samples say plainly

- **A literal allocating on every execution was visible on every profile and named on none.**
  `gc.alloc` was priced four times as the allocator's cost; nobody asked what was being allocated.
  `SLATE_PROFILE`'s allocator step count divided by the loop count — **3.0 on `calls`, 3.0 on
  `alloc`** — against the instruction mix answered it in one line.
- **THE FIT CHANGED SIGN BECAUSE THE HEAD SHRANK, WHICH IS THE PREDICTION PROFILE 5 MADE.** A fixed
  cost drowned the arm term for three pages; five instructions off it and the arms show. The
  shortlist is correspondingly less about the head and more about particular arms.
- **A QUIET BOX IS A PER-PROGRAM PROPERTY ON A SHARED MACHINE.** One check before twenty programs
  was not enough today; the check before each one is cheap and is what this page stands on.
