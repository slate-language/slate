# A fourth sampled profile, and where the missing 2% went (dev `f36f35e`, sysl 0.0.125)

**THE ANSWER IS THAT `inline-fused` IS A NET LOSS ON TODAY'S COMPILER, AND IT WAS MEASURED BY
BUILDING BOTH TREES WITH ONE COMPILER AND TIMING THEM AGAINST EACH OTHER.** Two things landed after
the third profile: `24a2cb0` `inline-fused`, which wrote the four superinstruction arms out inside
`run_frames.sysl` and moved seven cold arms to `run_compose.sysl` (−1.96% measured on sysl 0.0.123),
and the sysl 0.0.124 pickup, which made `Buf.push<Value>` inline outright (−2.08% measured alone on
the pre-merge tree, +0.06% measured on top of `inline-fused`). Those four figures do not add: two
changes worth −4.0% between them came to a wash, so about **+4% of interaction** has to be somewhere.

**Rebuilt today with one compiler — sysl 0.0.125, which inlines `push` in both — and timed
alternating best-of-9, `inline-fused` costs +1.19% on the twenty benchmark programs and +0.90%
over all twenty-three.** `branches` is +6.66%, which is the +8% the 0.0.124 page reported wearing
its own name. So the −2% did not "go" anywhere: **the push inlining is real and is still worth what
it measured, and `inline-fused` stopped being worth what it measured the moment it landed underneath
it.** The item is a revert, and it is the top of the shortlist below.

**AND THE MECHANISM IS THE REGISTER ALLOCATOR RATHER THAN CODE SIZE, WHICH THE DISASSEMBLY SETTLES IN
THE OPPOSITE DIRECTION FROM THE ONE THE QUESTION EXPECTED.** `run_frames` got **smaller** —
49,232 bytes down to 40,300, an 18% cut — and got slower with it, so no icache or code-layout story
survives. What the two binaries' prologues say instead is that **`run_frames` was already saturated**:
both save the identical six callee-saved pairs (`x19`–`x28`, `x29`/`x30`) and both open the identical
1,504-byte frame (`sub sp, sp, #0x5e0`). There was no room to make. The difference is which of the
loop's own invariants got a register, and the entry block is where it shows.

### How it was taken

**Identical to the first three profiles, so all four are comparable.** macOS `/usr/bin/sample` at a
1 ms interval, each program started and sampled in one shell call, run serially under
`caffeinate -dimsu`, against a plain (`-O2`, no `--features profile`) build of dev `f36f35e`.
`sample`'s **"Sort by top of stack, same collapsed"** section is self time and is what every figure
below reads; the denominator is the main thread's sample total.

- **The same twenty of the twenty-three programs**, for the reason the first page gives — `startup`,
  `strindex` and `strwalk` exit before the sampler can attach.
- **7,255 samples**, against the third profile's 7,264 on the same twenty at the same interval: the
  tree is the same speed, which is itself the finding this page opens with.
- **The idle figure WAS recorded this time**, the third profile having had to state it as unknown:
  **84.2% before sampling and 87.9% before the timing run**, `pgrep -x java` empty throughout.
- `sample` truncates its self-time table at 5 samples per name, so a per-program column sums to under
  100% — 72.8% on `mapset` and 75.4% on `csv`, 85–100% on the rest.
- **The unnamed `???` region does not reach the floor on any program this time** and no `arc.*` or
  `@arc.reap` symbol appears anywhere, exactly as on the last two pages.

**The A/B that answers the question is a separate measurement and is not a sample.** Two binaries
built by sysl 0.0.125 in detached worktrees:

- **Q** — dev `f36f35e` as it stands. `24a2cb0`..`f36f35e` touches only test files, `script.sysl`
  and `package.hocon`, so this binary's `run_frames` is `inline-fused`'s.
- **P** — the same tree with **only** the four `inline-fused` files put back to `bf4dd9b`
  (`run_frames.sysl`, `run_fused.sysl`, `run_compose.sysl`, `tests_fused.sysl`). `git diff --stat
  f36f35e -- dev/` over that worktree names those four and nothing else.

**`bf4dd9b` itself will not build under sysl 0.0.125** — `script.sysl:193` matches on
`sysl.process.Status`, which grew a `TimedOut` variant, and `f36f35e` is the commit that added the
arm. That is why the control is *HEAD minus the four files* rather than the old commit, and it is the
better control anyway: it holds everything else constant.

