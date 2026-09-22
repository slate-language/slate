# A third sampled profile, after sysl 0.0.123, the VM parameter and the inline caches (dev `a642e9f`)

**The second profile's headline — `Buf.push<Value>` at 15.3% of weighted wall time — is closed.**
sysl 0.0.123 moved `push`'s grow path out of line so the store-and-bump could inline, and
`Buf.push<Value>` is now **0.88%** weighted (1.36% on `methods`, the program the 0.0.123 witness
measured at 1.9%). Every `Buf.*` symbol together is **2.9%**, down from 19.2%. So the two structural
items that were ranked first and second on the second profile's table — inlining `push`, and a
register machine priced on push traffic — no longer point at the same cost, which is why this page
exists.

**THE NEW HEADLINE IS THAT THERE IS NO LONGER A SINGLE NAME TO NAME: `run_frames` IS 29.1% OF WEIGHTED
WALL TIME AND IT IS THE DISPATCH RATHER THAN ANY ARM.** Attributed against the profile build's own
instruction counts, its self time comes to a flat **1.30 ns per instruction executed** with **0.00 ns**
of dependence on which arms a program runs — the arms that do real work are all out-of-line symbols
with their own samples, and the arms that stay inside are a few instructions each. That is a different
kind of finding from the first two profiles: it is not a function to fix, it is the per-instruction
price of the instruction set.

**AND THE SECOND-LARGEST WHOLLY-SLATE ITEM WAS SITTING IN PLAIN SIGHT ON THE LAST PAGE, READ WRONG:
THE FOUR SUPERINSTRUCTION ARMS ARE OUT-OF-LINE CALLS.** `fused_load_slot_int`,
`fused_add_store_slot`, `fused_load_slot2` and `fused_less_jump_if_false` take **7.4%** of weighted
wall between them, and the second profile read their appearance as "the fused work now visible under
its own names". It is that, and it is also a `bl` and a frame around ten instructions, once per fused
pair — the very shape 0.0.122 and 0.0.123 removed from `Buf.at` and `Buf.push`. The sample's own
call-graph edges show `run_frames + <offset>` → `fused_load_slot_int` on `fib` and
→ `fused_add_store_slot` on `loops`, so they are calls and not inlined code wearing a name.

### How it was taken

**Identical to the first two profiles, so all three are comparable.** macOS `/usr/bin/sample` at a
1 ms interval, each program started and sampled in one shell call, run serially under
`caffeinate -dimsu`, against a plain (`-O2`, no `--features profile`) build of this commit.
`sample`'s **"Sort by top of stack, same collapsed"** section is self time and is what every figure
below reads; the denominator is the main thread's sample total from the call graph's head.

- **The same twenty of the twenty-three programs**, for the reasons the first page gives — `startup`,
  `strindex` and `strwalk` exit before the sampler can attach and are all already at or better than
  CPython.
- **7,264 samples**, against the second profile's 9,375 and the first's 19,349, on the same twenty
  programs at the same interval. The tree is about 2.7x faster than the first profile's and about
  1.3x faster than the second's; that is what makes every per-program total smaller.
- `sample` truncates its self-time table at 5 samples per name, so a per-program column sums to a
  little under 100% — 65.3% on `mapset` and 67.1% on `csv`, which are the two most scattered, and
  90–99% on the rest.
- **The idle figure at sampling time was not recorded** by the run that took these samples, so that
  one condition of the measurement protocol is stated as unknown rather than asserted. Nothing below
  is a wall-clock number: the shares are ratios within each program's own sample set, which a busy
  box would blur rather than bias.
- **The unnamed region is back up**: `???` leaves inside the first ~12 KB of `__text` — sysl's ARC
  release and its deferred-free walk — are **1.46%** weighted (1.28% unweighted), against the second
  profile's 0.67%, concentrated on `options` (3.8%), `csv` (3.8%), `fib` (2.6%) and `calls` (2.0%).
  Nothing named `arc.*` or `@arc.reap` appears anywhere in these samples.