**And the third binary the brief asked for does not exist.** `1ddd87e` touches `bench/` only, so a
build of it is byte-for-byte a build of `24a2cb0`; the 0.0.124 pickup was a **compiler** change, and
with only 0.0.125 installed there is no way to build a tree with `push` out of line. The interaction
is therefore measured as *(both) minus (push alone)*, which is what P against Q is, and which the
arithmetic above predicts at about +2%.

### What `inline-fused` costs, alternating best-of-9, control P against dev Q

Lowest of nine alternating runs each, `bench/timeit.pl`, under `caffeinate -dimsu`, 87.9% idle.

| program | P control (ms) | Q dev (ms) | change |
|---|---|---|---|
| branches | 323.952 | 345.541 | **+6.66%** |
| closures | 230.630 | 238.878 | **+3.58%** |
| funcs | 230.972 | 236.487 | **+2.39%** |
| dispatch | 461.010 | 469.956 | +1.94% |
| strings | 704.851 | 718.091 | +1.88% |
| loops | 289.745 | 295.045 | +1.83% |
| sorting | 504.321 | 513.222 | +1.76% |
| fields | 257.145 | 261.084 | +1.53% |
| reals | 349.503 | 353.047 | +1.01% |
| globals | 1104.683 | 1115.652 | +0.99% |
| fib | 513.307 | 517.972 | +0.91% |
| csv | 362.904 | 366.129 | +0.89% |
| alloc | 599.992 | 605.102 | +0.85% |
| mapset | 242.809 | 244.627 | +0.75% |
| arrays | 433.484 | 436.518 | +0.70% |
| arith | 268.932 | 268.981 | +0.02% |
| options | 578.420 | 578.288 | −0.02% |
| calls | 549.108 | 546.791 | −0.42% |
| methods | 540.102 | 534.791 | −0.98% |
| nested | 487.601 | 477.304 | **−2.11%** |
| **geometric mean, the twenty** | | | **+1.19%** |
| **geometric mean, all twenty-three** | | | **+0.90%** |

**Seventeen of twenty are slower and the three that are not are the three the arms barely touch.**
`nested` is `match_walk` and `placed_call`; `methods` is the field lookup; `calls` is `gc.alloc`. The
loss concentrates exactly where the loop's own arms are the program — `branches` executes 85.1% of
its instructions inside `run_frames`, 22.6% of them `LoadSlotInt`, and it pays the most.

**Read against the historical numbers this is consistent rather than new.** `inline-fused` measured
−1.96% on sysl 0.0.123 and +1.19% on 0.0.125; the push inlining measured −2.08% on the pre-merge tree
and +0.06% on top of `inline-fused`. Both pairs say the same thing from opposite ends: **the two
changes compete for one resource, and only one of them can be had.**

### The disassembly, which says the resource is registers and not space

`nm -n` bounds plus `otool -tvV` over `_dev.slatelang.slate$run_frames` in both binaries.

| | P control (fused out of line) | Q dev (inline-fused) |
|---|---|---|
| `run_frames` | 49,232 bytes (12,308 insns) | **40,300 bytes (10,075 insns)** |
| the four `fused_*` bodies | 1,556 bytes (389 insns) | not in the binary |
| **total** | **50,788 bytes** | **40,300 bytes** |
| callee-saved `stp` pairs in the prologue | **6** (`x19`–`x28`, `x29`/`x30`) | **6**, identical |
| stack frame | `sub sp, sp, #0x5e0` (1,504 bytes) | `sub sp, sp, #0x5e0`, identical |
| `bl` sites in the body | 639 | 517 |
| stack stores / loads in the body | 880 / 2,107 | 891 / 1,627 |
| stack loads as a share of the body | 17.1% | 16.1% |
| distinct stack slots read | 185 | 182 |

**The frame and the saved set are byte-identical, which is the whole finding.** `run_frames` already
used every callee-saved register the ABI has, and already opened a 1,504-byte frame, *before*
`inline-fused` — so the hypothesis in the brief, that inlining `push` raised pressure and a bigger
prologue would show it, cannot be tested that way: there is no headroom to consume and the prologue
could not have grown. The allocator's answer to more live values in a saturated function is not a
larger frame, it is **a different choice about which values keep registers**, and that is what the
entry block records:

```
P control                              Q dev f36f35e
  +0x1c  mov  x22, x5   (outer_scope)    +0x1c  mov  x19, x7   (args)
  +0x20  str  x4,  [sp, #0xf0]  (floor)  +0x20  str  x4,  [sp, #0x120]  (floor)
  +0x24  mov  x21, x2   (from)           +0x24  str  x3,  [sp, #0x208]  (base0)
  +0x28  mov  x23, x1   (start)          +0x28  mov  x28, x2  (from)
  +0x2c  mov  x10, x0   (u)              +0x2c  mov  x10, x1  (start)
                                         +0x30  str  x0,  [sp, #0x218]  (u)
                                         ...
                                         +0x6c  ldr  x9,  [sp, #0x218]  (u, read back)
```

**P spills one of `run_frames`' nine parameters at entry and Q spills three**, and one of Q's three is
`u` — the `Unit`, which every instruction fetch reads — reloaded forty lines later and forty-two times
across the body. That is the cost, and it is paid per instruction dispatched rather than per fused
pair saved.

**What it is NOT, and both were candidates in the brief:**

- **Not code size or layout.** The loop is 18% smaller in the build that is 1.19% slower, and the
  binary has 122 fewer call sites in it. An icache or branch-predictor story would have to explain
  why *less* code in the hot function costs time.
- **Not raw spill volume.** Q does proportionally *fewer* stack loads (16.1% of its body against
  17.1%) over a similar number of distinct slots (182 against 185). The change is in **which** values
  are on the stack, not how many.

**And the fourth candidate cannot be answered with this instrument.** macOS `sample` collapses every
frame to its symbol, so there is no `run_frames + <offset>` anywhere in these twenty files and there
is no way to map hot spots inside the loop to arms. Attributing within `run_frames` needs a
PC-sampling profiler this machine does not have, or an instrumented build, and that is a measurement
this page did not take rather than one it took and found nothing in.

### The aggregate