- **`<deduplicated_symbol>` is 1.05% weighted** and is `sample` reporting a body the linker folded,
  not a function. It is largest on `globals` (5.9%), where the call graph shows it reached straight
  from `run_frames`.

### The aggregate

Weighted by each program's **slate/CPython ratio** from
[the QuickJS run's table](2026-09-21-quickjs.md), as the last two pages were, so the ranking favours
what closes the Python gap. The last column is the second profile's weighted share for the same
name, where it had one.

| self time | unweighted | weighted | second profile | what it is |
|---|---|---|---|---|
| `run_frames` | 27.74% | **29.08%** | 21.87% | the loop itself — **the dispatch, see below** |
| `gc.alloc` | 4.34% | **6.10%** | 4.91% | 28.7% `alloc`, 24.3% `csv`, 20.1% `calls` |
| `match_walk` | 4.17% | **4.59%** | 3.84% | `for` heads, `match` arms, destructuring |
| `fused_load_slot_int` | 2.82% | **2.91%** | — | a superinstruction, **and an out-of-line call** |
| `_platform_memmove` | 7.48% | 2.47% | 1.98% | 84.3% of it is `strings` alone |
| `fused_add_store_slot` | 2.01% | **2.29%** | 1.98% | a superinstruction, out-of-line |
| `placed_call` | 1.94% | **2.23%** | 1.74% | which of the three call paths |
| `Buf.push<Frame>` | 1.50% | 1.75% | 1.86% | one per call that pushes a frame |
| `fused_load_slot2` | 1.49% | **1.70%** | — | a superinstruction, out-of-line |
| `merge_sort` | 2.99% | 1.69% | 1.31% | 53.7% of `sorting`, which is its own comparator walk |
| `Map.find<string,Value>` | 1.84% | 1.58% | 1.18% | 9.1% of `globals` |
| `_xzm_free` | 1.78% | 1.50% | 1.54% | `free` — 7.1% `globals`, 7.0% `arrays` |
| `field_from_site` | 1.24% | 1.41% | — | **the inline cache** — 13.4% `fields`, 10.6% `methods` |
| `_tlv_get_addr` | 1.21% | **1.31%** | **4.28%** | the thread-local getter — **closed, see below** |
| `maybe_collect_on` | 1.12% | 1.29% | 1.59% | the collection schedule, asked per safe point |
| `multiplied` | 1.21% | 1.21% | 1.05% | `Mul`'s arm |
| `gc.collect` | 0.70% | 1.16% | 0.96% | 6.9% of `csv` |
| `key_here` | 0.95% | 1.09% | — | **the inline cache's key check** — 11.2% `fields`, 9.7% `methods` |
| `<deduplicated_symbol>` | 1.29% | 1.05% | — | a folded body, not a function |
| `arith` | 1.31% | 0.91% | 0.68% | 15.6% `reals`, 13.4% `sorting` |
| `Buf.push<Value>` | **0.76%** | **0.88%** | **15.34%** | **closed by sysl 0.0.123** |
| `lay_standing` | 0.69% | 0.87% | 0.41% | the standing-argument call path |
| `_platform_memset` | 0.99% | 0.87% | 0.89% | zeroing a payload |
| `find_entry` | 0.41% | 0.80% | 0.60% | 12.9% of `mapset` |
| `read_field_site` | 0.72% | 0.80% | — | the inline cache's read |
| `methods_of` | 0.32% | 0.73% | 0.50% | 13.5% of `mapset` and invisible elsewhere |
| `gc.rebuild_free` | 0.47% | 0.72% | — | the sweep's free-list rebuild |
| `hash_str` | 1.10% | 0.67% | — | 7.7% of `globals` |
| `Buf.at<*>` (all) | 1.25% | 1.31% | 0.61% | still inlined at every hot site |
| `Buf.push<*>` (all) | 2.44% | **2.88%** | **19.2%** | — |

**Rolled up, weighted:**

| group | weighted | unweighted | what is in it |
|---|---|---|---|
| **the dispatch** (`run_frames` self) | **29.08%** | 27.74% | — |
| **allocation and the collector** | **12.08%** | 9.42% | `gc.alloc` 6.10 + `gc.collect` 1.16 + `maybe_collect_on` 1.29 + `gc.rebuild_free` 0.72 + `memset` 0.87 + `__bzero` 0.66 + `new_str_counted` 0.55 + `compose_object` 0.42 + `alloc_or_collect` 0.28 |
| **the superinstruction arms** | **7.41%** | 6.87% | the four `fused_*` symbols, every one an out-of-line call |
| **field and method lookup** | **7.35%** | 5.86% | `field_from_site` 1.41 + `key_here` 1.09 + `read_field_site` 0.80 + `find_entry` 0.80 + `methods_of` 0.73 + `obj_put` 0.60 + `scan_named` 0.56 + six smaller |
| **the call path** | **5.70%** | 4.80% | `placed_call` 2.23 + `Buf.push<Frame>` 1.75 + `lay_standing` 0.87 + `Buf.at<Frame>` 0.64 + `pop_on` 0.20 |
| **`match_walk`** | **4.59%** | 4.17% | one symbol |
| **`Map<string, *>` plus `hash_str`** (globals) | **4.03%** | 5.97% | `Map.find` 1.58 + `hash_str` 0.67 + `Map.get` 0.58 + `Map.put` 0.40 + `Map.get<string,bool>` 0.33 + `lookup` 0.33 + `assign_name` 0.13 |
| **ARC and the malloc/free under it** | **3.81%** | 4.27% | `_xzm_free` 1.50 + the unnamed `???` 1.46 + three malloc symbols 0.76. **No `arc.*` or `@arc.reap` symbol appears at all** |
| **`memmove`/`memcpy`** | **2.52%** | 7.56% | almost all of it `strings` |
| **`Buf.push<Value>`** | **0.88%** | 0.76% | the counted-element push — **confirmed closed** |
| **`current()` through `_tlv_get_addr`** | **1.31%** | 1.21% | was 4.28%; the VM parameter took it |

### Per program, the top five

| benchmark | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| arith | `run_frames` 51.4 | `fused_load_slot_int` 10.3 | `fused_add_store_slot` 9.7 | `fused_load_slot2` 7.4 | `added` 7.4 |
| reals | `run_frames` 44.7 | `arith` 15.6 | `real_arith` 11.5 | `fused_load_slot_int` 9.5 | `fused_load_slot2` 4.2 |
| globals | `run_frames` 19.5 | `Map.find` 9.1 | `hash_str` 7.7 | `_xzm_free` 7.1 | `Map.put` 6.1 |
| funcs | `run_frames` 54.3 | `fused_load_slot_int` 9.2 | `Buf.push<Frame>` 5.2 | `lay_standing` 4.6 | `fused_add_store_slot` 4.6 |
| fib | `run_frames` 54.3 | `placed_call` 10.5 | `fused_load_slot_int` 6.8 | `Buf.push<Frame>` 5.9 | `Buf.push<Value>` 3.5 |
| calls | `gc.alloc` 20.1 | `run_frames` 13.4 | `placed_call` 3.1 | `fused_load_slot_int` 3.1 | `_tlv_get_addr` 3.1 |
| methods | `run_frames` 44.6 | `field_from_site` 10.6 | `key_here` 9.7 | `read_field_site` 5.4 | `multiplied` 4.5 |
| closures | `run_frames` 35.0 | `fused_add_store_slot` 11.3 | `Map.find` 6.2 | `fused_load_slot_int` 5.6 | `placed_call` 5.1 |
| nested | `run_frames` 36.1 | `match_walk` 19.9 | `multiplied` 6.0 | `fused_load_slot2` 5.5 | `placed_call` 5.2 |
| loops | `run_frames` 38.0 | `match_walk` 36.7 | `fused_add_store_slot` 5.2 | `fused_load_slot2` 4.8 | `multiplied` 4.4 |
| options | `run_frames` 31.5 | `match_walk` 13.7 | `scan_named` 6.7 | `multiplied` 3.4 | `Buf.grow<string>` 3.4 |
| fields | `run_frames` 35.8 | `field_from_site` 13.4 | `read_field_site` 11.8 | `key_here` 11.2 | `fused_add_store_slot` 5.9 |
| alloc | `gc.alloc` 28.7 | `run_frames` 13.2 | `memset` 4.6 | `gc.collect` 3.8 | `_tlv_get_addr` 3.4 |
| arrays | `run_frames` 17.6 | `mach_absolute_time` 8.2 | `_xzm_free` 7.0 | `fused_add_store_slot` 6.2 | `fused_load_slot2` 5.0 |
| mapset | `run_frames` 23.5 | `methods_of` 13.5 | `find_entry` 12.9 | `obj_put` 4.7 | `fused_load_slot2` 3.5 |
| dispatch | `run_frames` 48.0 | `match_walk` 19.8 | `placed_call` 4.7 | `fused_add_store_slot` 4.5 | `fused_load_slot_int` 4.2 |
| branches | `run_frames` 65.7 | `fused_load_slot_int` 14.0 | `remainder_of` 5.8 | `fused_add_store_slot` 3.7 | `fused_less_jump_if_false` 2.5 |
| sorting | `merge_sort` 53.7 | `on_values` 13.9 | `arith` 13.4 | `int_arith` 11.1 | `Buf.grow<Value>` 2.7 |
| csv | `gc.alloc` 24.3 | `run_frames` 10.1 | `gc.collect` 6.9 | `gc.rebuild_free` 3.1 | `_tlv_get_addr` 3.1 |
| strings | `memmove` 84.3 | `trace_env` 5.9 | `gc.alloc` 2.0 | `mach_absolute_time` 1.6 | `mark_value` 0.8 |

**`run_frames` takes no measurable self time on `sorting` or `strings`** — both are below the
five-sample floor, because in one the work is `merge_sort` and in the other it is one `memmove`.
Neither is an interpreter benchmark.

### `run_frames` BROKEN DOWN BY INSTRUCTION ARM, WHICH IS THE QUESTION THIS PAGE WAS ASKED

`run_frames` is 44.6% self on `methods`, 54.3% on `fib` and 65.7% on `branches`, so the brief was to
attribute that across the arms. **The attribution says the arms are not where it goes.**

The instrument is `sysl build . --features profile` and `SLATE_PROFILE=1 ./slate bench/<name>.sl`,
which reports exact executions per instruction kind. (The `wall` figure that build prints is ~18x the
plain build's, the per-kind tally and the adjacent-pair maps being what costs it; the **counts** are
exact and are the only thing read here.)

**An arm either stays inside `run_frames` or it calls out to a symbol that takes its own samples**, and
the second set is much the larger. Every one of these kinds is a call: `CallFn`/`CallMethod`
(`placed_call`, `Buf.push<Frame>`, `lay_standing`), `Ret` (`pop_on`, `Buf.at<Frame>`), `Add`/`Sub`/`Mul`
(`added`, `subtracted`, `multiplied`), `Rem` (`remainder_of`), `GetField`/`SetField`
(`field_from_site`, `key_here`, `read_field_site`, `write_named_at`), `LoadName`/`StoreName`
(`Map.find`/`Map.put`, `hash_str`, `lookup`), `IterNext`/`UnpackSlots` (`match_walk`), `Tick`
(`maybe_collect_on`), `MakeObject` (`compose_object`, `obj_put`), **and the four fused
superinstructions**. What stays inside is `LoadSlot`, `PushInt`, `PushReal`, `PushStr`, `LoadDef`,
`Jump`, `JumpIfFalse`, `JumpIfSet`, `TestSlots`, `StoreSlot`, `DeclareSlot`, `Pop`, `Discard` and
`Equal` — a load, a store or a branch each.

| program | instructions | `run_frames` self | ns per instruction | arms that STAY inside, by share of executions |
|---|---|---|---|---|
| branches | 121,451,942 | 65.7% | **1.31** | `JumpIfFalse` 11.6, `PushInt` 10.0, `Equal` 6.7, `Jump` 5.2, `DeclareSlot` 4.9, `TestSlots` 4.9 |
| fib | 119,760,624 | 54.3% | **1.94** | `LoadDef` 9.5, `LoadSlot` 4.8, `Jump` 4.8 |
| funcs | 72,000,027 | 54.3% | **1.31** | `LoadSlot` 11.1, `PushInt` 5.6, `LoadDef` 5.6, `Jump` 5.6 |
| arith | 130,000,025 | 51.4% | **0.69** | `PushInt` 15.4, `StoreSlot` 7.7, `Jump` 7.7 |
| dispatch | 140,000,026 | 48.0% | **1.23** | `TestSlots` 12.5, `JumpIfFalse` 12.5, `PushInt` 7.1, `LoadSlot` 7.1, `Jump` 7.1 |
| reals | 130,000,027 | 44.7% | **0.90** | `PushReal` 15.4, `StoreSlot` 7.7, `Jump` 7.7 |
| methods | 111,000,068 | 44.6% | **1.77** | `LoadSlot` 24.3, `Jump` 2.7 |
| loops | 64,138,039 | 38.0% | **1.36** | `Jump` 12.5, `LoadSlot` 12.5 |
| nested | 84,108,048 | 36.1% | **1.72** | `Jump` 7.1, `LoadSlot` 7.1 |
| fields | 75,000,032 | 35.8% | **0.89** | `LoadSlot` 13.3, `Jump` 3.3 |
| closures | 60,000,033 | 35.0% | **1.03** | `LoadSlot` 13.3, `Jump` 3.3 |
| options | 86,000,037 | 31.5% | **1.81** | `LoadSlot` 16.3, `JumpIfSet` 9.3, `PushInt` 4.7 |
| mapset | 34,015,042 | 23.5% | **1.18** | `LoadSlot` 5.9, `PushInt` 11.8, `Discard` 11.8 |
| globals | 102,000,020 | 19.5% | **1.78** | `PushInt` 23.5, `Jump` 5.9 |
| arrays | 91,000,521 | 17.6% | **0.66** | `Jump` 11.5, `LoadSlot` 3.3 |
| calls | 48,000,046 | 13.4% | **1.25** | `LoadSlot` 12.5, `PushStr` 8.3, `StoreSlot` 4.2, `Jump` 4.2 |
| alloc | 57,000,025 | 13.2% | **1.16** | `LoadSlot` 10.5, `PushStr` 10.5 |
| csv | 14,340,921 | 10.1% | **2.02** | `LoadSlot` 8.6, `DeclareSlot` 8.4, `PushStr` 4.5, `Jump` 4.3 |

**THE ARMS EXPLAIN NOTHING, AND THAT IS A FITTED RESULT RATHER THAN AN IMPRESSION.** Fit
`run_frames`' self time as `D × (instructions) + E × (instructions whose arm stays inside)` by least
squares over the eighteen programs that take any: the best fit is **D = 1.30 ns and E = 0.00 ns**. The
inline arms cost nothing measurable above what every instruction already costs, and the fit will not
pay for a per-inline-arm term at all. `branches` — the highest `run_frames` share on the page at
65.7% — is simply the program with the largest fraction of its arms inside the loop and almost nothing
else running; it is not a program where an arm is slow.

**What the residuals say instead is that the cost per instruction varies threefold with the SHAPE of
the program, not with its arm mix.** `arrays` 0.66, `arith` 0.69, `fields` 0.89 and `reals` 0.90 at one
end; `csv` 2.02, `fib` 1.94, `options` 1.81, `globals` 1.78 and `methods` 1.77 at the other. There is no
correlation with the inline share (`fib` is 19.0% inline at 1.94 ns, `branches` 48.3% inline at 1.31 ns,
`arith` 30.8% inline at 0.69 ns). The cheap end is tight single-chunk loops; the expensive end is
programs that interleave many chunks and calls. **The reading offered, as a hypothesis rather than a
measurement:** the dispatch head fetches a 56-byte `Ins` with four loads before it branches (the second
profile's disassembly of that head), so a program whose instruction stream stays in L1 pays about three
cycles and one that jumps between chunks pays the miss. That is testable and was not tested here.

**So on `methods`, `calls`, `fib`, `nested` and `csv` the answer to "which arm dominates" is: none.**
73.0%, 70.8%, 81.0%, 85.7% and 74.1% of the instructions those five execute have their real work in a
symbol outside `run_frames`, and the largest arm that stays inside is `LoadSlot` — 24.3% of `methods`'
executions, 12.5% of `calls`', 4.8% of `fib`'s. Where their time actually goes is already in the
per-program table above: `methods` is the field lookup (25.7% across `field_from_site`, `key_here` and
`read_field_site`), `calls` and `csv` are `gc.alloc` (20.1% and 24.3%), `fib` is the call path (`placed_call`
10.5 + `Buf.push<Frame>` 5.9 + `Buf.push<Value>` 3.5 + `Buf.at<Frame>` 1.4), and `nested` is `match_walk`
19.9 plus `multiplied` 6.0.

### The things the brief asked to be measured, with their numbers

| what | weighted | where it concentrates |
|---|---|---|
| **the call path** — `lay_frame`/`Called.Enter`, frame set-up, argument placing, `Ret` | **5.70%** | `fib` 21.1, `funcs` 11.6, `closures` 11.4, `nested` 9.4 |
| **`gc.alloc`** alone | **6.10%** | `alloc` 28.7, `csv` 24.3, `calls` 20.1 |
| **allocation and the collector together** | **12.08%** | `alloc` 41.9, `csv` 39.3, `calls` 29.6 |
| **ARC retain/release (`arc.*`, `@arc.reap`)** | **3.81%**, and **not under those names** — no `arc.*` or `@arc.reap` symbol appears in any of the twenty samples. What is there is `_xzm_free` 1.50, the unnamed `???` region 1.46 and three malloc symbols 0.76 | `options` 3.8 + `csv` 3.8 (unnamed), `globals` 7.1 + `arrays` 7.0 (`free`) |
| **`match_walk`** | **4.59%** | `loops` 36.7, `nested` 19.9, `dispatch` 19.8, `options` 13.7 |
| **`Map<string, Value>` lookups (globals)** | **4.03%** with `hash_str` | **37.9% of `globals`** and nothing above 6.2% anywhere else |
| **`memmove`/`memcpy`** | **2.52%** (7.56% unweighted) | `strings` 84.3, `globals` 3.1 |
| **`Buf.push<Value>`, the counted element** | **0.88%** — confirmed: 1.36% on `methods` against the 0.0.123 witness's 1.9% and the second profile's 16.2% | `fib` 3.5, `loops` 3.5, `closures` 3.4 |

**Two of the second profile's items are closed by this page rather than re-ranked.** `_tlv_get_addr`
went **4.28% → 1.31%** (on `fib` it was 9.1% and does not reach the five-sample floor at all now),
which is the VM-parameter work; and `Buf.push<Value>` went **15.34% → 0.88%**.

**The inline caches landed and the field lookup is still the largest concentrated cost on two
programs.** `field_from_site` + `key_here` + `read_field_site` is **25.7% of `methods`** and
**30.5% of `fields`**, and `key_here` — the cache's own key comparison — is a third of both. Weighted
over the set the lookup group is **7.35%**, against the second profile's 6.5%: it did not get slower,
everything around it got faster.

### The re-ranked shortlist: the next five slate-only items

Share is the weighted aggregate above. A ceiling is what an item could take off the geometric mean if
it removed **all** of the named cost, which none will. Every one of these five is slate's own code —
where an item's cost lands in sysl or in `sh.sysl.gc` it is said so.

| rank | candidate | measured share | ceiling | kind | files |
|---|---|---|---|---|---|
| 1 | ~~**INLINE THE FOUR SUPERINSTRUCTION ARMS** — `fused_load_slot_int`, `fused_add_store_slot`, `fused_load_slot2`, `fused_less_jump_if_false` are out-of-line functions called from the dispatch, each a `bl` and a frame around a handful of instructions~~ — **DONE 2026-09-21, [`inline-fused`](2026-09-21-inline-fused.md): -1.96% geometric mean**, `fib` -6.4%, `arith` -5.3%, `fields` -4.5%, `branches` -3.9%; all four symbols gone from the binary, instruction counts identical. **Why `-O2` had not done it: `private` in sysl is per FILE, so a body called across one is EXTERNAL in the emitted LLVM and the single-caller bonus cannot apply** | **7.41%**; 14.0% + 3.7% + 2.5% of `branches`, 11.3% of `closures`, 10.3% + 9.7% + 7.4% of `arith`, 9.2% of `funcs` | was **3–5%**, and it took 2.0% | INCREMENTAL, **wholly slate's** | `run_frames.sysl` (each arm written out), `run_compose.sysl` (seven cold arms moved out to make the room) |
| 2 | **THE FIELD AND METHOD LOOKUP, AFTER the inline caches** — `key_here` is the cache's validity check and is 11.2% of `fields` and 9.7% of `methods` on its own; a shape/hidden-class token compared as one integer would replace a key comparison | **7.35%**; 30.5% of `fields`, 25.7% of `methods`, 19.2% of `mapset`, 10.8% of `calls` | **2–4%** | INCREMENTAL, wholly slate's | `index.sysl`, `table.sysl`, `run_frames.sysl` |
| 3 | **`match_walk` — `for` heads, `match` arms, destructuring** — confirmed, and it is now the third-largest single name on the page. A `for` over an array with a bare-name head does not need the pattern matcher at all | **4.59%**; 36.7% `loops`, 19.9% `nested`, 19.8% `dispatch`, 13.7% `options` | **2–3%** | INCREMENTAL, wholly slate's | `match.sysl`, `index.sysl`, `run_frames.sysl` |
| 4 | **MODULE-LEVEL `var` CELLS, `StoreDef`** — confirmed, and its reach is sharper than the last page's estimate: the `Map<string,*>` work is 37.9% of `globals` and the `free`/`malloc`/`memmove` churn reached straight from `run_frames` is another ~15%, so **over half of one program** | **4.03%**, and ~53% of `globals` | **0.6–0.9% of the mean**, 40%+ of one program — the reach column's usual reading | INCREMENTAL, wholly slate's | `defs.sysl`, `emit.sysl`, `compile.sysl` |
| 5 | **A NARROWER `Ins`, so the dispatch head fetches less** — the dispatch is 29.1% of wall at a flat 1.30 ns per instruction with no arm dependence, and the head's four loads of a 56-byte `Ins` are the part of it a change can reach. **Measure the hypothesis before building anything**: the threefold spread in ns/instruction is consistent with instruction-stream cache behaviour and has not been confirmed as its cause | **29.08%** is the dispatch; the fetch is an unmeasured fraction of it | **unknown — the next measurement, not yet an item.** A ceiling cannot be named until the spread is explained | OPEN QUESTION | `vm.sysl` (`Ins`), `emit.sysl`, `run_frames.sysl` |

**And what came off the list.**

| | candidate | what this page says |
|---|---|---|
| — | ~~**Inline `Buf.push`**~~ | **DONE in sysl 0.0.123.** `Buf.push<Value>` is **0.88%** weighted and 1.36% on `methods`; all of `Buf.*` is 2.9%, from 19.2% |
| — | ~~**Stop re-asking `current()`**~~ | **DONE.** `_tlv_get_addr` **4.28% → 1.31%**, and below the floor on `fib` |
| — | ~~**Inline caches for a field or a method**~~ | **DONE**, and the remainder is item 2 above: the lookup is still 25.7% of `methods` with the cache's own `key_here` a third of it |
| — | **Per-call allocation in `calls` and `csv`** — the second profile's open question | **ANSWERED, and it is not per-call overhead.** `calls` executes 2,000,003 `MakeObject`s against 2,000,003 `CallFn`s and 2,000,000 `CallMethod`s — one object per call, which is the benchmark's own work. `gc.alloc` is `sh.sysl.gc`'s allocator, so the 20.1%/24.3% it takes on those two is **a gc-package item, not a slate one**. What is slate's is the schedule beside it (`maybe_collect_on` 1.29 + `gc.collect` 1.16 + `gc.rebuild_free` 0.72 weighted) |
| — | **`strings` O(i) indexing, 44.6x QuickJS** | **STRUCK, and the premise is wrong.** Character indexing was closed in 0.0.58; `bench/strings.sl` is `out = out + "x" + string(i % 10)` 150,000 times, so the 84.3% `memmove` is **quadratic copying in repeated concatenation**, not indexing. A rope or a builder would close it, and the program is already **1.2x CPython and 2.0x Lua** — 2.5% of weighted wall over the set. Worth doing for a consumer that concatenates in a loop, not for the mean |
| — | **A register machine instead of a stack machine** | **RE-PRICED, and the old price is gone.** It was ranked at 15.5% on `Buf.push<Value>` + `pop`, which together are now **1.1%**. What is left of the item is the *instruction count* it would remove — `LoadSlot`, `LoadSlot2`, `LoadSlotInt` and `PushInt` are ~26% of all instructions — which at the dispatch's 1.30 ns/instruction is worth **6–9%**. Still STRUCTURAL, still not piecemeal, and now competing with item 1 for the same cost by a cheaper route |
| — | **A narrower `Value`, or NaN-boxing** | **STRUCK as a near-term item.** Priced at 5–8% when `Buf.push<Value>` was 15.3%; the push is inlined and 0.88%, so what remains is stack-traffic width inside the loop. **1–3%** for a change that reaches the collector, the tables, both back ends and every native |
| — | ~~**The second bounds check inside `Buf.at`**~~ | **STILL STRUCK** — the second profile's disassembly closed it |
| — | ~~**`methods_of` looking a method up by name**~~ | **STILL STRUCK.** 0.73% weighted, 13.5% of `mapset` and invisible on the other nineteen |

### What the samples say plainly, beside the first two profiles

- **Three profiles have now each closed the previous one's headline, and the fourth cannot be a
  function.** `Buf.at` was 32.4%, `Buf.push<Value>` was 15.3%, and both are under 1%. What is left at
  the top is `run_frames` itself at 29.1%, which the arm attribution says is the per-instruction price
  of the instruction set rather than any one piece of code.
- **The largest wholly-slate item on the page was visible on the last one and read wrong.** The four
  `fused_*` names were taken for "the fused work now visible under its own names"; a name in the
  self-time table means a **function**, and a function called once per instruction is the shape the
  last two sysl releases were about. **A symbol taking self time is evidence about the binary's
  structure, not only about where time goes.**
- **`sample` cannot attribute this interpreter's call graph and the self-time table is the only honest
  read.** The hot symbols appear as siblings of `run_frames` under the top closure rather than as its
  children, so a "callees of `run_frames`" figure would be nearly empty — 1–3% per program, and the
  edges that do survive (`globals` → `memmove`, `malloc`; `fib` → `Buf.push<Value>`, `placed_call`)
  are the useful residue rather than the picture.
- **An instruction count and a sampled profile disagree about `branches` and agree about nothing
  else.** `branches` has the highest `run_frames` share on the page (65.7%) and is 0.9x CPython — the
  best ratio of any interpreter benchmark here. A high dispatch share means *the arms are cheap*, not
  that the program is slow, and the second profile's `branches` reading (44.6%) was the same fact one
  release earlier.
- **`_tlv_get_addr` is the worked example of reading a profile twice.** The first profile called it the
  ARC free list, the second called it `current()` and made an item of it, and the item measured -4.06%.
  It is 1.31% now. Three readings, and only the middle one could have been acted on.
- **The position, from the QuickJS run on this tree:** 3.5x Lua, 2.7x `node --jitless`, **1.8x
  CPython** and 2.2x QuickJS-ng on the geometric mean. The four worst against CPython are `csv` 4.3x,
  `calls` 4.2x, `methods` 3.0x and `globals` 2.9x — and this page names all four: `csv` and `calls` are
  `gc.alloc` (a gc-package item), `methods` is the field lookup (item 2), and `globals` is its
  `Map<string, Value>` name path (item 4).