Weighted by each program's **slate/CPython ratio** from
[the QuickJS run's table](2026-09-21-quickjs.md), as the last three pages were. The last column is the
third profile's weighted share for the same name.

| self time | unweighted | weighted | profile 3 | what it is |
|---|---|---|---|---|
| `run_frames` | 33.03% | **35.26%** | 29.08% | the loop — **and it now contains the four fused arms** |
| `gc.alloc` | 4.07% | **6.23%** | 6.10% | 28.5% `csv`, 25.4% `alloc`, 19.9% `calls` |
| `match_walk` | 4.01% | **4.49%** | 4.59% | `for` heads, `match` arms, destructuring |
| `placed_call` | 2.18% | **2.62%** | 2.23% | which of the three call paths |
| `_platform_memmove` | 7.31% | 2.46% | 2.47% | 83.7% of it is `strings` alone |
| `Map.find<string,Value>` | 2.34% | 1.91% | 1.58% | 12.2% of `globals` |
| `merge_sort` | 3.31% | 1.72% | 1.69% | 54.8% of `sorting` |
| `key_here` | 1.30% | 1.51% | 1.09% | the inline cache's key check — 12.3% `methods` |
| `field_from_site` | 1.25% | 1.46% | 1.41% | the inline cache — 16.1% `fields` |
| `<deduplicated_symbol>` | 1.61% | 1.39% | 1.05% | a folded body, not a function |
| `maybe_collect_on` | 1.21% | 1.34% | 1.29% | the collection schedule, per safe point |
| `_xzm_free` | 1.70% | 1.31% | 1.50% | `free` — 7.9% `globals` |
| `multiplied` | 1.20% | 1.26% | 1.21% | `Mul`'s arm |
| `_tlv_get_addr` | 1.24% | 1.23% | 1.31% | the thread-local getter — still closed |
| `Buf.push<Frame>` | 1.03% | 1.20% | 1.75% | one per call that pushes a frame |
| `gc.collect` | 0.69% | 1.07% | 1.16% | 5.3% of `csv` |
| `_platform_memset` | 1.03% | 1.04% | 0.87% | zeroing a payload |
| `added` | 1.10% | 1.01% | — | `Add`'s arm |
| **`compose_unpack_slots`** | 0.83% | **1.00%** | — | **new**: a cold arm `inline-fused` moved out — 11.1% of `loops` |
| `hash_str` | 1.06% | 0.97% | 0.67% | 5.1% of `globals` |
| **`Buf.set<Value>`** | 0.70% | **0.86%** | — | **new** under its own name — 5.6% `loops`, 4.3% `funcs` |
| `lay_standing` | 0.73% | 0.83% | 0.87% | the standing-argument call path |
| `read_field_site` | 0.66% | 0.74% | 0.80% | the inline cache's read |
| `methods_of` | 0.29% | 0.65% | 0.73% | 12.1% of `mapset` and invisible elsewhere |
| `find_entry` | 0.30% | 0.56% | 0.80% | 8.7% of `mapset` |
| **`Buf.push<Value>`** | **0.17%** | **0.17%** | 0.88% | **inlined by sysl 0.0.124 — confirmed gone** |
| **the four `fused_*`** | **0.00%** | **0.00%** | **7.41%** | **absorbed into `run_frames` by `inline-fused`** |

**Rolled up, weighted:**

| group | weighted | profile 3 | what is in it |
|---|---|---|---|
| **the dispatch** (`run_frames` self) | **35.26%** | 29.08% | one symbol, now carrying the four fused arms |
| **the dispatch + the fused arms** | **35.26%** | **36.49%** | the honest comparison, and it barely moved |
| **allocation and the collector** | **11.88%** | 12.08% | `gc.alloc` 6.23 + `gc.collect` 1.07 + `maybe_collect_on` 1.34 + `rebuild_free` 0.56 + `memset` 1.04 + `__bzero` 0.68 + the rest |
| **the call path** | **5.29%** | 5.70% | `placed_call` 2.62 + `Buf.push<Frame>` 1.20 + `lay_standing` 0.83 + `Buf.at<Frame>` 0.45 |
| **field and method lookup** | **7.41%** | 7.35% | `key_here` 1.51 + `field_from_site` 1.46 + `read_field_site` 0.74 + `find_entry` 0.56 + `obj_put` 0.56 + `methods_of` 0.65 + the rest |
| **`match_walk`** | **4.49%** | 4.59% | one symbol |
| **`Map<string, *>` plus `hash_str`** | **3.91%** | 4.03% | the `globals` name path |
| **ARC and the malloc/free under it** | **2.24%** | 3.81% | `_xzm_free` 1.31 + three malloc symbols. **The unnamed `???` region does not reach the floor at all this time** |
| **`memmove`/`memcpy`** | **2.46%** | 2.52% | almost all of it `strings` |
| **`Buf.push<Value>`** | **0.17%** | 0.88% | the counted push, now inlined by the compiler |

**The two structural facts to read off this table.** `run_frames` plus the fused arms was 36.49% and
is 35.26%: **taking the four `bl`s out really did remove work**, about 1.2 points of weighted wall,
which is what `inline-fused` was measuring when it read −1.96%. And `Buf.push<Value>` went 0.88% to
0.17%, which is what the 0.0.124 witness was measuring. **Both changes did exactly what they claimed
and the wall clock is flat anyway**, because what each one saved the other spent on the allocator's
behalf. That is the shape of the finding, and no third mechanism is needed to explain it.

### Per program, the top five

| benchmark | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| arith | `run_frames` 84.0 | `multiplied` 6.3 | `added` 3.4 | — | — |
| reals | `run_frames` 59.3 | `arith` 12.4 | `real_arith` 10.9 | `maybe_collect_on` 5.4 | `subtracted` 3.9 |
| globals | `run_frames` 12.2 | `Map.find` 12.2 | `_xzm_free` 7.9 | `Map.put` 7.1 | `Map.get<string,bool>` 5.9 |
| funcs | `run_frames` 66.5 | `placed_call` 11.0 | `Buf.set<Value>` 4.3 | `lay_standing` 3.7 | `maybe_collect_on` 3.0 |
| fib | `run_frames` 68.3 | `placed_call` 9.6 | `maybe_collect_on` 5.2 | `Buf.push<Frame>` 3.7 | `subtracted` 3.4 |
| calls | `run_frames` 20.1 | `gc.alloc` 19.9 | `placed_call` 4.1 | `memset` 3.8 | `gc.collect` 3.2 |
| methods | `run_frames` 48.7 | `key_here` 12.3 | `field_from_site` 10.2 | `read_field_site` 5.8 | `multiplied` 3.9 |
| closures | `run_frames` 60.7 | `Map.find` 6.5 | `maybe_collect_on` 4.8 | `placed_call` 4.2 | `Map.get` 4.2 |
| nested | `run_frames` 37.0 | `match_walk` 19.4 | `placed_call` 7.7 | `Buf.push<Frame>` 5.1 | `compose_unpack_slots` 4.8 |
| loops | `match_walk` 36.6 | `run_frames` 32.9 | `compose_unpack_slots` 11.1 | `multiplied` 6.9 | `Buf.set<Value>` 5.6 |
| options | `run_frames` 33.3 | `match_walk` 12.7 | `scan_named` 6.2 | `<deduplicated_symbol>` 4.3 | `obj_get_name` 4.1 |
| fields | `run_frames` 50.0 | `field_from_site` 16.1 | `key_here` 11.7 | `read_field_site` 8.9 | `added` 3.9 |
| alloc | `gc.alloc` 25.4 | `run_frames` 17.9 | `gc.collect` 4.2 | `memset` 4.2 | `Buf.grow<Entry>` 3.4 |
| arrays | `run_frames` 33.0 | `mach_absolute_time` 9.5 | `malloc_tiny` 4.9 | `properties_of` 4.0 | `_xzm_free` 4.0 |
| mapset | `run_frames` 24.3 | `methods_of` 12.1 | `find_entry` 8.7 | `_tlv_get_addr` 5.2 | `call_native` 4.0 |
| dispatch | `run_frames` 60.5 | `match_walk` 18.4 | `placed_call` 4.3 | `Buf.push<Frame>` 2.9 | `maybe_collect_on` 2.1 |
| branches | `run_frames` 84.3 | `remainder_of` 6.4 | `match_walk` 3.0 | `is_equal` 2.2 | — |
| sorting | `merge_sort` 54.8 | `int_arith` 15.1 | `arith` 13.7 | `on_values` 9.4 | `copy<Value>` 3.4 |
| csv | `gc.alloc` 28.5 | `run_frames` 7.7 | `gc.collect` 5.3 | `do_split` 3.5 | `find_from` 3.2 |
| strings | `memmove` 83.7 | `trace_env` 4.5 | `mach_absolute_time` 2.3 | `mark_value` 1.8 | `run_frames` 1.3 |

**`branches` is now four names and `arith` three.** Absorbing the fused arms did not change where the
time is, only what it is called: `branches` was `run_frames` 65.7 + three `fused_*` at 20.2 and is
`run_frames` 84.3, and `arith` was 51.4 + 27.4 and is 84.0. **A symbol that disappears from a profile
because it was inlined is not a cost that went away**, which is the reading this page exists to make
explicit.

### Per instruction, and the D/E fit recomputed

Instruction counts from `sysl build . --features profile` on the same commit, `run_frames` self time
from the samples above, wall from the best-of-9 run. `ns per instruction` is `run_frames`' self time
divided by every instruction the program executed. The **inline share** is the fraction of executions
whose arm stays inside the loop, with the four fused kinds now counted as inside and the seven arms
`inline-fused` moved to `run_compose.sysl` now counted as out.

| program | instructions | `run_frames` self | ns per instruction | inline share | the largest arms that STAY inside |
|---|---|---|---|---|---|
| branches | 121,451,942 | 84.3% | **2.40** | 85.1% | `LoadSlotInt` 22.6, `JumpIfFalse` 11.6, `PushInt` 10.0, `AddStoreSlot` 6.8, `Equal` 6.7 |
| arith | 130,000,025 | 84.0% | **1.74** | 69.2% | `PushInt` 15.4, `LoadSlotInt` 15.4, `LessJumpIfFalse` 7.7, `StoreSlot` 7.7, `LoadSlot2` 7.7 |
| fib | 119,760,624 | 68.3% | **2.95** | 47.6% | `LoadSlotInt` 19.0, `LoadDef` 9.5, `LessJumpIfFalse` 9.5, `LoadSlot` 4.8 |
| funcs | 72,000,027 | 66.5% | **2.18** | 66.7% | `LoadSlotInt` 16.7, `LoadSlot` 11.1, `AddStoreSlot` 11.1, `PushInt` 5.6 |
| closures | 60,000,033 | 60.7% | **2.42** | 60.0% | `LoadSlotInt` 13.3, `LoadSlot` 13.3, `AddStoreSlot` 13.3, `LessJumpIfFalse` 6.7 |
| dispatch | 140,000,026 | 60.5% | **2.03** | 75.0% | `TestSlots` 12.5, `JumpIfFalse` 12.5, `PushInt` 7.1, `LoadSlotInt` 7.1 |
| reals | 130,000,027 | 59.3% | **1.61** | 69.2% | `PushReal` 15.4, `LoadSlotInt` 15.4, `LessJumpIfFalse` 7.7, `StoreSlot` 7.7 |
| fields | 75,000,032 | 50.0% | **1.74** | 53.3% | `LoadSlotInt` 13.3, `LoadSlot` 13.3, `LessJumpIfFalse` 6.7, `LoadSlot2` 6.7 |
| methods | 111,000,068 | 48.7% | **2.35** | 45.9% | `LoadSlot` 24.3, `LoadSlotInt` 8.1, `AddStoreSlot` 5.4 |
| nested | 84,108,048 | 37.0% | **2.10** | 35.7% | `LoadSlot2` 14.3, `Jump` 7.1, `AddStoreSlot` 7.1, `LoadSlot` 7.1 |
| options | 86,000,037 | 33.3% | **2.24** | 62.8% | `LoadSlot` 16.3, `JumpIfSet` 9.3, `PushInt` 4.7, `LoadSlotInt` 4.7 |
| arrays | 91,000,521 | 33.0% | **1.58** | 70.3% | `LoadSlot2` 17.6, `AddStoreSlot` 17.0, `Jump` 11.5, `LessJumpIfFalse` 6.0 |
| loops | 64,138,039 | 32.9% | **1.51** | 50.0% | `Jump` 12.5, `LoadSlot` 12.5, `AddStoreSlot` 12.5, `LoadSlot2` 12.5 |
| mapset | 34,015,042 | 24.3% | **1.75** | 70.6% | `LoadSlotInt` 11.8, `LoadSlot2` 11.8, `PushInt` 11.8, `Discard` 11.8 |
| calls | 48,000,046 | 20.1% | **2.29** | 50.0% | `LoadSlot` 12.5, `LoadSlotInt` 12.5, `PushStr` 8.3, `LessJumpIfFalse` 4.2 |
| alloc | 57,000,025 | 17.9% | **1.90** | 68.4% | `LoadSlotInt` 15.8, `LoadSlot` 10.5, `PushStr` 10.5, `AddStoreSlot` 10.5 |
| globals | 102,000,020 | 12.2% | **1.33** | 35.3% | `PushInt` 23.5, `LessJumpIfFalse` 5.9, `Jump` 5.9 |
| csv | 14,340,921 | 7.7% | **1.98** | 43.5% | `LoadSlotInt` 13.0, `LoadSlot` 8.6, `DeclareSlot` 8.4, `PushStr` 4.5 |

**THE FIT STILL WILL NOT PAY FOR AN ARM TERM, AND IT IS SHARPER ABOUT IT THAN LAST TIME.** Fitting
`run_frames`' self time as `D × (instructions) + E × (instructions whose arm stays inside)` by least
squares over the eighteen programs that take any gives **D = 2.10 ns and E = −0.11 ns**; the
single-term fit is **2.03 ns per instruction**. A negative `E` is a fit saying the inline share
carries no signal at all — the third profile's `E` was 0.00 ns and this is the same answer with the
fused work moved inside the term being fitted. **So the arms are still not where the dispatch's time
goes**, even now that four of the busiest ones are inside it.

**`D` went from 1.30 ns to 2.10 ns and almost all of that is bookkeeping rather than a slowdown.** The
third profile's `run_frames` did not contain the fused arms, so their time sat in four other symbols
and outside the fit; this one's does. The figure to compare across pages is the whole-program one
below, which is the same denominator in both builds.

| program | instructions | ns/insn control P | ns/insn dev Q | change |
|---|---|---|---|---|
| branches | 121,451,942 | 2.667 | 2.845 | **+6.66%** |
| closures | 60,000,033 | 3.844 | 3.981 | +3.58% |
| funcs | 72,000,027 | 3.208 | 3.285 | +2.39% |
| dispatch | 140,000,026 | 3.293 | 3.357 | +1.94% |
| loops | 64,138,039 | 4.518 | 4.600 | +1.83% |
| fields | 75,000,032 | 3.429 | 3.481 | +1.53% |
| reals | 130,000,027 | 2.688 | 2.716 | +1.01% |
| fib | 119,760,624 | 4.286 | 4.325 | +0.91% |
| alloc | 57,000,025 | 10.526 | 10.616 | +0.85% |
| mapset | 34,015,042 | 7.138 | 7.192 | +0.75% |
| arrays | 91,000,521 | 4.764 | 4.797 | +0.70% |
| arith | 130,000,025 | 2.069 | 2.069 | +0.02% |
| options | 86,000,037 | 6.726 | 6.724 | −0.02% |
| calls | 48,000,046 | 11.440 | 11.391 | −0.42% |
| methods | 111,000,068 | 4.866 | 4.818 | −0.98% |
| nested | 84,108,048 | 5.797 | 5.675 | −2.11% |

**The instruction counts are identical between the two binaries**, `inline-fused` having changed only
how an arm is reached, so this table is the wall-clock one divided by a constant and carries the same
sign per row. It is here because the per-instruction figure is what the last three pages ranked on,
and it says the same thing: the price of an instruction went **up** on the programs that are mostly
dispatch, and down on the three that are mostly something else.

### The re-ranked shortlist

Share is the weighted aggregate above. A ceiling is what an item could take off the geometric mean if
it removed **all** of the named cost, which none will.

| rank | candidate | measured share | ceiling | kind | files |
|---|---|---|---|---|---|
| ~~**1**~~ | **DONE 2026-09-22 (`unfuse`), and the measurement held: the four arms are calls again and the twenty read −0.70%, `branches` −6.7%, `closures` −3.2%, `funcs` −2.6%. [The write-up](2026-09-22-unfuse.md) timed three binaries from one worktree, twice. What LANDED is variant 1a — the arms out of line, the cold arms left in `run_compose.sysl`.** ~~REVERT `inline-fused`, or reshape it so the four arms are calls again~~: — the four superinstruction arms were written out inside `run_frames` when `Buf.push<Value>` was still an out-of-line call. sysl 0.0.124 inlined the push into the same saturated function, and the two cannot both have the registers: the allocator now spills three of `run_frames`' own parameters at entry, `u` among them. **The full revert is MEASURED, not estimated: −1.19% geometric mean, `branches` −6.2%, `closures` −3.5%, `funcs` −2.3%** (this page's P-against-Q table read the other way). `run_frames` grows 40,300 → 49,232 bytes, which is not the thing that matters | **35.26%** is the dispatch; the item is the 1.19% of it this change costs | **1.2%, measured** | REVERT, wholly slate's | `run_frames.sysl`, `run_fused.sysl`, `run_compose.sysl`, `tests_fused.sysl` |
| ~~**1a**~~ | **DONE 2026-09-22 and it is what landed. Measured against the full revert it is 0.09–0.26% behind over two runs, which is inside the instrument — so the cold-arm move is worth NOTHING either way and stays, `run_frames.sysl` being 941 lines with it and 994 without.** ~~the variant worth measuring first~~: put the four arms back out of line **and keep the seven cold arms in `run_compose.sysl`**. The full revert does both, and only the pair was ever measured together — the cold-arm move is what made `compose_unpack_slots` (1.00% weighted, 11.1% of `loops`) and `Buf.set<Value>` (0.86%) visible, and it may be carrying part of the −1.19% rather than fighting it | — | **1.2% or better** | REVERT, wholly slate's | the same four files |
| 2 | **THE FIELD AND METHOD LOOKUP, AFTER the inline caches** — `key_here` is the cache's validity check at 12.3% of `methods` and 11.7% of `fields`; a shape token compared as one integer would replace a key comparison. **Unchanged in price from profile 3** | **7.41%**; 30.7% of `fields`, 28.3% of `methods`, 20.8% of `mapset` | **2–4%** | INCREMENTAL, wholly slate's | `index.sysl`, `table.sysl`, `run_frames.sysl` |
| 3 | **`match_walk` — `for` heads, `match` arms, destructuring** — a `for` over an array with a bare-name head does not need the pattern matcher at all. **Re-priced slightly up on reach**: `compose_unpack_slots` at 1.00% is the same work under a second name now, so the group is 5.49% rather than 4.49% | **4.49%** + 1.00%; 47.7% of `loops`, 24.2% of `nested`, 18.4% of `dispatch` | **2–3%** | INCREMENTAL, wholly slate's | `match.sysl`, `index.sysl`, `run_frames.sysl`, `run_compose.sysl` |
| 4 | **MODULE-LEVEL `var` CELLS, `StoreDef`** — confirmed again: the `Map<string,*>` work is 36.6% of `globals` and the `free`/`malloc` churn another ~13%, so still about half of one program | **3.91%**, and ~50% of `globals` | **0.6–0.9% of the mean** | INCREMENTAL, wholly slate's | `defs.sysl`, `emit.sysl`, `compile.sysl` |
| 5 | **A NARROWER `Ins`, so the dispatch head fetches less** — and this page adds the first evidence for it. The dispatch is 35.3% of weighted wall, the arm term of the fit is still zero, and the one change that *did* move the dispatch's cost moved it through **register pressure inside the loop**. A smaller `Ins` is the one item that lowers both the fetch and the number of live values the head needs. **Still measure before building**: the threefold ns/instruction spread (1.33 to 2.95) has not been explained | **35.26%** is the dispatch; the fetch is an unmeasured fraction of it | **unknown** | OPEN QUESTION | `vm.sysl` (`Ins`), `emit.sysl`, `run_frames.sysl` |

**And what came off or stayed off.**

| | candidate | what this page says |
|---|---|---|
| — | ~~**Inline the four superinstruction arms**~~ (profile 3's item 1) | **UNDONE 2026-09-22 (`unfuse`), and the four are calls again.** It measured −1.96% against a compiler that had not yet inlined `Buf.push` and **+1.19%** against the one that has; putting it back read **−0.70%** over the twenty. See item 1 and [the write-up](2026-09-22-unfuse.md) |
| — | ~~**Inline `Buf.push`**~~ | **DONE in sysl 0.0.124 and it stays done.** `Buf.push<Value>` is **0.17%** weighted, from 0.88% and from 15.34% two profiles ago. Its wall-clock value is hostage to item 1 and is not the thing to undo |
| — | ~~**Stop re-asking `current()`**~~ | **STILL DONE.** `_tlv_get_addr` 1.23%, flat against profile 3's 1.31% |
| — | **Per-call allocation in `calls` and `csv`** | **STILL a `sh.sysl.gc` item rather than a slate one.** `gc.alloc` is 28.5% of `csv` and 19.9% of `calls`, and it is the allocator's own code |
| — | **A register machine instead of a stack machine** | **RE-PRICED DOWN AGAIN.** `LoadSlot`, `LoadSlot2`, `LoadSlotInt` and `PushInt` are still ~26% of executions, but this page says the dispatch's cost is sensitive to *register pressure inside `run_frames`*, and a register machine widens `Ins` and adds live values to the very function that has none spare. **Measure a narrower `Ins` (item 5) before pricing this again** |
| — | **A narrower `Value`, or NaN-boxing** | **STRUCK as a near-term item**, unchanged from profile 3: 1–3% for a change that reaches the collector, the tables, both back ends and every native |
| — | **`strings` quadratic concatenation** | **STRUCK for the mean, unchanged.** 83.7% `memmove` on one program that is already 1.2x CPython |

### What the samples say plainly, beside the first three profiles

- **A PROFILE CANNOT SEE A CHANGE THAT MOVED COST INTO A FUNCTION IT WAS ALREADY MEASURING.**
  `run_frames` went 29.08% to 35.26% and the four `fused_*` names went to zero, which reads exactly
  like a successful inlining and says nothing whatever about whether the program got faster. It did
  not. **The A/B is what answered the question and the samples are what explained it**; neither would
  have done on its own.
- **TWO OPTIMISATIONS THAT EACH MEASURE WELL ALONE CAN BE WORTH NOTHING TOGETHER, AND THE ONLY
  INSTRUMENT FOR THAT IS MEASURING THE PAIR.** `inline-fused` was measured against `bf4dd9b`; the
  0.0.124 pickup was measured against `bf4dd9b`. Both controls were honest and both were the same
  tree, and the combination was never measured until the 0.0.124 page re-ran it and found the wash.
  **Where two items compete for one resource, the second one's control has to be the first one's
  result.**
- **`run_frames` HAS NO REGISTERS LEFT, AND THAT IS A STANDING FACT RATHER THAN THIS COMMIT'S.** Six
  callee-saved pairs and a 1,504-byte frame in both binaries, 16–17% of the body being stack traffic
  in both. **Every future change to the dispatch is a change to what gets a register**, whatever it
  looks like in the source, and an item that adds a live value to the loop is paying a price the
  source does not show.
- **A SMALLER HOT FUNCTION IS NOT A FASTER ONE.** 40,300 bytes at +1.19% against 49,232 bytes as the
  control is the cleanest counter-example this project has produced to the reflex that inlining a
  call and shrinking the code are the same kind of win.
- **macOS `sample` collapses to symbols and cannot attribute inside a function**, so the fourth
  profile hits the ceiling the third one was approaching: with the arms inside `run_frames`, this
  instrument can no longer say anything about them at all. **Answering "which arm" now needs a
  different instrument**, and that is a decision for whoever picks up item 5.
- **The position is unchanged from the QuickJS run**, this tree being within a percent of `a642e9f`'s:
  3.5x Lua, 2.7x `node --jitless`, **1.8x CPython**, 2.2x QuickJS-ng on the geometric mean.
