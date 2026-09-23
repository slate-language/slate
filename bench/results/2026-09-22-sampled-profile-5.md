# A fifth sampled profile, and the dispatch finally has a number (dev `5aa3520`, sysl 0.0.125)

**THE DISPATCH HEAD IS NOT A SHARE OF `run_frames` — IT IS ABOUT HALF OF IT, AND IT IS THE HOTTEST
CODE IN THE INTERPRETER BY BOTH INSTRUMENTS AT ONCE.** Four profiles said `run_frames` was a third of
the weighted wall and none of them could say what inside it. The offset instrument the `gc.alloc`
investigation added answers it: **of the nineteen programs where `run_frames` appears as a leaf node
at all, eighteen have BOTH of their two hottest program counters inside a twenty-two instruction
block that no arm ever reaches — the instruction fetch and the indirect jump.** The one exception is
`fib`. And reading the jump tables against the executed instruction mix puts the same block at
**38–62% of every machine instruction the loop runs, 46% unweighted over the twenty**.

**So the structural items have their number.** The dispatch is 30.93% of weighted wall; the head is
about 46% of that, so **roughly 14 points of weighted wall is fetch and decode** — reloading three
spilled pointers, two bounds checks that cannot fail, a `madd` by 56, four loads that pull all 56
bytes of an `Ins` whatever the arm wants, and a two-level jump table. That is the budget a narrower
`Ins` and a threaded dispatch are competing for, and it is much larger than any arm-level item left.

**AND THE ARM TERM OF THE FIT IS ZERO FOR THE THIRD PAGE RUNNING, WHICH NOW READS AS A RESULT RATHER
THAN A DISAPPOINTMENT.** `D = 1.67 ns, E = −0.03 ns`; the single-term fit is `1.65 ns` per
instruction, down from profile 4's `2.03`. The fit has been saying since profile 3 that what an
instruction *does* barely moves the price of executing it — and the reason is now visible in the
disassembly rather than inferred: about half the machine instructions are spent getting to the arm.

**THE FIVE ITEMS THAT LANDED SINCE PROFILE 4 ARE ALL VISIBLE IN THE TABLE AND ALL DID WHAT THEY
CLAIMED.** `unfuse` put the four superinstruction arms back out of line, so `fused_*` are four
symbols again (6.99% weighted between them). `lookup-hit-path` collapsed `key_here` and
`field_from_site` into `field_here`. `match_leaf` split the pattern matcher and `match_walk` fell
from 4.49% to 1.79%. `module-cells` took `Map.find`, `Map.get` and `hash_str` off `globals`. `gc`
0.2.4 took the bin scan out of `gc.alloc`, whose two hottest offsets have moved from `+396/+404` to
somewhere else entirely — see below.

### How it was taken

**Identical to the first four profiles, so all five are comparable.** macOS `/usr/bin/sample` at a
1 ms interval, each program started and sampled in one shell call, run serially under
`caffeinate -dimsu`, against a plain (`-O2`, no `--features profile`) build of dev `5aa3520`.
`sample`'s **"Sort by top of stack, same collapsed"** section is self time and is what every figure
below reads; the denominator is the main thread's sample total from the call graph's head.

- **The same twenty of the twenty-three programs**, for the reason the first page gives — `startup`,
  `strindex` and `strwalk` exit before the sampler can attach.
- **6,519 samples**, against profile 4's 7,255 on the same twenty at the same interval. **The tree is
  about 10% faster in sampled wall**, which is the five landed items showing up as a smaller
  denominator rather than as a moved share.
- **The box: 93.2% idle before sampling.** `pgrep -x java` was **not** empty — two idle Gradle and
  Kotlin daemons belonging to the `work` account, at 0.2% and 0.0% CPU and nearly two hours old. They
  are not builds and no timing claim is made on this page; every figure here is a *share*, which a
  quiet background process cannot move.
- `sample` truncates its self-time table at 5 samples per name, so a per-program column sums to under
  100%.
- **Weights are each program's slate/CPython ratio from
  [the `gc` 0.2.4 run](2026-09-22-gc-0-2-4.md)'s `run.sh` table**, which is this same commit. Profile
  4 weighted by the QuickJS page's ratios, so the weighted columns are close but not exactly
  comparable across the two pages; the unweighted ones are.

### The offset instrument, and what it can and cannot do

`sample`'s call graph prints a leaf as `symbol + off,off,… [0x…,0x…]` where the collapsed table
prints only the symbol, so attribution **inside** a function comes out of the ordinary sampler. Take
the offsets, add the function's address from `nm -pa`, look the result up in `otool -tv`.

**The limit, which cost this page an afternoon before it was accepted: the list is truncated at TWO
offsets per node, always.** That was enough for `gc.alloc`, whose answer was a six-instruction loop.
It is not enough to split a 37,268-byte dispatch into a hundred arms. An lldb-driven PC sampler was
written to get the full histogram and is **not** what produced the numbers below — it deadlocked
against its own child and was abandoned. What replaced it needs no sampler at all:

- **What the two hottest PCs per program say** is a ranking, and a ranking over twenty programs is a
  strong statement even at two samples deep. It is the first table below.
- **What the jump tables say** is exact. The dispatch ends in
  `ldrh w10,[x11,x8,lsl #1]; add x9,x9,x10,lsl #2; br x9`, so the table is 16-bit word-scaled
  displacements from an `adr`-computed base; reading it out of the binary gives **every arm's entry
  point**, and walking the disassembly from each entry to its first unconditional exit gives **every
  arm's straight-line length**. Combined with the executed instruction mix from
  `SLATE_PROFILE=1` on a `--features profile` build, that is a head-against-arm split per program
  with no sampling in it at all.

### The dispatch head, instruction by instruction

`run_frames` is at `0x10021c384` and runs to `0x100225520` — **37,268 bytes**. Every VM instruction
passes through this, and nothing else does:

```
+508  ldr  x8, [sp, #0x220]       spill reload  -- the code buffer's length
+512  cmp  x26, x8
+516  b.hs <trap>                 a bounds check that cannot fail
+520  ldr  x8, [sp, #0x230]       spill reload  -- the length again, a second copy
+524  cmp  x28, x8
+528  b.hs <trap>                 the same bounds check, again
+532  mov  w8, #0x38              sizeof(Ins) = 56
+536  ldr  x9, [sp, #0x228]       spill reload  -- the code buffer's base
+540  madd x9, x28, x8, x9        base + pc * 56
+544  ldp  x27, x19, [x9, #0x18]
+548  ldp  x23, x22, [x9, #0x8]
+552  ldr  w8,       [x9]         the tag
+556  ldp  x24, x25, [x9, #0x28]
+560  add  x26, x28, #0x1         pc + 1
+564  cmp  w8, #0x68
+568  b.hi <the second table>
+572  adrp x11, ...
+576  add  x11, x11, #0x378
+580  adr  x9,  #-152
+584  ldrh w10, [x11, x8, lsl #1]
+588  add  x9, x9, x10, lsl #2
+592  br   x9
```

**Twenty-two instructions, and they divide into four costs, none of which is the arm's work.**

| what | instructions | note |
|---|---|---|
| **spill reloads** | 3 | `[sp,#0x220]`, `[sp,#0x228]`, `[sp,#0x230]` — the code buffer's base and its length, re-read from the frame on **every** instruction. Profile 4's "`run_frames` has no registers left" wearing its own address |
| **bounds checks** | 4 | two `cmp`/`b.hs` pairs against the same length, neither of which can fail on generated code |
| **the `Ins` fetch** | 5 | `mov w8,#0x38`, `madd`, and **four loads pulling all 56 bytes** — three `ldp` and the tag — whatever the arm is about to want |
| **the indirect jump** | 10 | `add` for `pc+1`, the range check, `adrp`/`add`/`adr`/`ldrh`/`add`/`br` |

**AND THERE IS A SECOND JUMP TABLE, WHICH MOST OF THE HOT OPS GO THROUGH.** `cmp w8,#0x68` sends
any tag above 104 to `0x10021d2d0`, and the table itself sends **every tag from 27 upward** to the
same place, where

```
+3916  sub  w9, w8, #0x1b
+3920  cmp  w9, #0x52
+3924  b.hi <the default>
+3928  adrp x12, ... ; +3932  add x12, x12, #0x44a ; +3936  adr x10, #16
+3940  ldrh w11, [x12, x9, lsl #1]
+3944  add  x10, x10, x11, lsl #2
+3948  br   x10
```

does the whole thing again. **So `Op` splits at tag 27: the first twenty-seven arms cost one indirect
branch and every other arm costs two** — nine more instructions and a second unpredictable jump.
`JumpIfFalse`, `Jump`, `Equal`, `Mul`, `Rem`, `Pop`, `CallFn`, `Ret`, `TestSlots` and all four
`fused_*` are on the far side of that split. `+3940` — the second table's own `ldrh` — is one of the
two hottest PCs in the whole loop on `arith`, `nested`, `arrays` and `csv`.

### The hottest program counters inside `run_frames`

The two offsets `sample` prints for the loop's leaf node, per program, with what `otool -tv` says is
there. `sorting` has no `run_frames` node above the five-sample floor.

| offset | what it is | the programs whose top two include it |
|---|---|---|
| **+556** | `ldp x24,x25,[x9,#0x28]` — **the last 16 bytes of the 56-byte `Ins`** | 18 of 19 |
| **+508** | `ldr x8,[sp,#0x220]` — **the spilled length, reloaded for the bounds check** | 15 of 19 |
| **+3940** | `ldrh w11,[x12,x9,lsl #1]` — **the second jump table's load** | `arith`, `nested`, `arrays`, `csv` |
| +584 | `ldrh w10,[x11,x8,lsl #1]` — the first jump table's load | `fields` |
| +1632 | `ldr x1,[x20,#0x338]` — a bounds check inside `LoadDef`'s arm | `fib` |
| +1048 | `and x8,x23,#0xff000000` — the tag test inside `LoadSlot`'s arm | `fib` |

**Eighteen of nineteen programs have both hottest counters in the head; `fib` has neither.** That one
exception is the honest shape of the finding rather than noise: `fib` is the most call-heavy program
on the list, so more of its time sits in arms that do real work, and `placed_call` is 8.0% of it
besides.

### The head against the arms, from the jump tables

Head is 22 machine instructions, plus 6 more for a tag on the far side of the split — **a floor,
since the second-level sequence is really 9**. Arm is the straight-line run from the arm's entry to
its first unconditional exit, which undercounts a branchy arm and is exact for most. `unmapped` is
the share of executions whose op is one of the four `fused_*`: those are out-of-line calls since
`unfuse`, so they pay the head and then a `bl`, and they have no arm inside the loop to measure.

| program | executed | head / insn | arm / insn | **dispatch share** | unmapped |
|---|---|---|---|---|---|
| loops | 64,138,039 | 26.8 | 16.6 | **61.8%** | 37.5% |
| arrays | 91,000,521 | 26.3 | 21.8 | **54.6%** | 58.2% |
| reals | 130,000,027 | 24.6 | 21.6 | **53.3%** | 46.2% |
| globals | 102,000,020 | 23.2 | 20.7 | **52.9%** | 11.8% |
| arith | 130,000,025 | 24.6 | 24.7 | **49.9%** | 46.2% |
| alloc | 57,000,025 | 24.2 | 26.0 | **48.2%** | 42.1% |
| branches | 121,451,942 | 26.2 | 28.3 | **48.1%** | 38.5% |
| fields | 75,000,032 | 25.3 | 27.7 | **47.8%** | 40.0% |
| nested | 84,108,048 | 26.7 | 31.1 | **46.2%** | 35.7% |
| strings | 2,100,026 | 24.6 | 29.0 | **45.9%** | 50.0% |
| sorting | 303,250 | 25.7 | 30.9 | **45.5%** | 46.7% |
| mapset | 34,015,042 | 26.2 | 34.0 | **43.5%** | 41.2% |
| options | 86,000,037 | 24.5 | 32.0 | **43.4%** | 27.9% |
| csv | 14,340,921 | 25.0 | 33.1 | **43.0%** | 21.9% |
| dispatch | 140,000,026 | 26.4 | 35.7 | **42.5%** | 32.1% |
| methods | 111,000,068 | 25.3 | 35.3 | **41.8%** | 27.0% |
| funcs | 72,000,027 | 24.0 | 34.8 | **40.8%** | 50.0% |
| closures | 60,000,033 | 25.4 | 37.0 | **40.7%** | 53.3% |
| calls | 48,000,046 | 24.6 | 37.4 | **39.7%** | 33.3% |
| fib | 119,760,624 | 25.8 | 41.4 | **38.4%** | 47.6% |

**The head costs 23–27 machine instructions per VM instruction on every program in the set**, which
is the point: it does not vary, because it does not depend on what the instruction is. The arm varies
from 17 to 41 and *that* is the program-dependent part. **The median arm is 22 machine instructions
and the head is 22 to 31.** `Jump`'s arm is two instructions and reaching it costs thirty-one.

**The two instruments agree and were built from different data.** The sampled counters say the
hottest addresses are in the head; the tables say the head is about half the machine instructions.
Neither could have said it alone, and the second needs no sampler, so it can be re-run on any commit.

### The aggregate

| self time | unweighted | weighted | profile 4 wtd | what it is |
|---|---|---|---|---|
| `run_frames` | 29.65% | **30.93%** | 35.26% | the loop, **without** the four fused arms this time |
| `placed_call` | 2.19% | **2.67%** | 2.62% | which of the three call paths |
| `_platform_memmove` | 7.81% | **2.50%** | 2.46% | 82.5% of it is `strings` alone |
| `fused_load_slot_int` | 2.56% | **2.46%** | — | **back out of line** (`unfuse`) |
| `fused_add_store_slot` | 2.24% | **2.43%** | — | **back out of line** |
| `match_leaf` | 1.98% | **2.07%** | — | **new**: the matcher's 80-byte fast frame |
| `gc.alloc` | 1.29% | **2.06%** | 6.23% | **6.23% → 2.06% on `gc` 0.2.4** |
| `merge_sort` | 3.45% | **1.88%** | 1.72% | 53.3% of `sorting` |
| `field_here` | 1.60% | **1.85%** | — | **new**: `key_here` + `field_from_site`, merged by `lookup-hit-path` |
| `match_walk` | 1.50% | **1.79%** | 4.49% | **4.49% → 1.79%** |
| `<deduplicated_symbol>` | 1.93% | 1.70% | 1.39% | a folded body, not a function |
| `_xzm_free` | 2.12% | 1.59% | 1.31% | `free` — 12.0% of `globals` |
| `gc.collect` | 0.89% | 1.46% | 1.07% | 9.5% of `csv`, 6.9% of `alloc` |
| `fused_load_slot2` | 1.33% | 1.45% | — | back out of line |
| `Buf.push<Frame>` | 1.17% | 1.36% | 1.20% | one per call that pushes a frame |
| `_tlv_get_addr` | 1.17% | 1.11% | 1.23% | the thread-local getter — still closed |
| `compose_unpack_slots` | 0.92% | 1.09% | 1.00% | 12.7% of `loops` |
| `added` | 1.12% | 1.07% | 1.01% | `Add`'s arm |
| `multiplied` | 1.09% | 1.07% | 1.26% | `Mul`'s arm |
| `_platform_memset` | 1.06% | 1.06% | 1.04% | zeroing a payload |
| `maybe_collect_on` | 1.12% | 1.04% | 1.34% | the collection schedule, per safe point |
| `find_entry` | 0.49% | 0.93% | 0.56% | 12.7% of `mapset` |
| `Map.find<string,Value>` | 0.64% | 0.86% | 1.91% | **1.91% → 0.86%** (`module-cells`) |
| `lay_standing` | 0.80% | 0.82% | 0.83% | the standing-argument call path |
| `__bzero` | 1.06% | 0.81% | 0.68% | the allocator's zeroing |
| `fused_less_jump_if_false` | 0.80% | 0.65% | — | back out of line |
| `read_field_site` | 0.57% | 0.61% | 0.74% | the inline cache's read |
| `hash_str` | 0.58% | 0.54% | 0.97% | **0.97% → 0.54%** (`module-cells`) |

**Rolled up, weighted:**

| group | weighted | profile 4 | what is in it |
|---|---|---|---|
| **the dispatch + the four fused arms** | **37.92%** | 35.26% | the like-for-like figure; profile 4's number had the arms inside the loop |
| **of which the head** | **~14 points** | never measured | 46% of `run_frames`, from the table above — **the number this page exists for** |
| **allocation and the collector** | **7.78%** | 11.88% | `gc.alloc` 2.06 + `gc.collect` 1.46 + `maybe_collect_on` 1.04 + `memset` 1.06 + `__bzero` 0.81 + `rebuild_free` 0.50 + the rest |
| **the call path** | **5.16%** | 5.29% | `placed_call` 2.67 + `Buf.push<Frame>` 1.36 + `lay_standing` 0.82 + `Buf.at<Frame>` 0.31 |
| **field and method lookup** | **4.43%** | 7.41% | `field_here` 1.85 + `find_entry` 0.93 + `read_field_site` 0.61 + `field_from_site` 0.46 + `methods_of` 0.58 |
| **the pattern matcher** | **3.86%** | 4.49% | `match_leaf` 2.07 + `match_walk` 1.79 — and `match_leaf` is now the larger half |
| **`Map<string,*>` plus `hash_str`** | **1.78%** | 3.91% | what is left of the name path after `module-cells` |
| **`memmove`/`memcpy`** | **2.50%** | 2.46% | almost all of it `strings` |

**Three of the five landed items are legible here as a group falling.** Lookup 7.41% → 4.43%,
allocation 11.88% → 7.78%, the name path 3.91% → 1.78%. The dispatch did not fall, and with the
denominator 10% smaller it rose slightly as a share — which is exactly what happens when everything
around a fixed cost gets cheaper, and is why it is now the whole shortlist.

### Per program, the top five

| benchmark | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| arith | `run_frames` 59.9 | `fused_load_slot_int` 7.7 | `fused_less_jump_if_false` 6.6 | `multiplied` 6.0 | `subtracted` 5.5 |
| reals | `run_frames` 48.7 | `arith()` 13.0 | `fused_load_slot_int` 8.6 | `real_arith` 6.7 | `fused_add_store_slot` 4.8 |
| globals | `run_frames` 17.9 | `_xzm_free` 12.0 | `<deduplicated_symbol>` 10.4 | `Map.put<string,Value>` 8.0 | `__bzero` 7.0 |
| funcs | `run_frames` 58.1 | `placed_call` 7.8 | `added` 6.6 | `fused_add_store_slot` 6.6 | `fused_load_slot_int` 4.8 |
| fib | `run_frames` 60.5 | `placed_call` 8.0 | `fused_load_slot_int` 7.3 | `fused_less_jump_if_false` 4.0 | `maybe_collect_on` 3.8 |
| calls | `run_frames` 19.4 | `gc.alloc` 8.1 | `field_here` 5.7 | `placed_call` 5.1 | `malloc_tiny` 3.3 |
| methods | `run_frames` 42.2 | `field_here` 13.1 | `read_field_site` 5.4 | `multiplied` 4.9 | `lay_standing` 4.6 |
| closures | `run_frames` 47.9 | `fused_add_store_slot` 6.5 | `placed_call` 4.7 | `Buf.push<Frame>` 4.7 | `Map.find<string,Value>` 4.1 |
| nested | `run_frames` 36.9 | `Map.find<string,Value>` 8.1 | `match_walk` 6.5 | `match_leaf` 6.5 | `placed_call` 5.4 |
| loops | `run_frames` 33.2 | `match_walk` 21.0 | `compose_unpack_slots` 12.7 | `match_leaf` 11.7 | `fused_load_slot2` 6.3 |
| options | `run_frames` 26.0 | `scan_named` 6.8 | `match_walk` 6.6 | `<deduplicated_symbol>` 5.3 | `Buf.grow<string>` 4.0 |
| fields | `run_frames` 45.0 | `field_here` 13.6 | `added` 7.1 | `read_field_site` 6.5 | `write_named_at` 6.5 |
| alloc | `run_frames` 14.6 | `gc.alloc` 8.2 | `gc.collect` 6.9 | `_platform_memset` 5.8 | `_xzm_free` 4.0 |
| arrays | `run_frames` 19.6 | `mach_absolute_time` 11.8 | `_xzm_free` 7.8 | `fused_add_store_slot` 6.9 | `fused_load_slot2` 6.3 |
| mapset | `run_frames` 17.0 | `find_entry` 12.7 | `methods_of` 9.7 | `standing_native` 5.5 | `same_plain` 4.2 |
| dispatch | `run_frames` 52.5 | `match_leaf` 17.8 | `placed_call` 4.8 | `fused_load_slot_int` 4.5 | `Buf.push<Frame>` 3.7 |
| branches | `run_frames` 63.4 | `fused_load_slot_int` 10.2 | `fused_add_store_slot` 5.9 | `remainder_of` 5.5 | `is_equal` 5.1 |
| sorting | `merge_sort` 53.3 | `int_arith` 14.2 | `arith()` 13.5 | `on_values` 11.6 | `Buf.grow<Value>` 2.6 |
| csv | `gc.alloc` 10.3 | `gc.collect` 9.5 | `run_frames` 7.5 | `find_from` 4.8 | `<deduplicated_symbol>` 4.4 |
| strings | `memmove` 82.5 | `trace_env` 6.0 | `mark_value` 2.6 | `mach_absolute_time` 2.6 | — |

`arith()` is `dev.slatelang.slate$arith`, the numeric-tower helper, and not the benchmark of the same
name. **`match_leaf` doing 17.8% of `dispatch` and 11.7% of `loops` is `match-leaf` working as
designed** — `match_walk` used to carry that and the entries are now answered in an 80-byte frame.

### Per instruction, and the D/E fit recomputed

`ns per instruction` is `run_frames`' sampled self share of the wall from
[the `gc` 0.2.4 run](2026-09-22-gc-0-2-4.md)'s table, divided by every instruction the program
executed. **Inline share** is the fraction of executions whose arm is inside the loop — that is,
everything but the four `fused_*`.

| program | instructions | `run_frames` self | ns per instruction | inline share |
|---|---|---|---|---|
| branches | 121,451,942 | 63.4% | **1.74** | 61.5% |
| fib | 119,760,624 | 60.5% | **2.64** | 52.4% |
| arith | 130,000,025 | 59.9% | **1.30** | 53.9% |
| funcs | 72,000,027 | 58.1% | **1.89** | 50.0% |
| dispatch | 140,000,026 | 52.5% | **1.69** | 67.9% |
| reals | 130,000,027 | 48.7% | **1.35** | 53.9% |
| closures | 60,000,033 | 47.9% | **1.91** | 46.7% |
| fields | 75,000,032 | 45.0% | **1.42** | 60.0% |
| methods | 111,000,068 | 42.2% | **1.86** | 73.0% |
| nested | 84,108,048 | 36.9% | **2.08** | 64.3% |
| loops | 64,138,039 | 33.2% | **1.39** | 62.5% |
| options | 86,000,037 | 26.0% | **1.74** | 72.1% |
| arrays | 91,000,521 | 19.6% | **0.95** | 41.8% |
| calls | 48,000,046 | 19.4% | **1.74** | 66.7% |
| globals | 102,000,020 | 17.9% | **1.27** | 88.2% |
| mapset | 34,015,042 | 17.0% | **1.22** | 58.8% |
| alloc | 57,000,025 | 14.6% | **1.22** | 57.9% |
| csv | 14,340,921 | 7.5% | **1.66** | 78.1% |

**`D = 1.67 ns, E = −0.03 ns`; the single-term fit is `1.65 ns` per instruction.** Profile 3 got
`E = 0.00`, profile 4 got `E = −0.11`, and this is the third page with no arm term to find. **The
disassembly now explains it**: the inline share is the fraction of executions that avoid a `bl`, and
that `bl` is small beside twenty-two head instructions everything pays.

`D` fell from 2.10 to 1.67 ns because the four fused arms left `run_frames` while staying in the
denominator — the same bookkeeping profile 4 flagged in the other direction. The whole-program figure
is the comparable one and it fell too: the spread is now **0.95 to 2.64** against profile 4's 1.33 to
2.95.

### Where `gc.alloc`'s remaining time goes

`gc.alloc` is 2.06% weighted, from 6.23%, and **9.8% of `alloc.sl` has become 8.2%**. The offsets say
the six-instruction bin scan is gone: `+396` and `+404` do not appear on any program. What is there
instead, on all three allocation-dense programs:

| offset | what `otool -tv` says | `alloc` / `calls` / `csv` |
|---|---|---|
| **+1224** | `add x9, x13, #0x1` inside the **size-class computation** — `cmp x9,#0x800`, `lsr x12,x9,#10`, `cmp x12,#4`, `lsr x12,x12,#1`: an iterative classifier, not a table or a `leading_zeros` | 28 / 26 / 25 — the hottest node on each |
| **+1368** | `mov x0, x19` — the **epilogue immediately after `bl _bzero`** | 11 / — / 6 |
| +1264, +1304 | `strb w12,[x10,#0x22]`, `strh wzr,[x11,#0x20]` — the **header write** | second rank |
| +1152 | `ldr x9,[x10,#0x18]; cmp x9,#0x400` — the head of the same classifier | second rank |

**So the three things the `gc` 0.2.4 page predicted would be left are exactly what is left, in the
order it guessed wrong.** It named "the header write, the list link and the `_bzero`"; the samples put
**the size-class computation first**, the `_bzero` second and the header write third. The classifier
is a loop of shifts and compares where a `leading_zeros` and a shift would do — it is `sh.sysl.gc`'s
code and a package item, not slate's.

**What slate pays around it** is separate and visible: `_platform_memset` 1.06% and `__bzero` 0.81%
weighted, 5.8% and 7.0% of `alloc` and `globals`. **Every allocation is zeroed by the collector and
then overwritten by the constructor**, and `new_object` is not in the profile at all under its own
name, so the zeroing is the whole of what a construction pays outside `gc.alloc`. Removing the double
write needs an allocator entry point that does not zero, which is again the package's.

### The counted-string read on a field access

The `lookup-hit-path` write-up flagged `u.strings.at(k)` as possibly ~5% of `fields`. **Confirmed and
smaller: `sysl.buf$Buf.at.string` is 5 samples of `fields`' 169, so 3.0%, and it is the last name
above the five-sample floor on that program.** The call sites are
`site_cache.sysl:191` and `:203` — `read_field_of_kind(other, u.strings.at(k), at)` and
`write_named_at(vm, here, u.strings.at(k), u.string_hashes.at(k), …)`.

**Priced, it is not an item.** `fields` is 1.1x CPython, so 3.0% of it is 0.03 points of weighted
wall, and the hit path already avoids the name entirely — `field_here` answers from the stored hash
and the remembered position, which is why this only shows on the paths that miss. It stays a
correctness-shaped nicety rather than a speed item.

### Per program against CPython, worst first

From [the `gc` 0.2.4 run](2026-09-22-gc-0-2-4.md)'s `run.sh` table, which is this commit.

| program | vs CPython | its top symbol | what that says |
|---|---|---|---|
| csv | **3.7x** | `gc.alloc` 10.3, `gc.collect` 9.5 | still the allocator's program; `run_frames` is only 7.5% of it |
| calls | **3.2x** | `run_frames` 19.4, `gc.alloc` 8.1 | a frame per call plus an allocation per call |
| options | **2.7x** | `run_frames` 26.0, `scan_named` 6.8 | named-argument scanning is its own 6.8% |
| fib | **2.6x** | `run_frames` 60.5 | the purest dispatch program on the list |
| methods | **2.6x** | `run_frames` 42.2, `field_here` 13.1 | lookup is still a fifth of it after `lookup-hit-path` |
| nested | **2.4x** | `run_frames` 36.9, `Map.find` 8.1 | the last `Map<string,*>` of any size |
| mapset | **2.4x** | `run_frames` 17.0, `find_entry` 12.7 | the table's own probe |
| alloc | **2.2x** | `run_frames` 14.6, `gc.alloc` 8.2 | allocation, still |
| arrays | **2.2x** | `run_frames` 19.6, `mach_absolute_time` 11.8 | **11.8% is the benchmark's own clock**, not slate |
| dispatch | **2.1x** | `run_frames` 52.5, `match_leaf` 17.8 | dispatch and the matcher, and nothing else |

**Seven of the ten worst have `run_frames` first**, which is the same sentence as the head finding
read from the other end. **`arrays` spending 11.8% in `mach_absolute_time` is worth a separate look**
— that is the benchmark timing itself, so its 2.2x is flattered downward by about a tenth, and
whatever it measures, slate is not doing it.

### The re-ranked shortlist

Share is the weighted aggregate above. A ceiling is what an item could take off the geometric mean if
it removed **all** of the named cost, which none will. **Every item on this list is now in the
dispatch head**, which has not been true of any previous page.

| rank | candidate | measured share | ceiling | kind | files |
|---|---|---|---|---|---|
| ~~**1**~~ | **DONE 2026-09-23 (`narrow-ins`), half of it: `Op` 40 → 16 and `Ins` 56 → 32, geometric mean −2.06%, `fib` −9.2%, `arith` −7.1%, head 22 → 18 instructions with all three spill reloads gone. [The write-up](2026-09-23-narrow-ins.md). THE OTHER HALF WAS BUILT AND BACKED OUT: spans in a buffer beside the code, read as `span_base + pc`, reaches the 16 bytes and a 13-instruction head and measures +1.65% — a span is an ARGUMENT passed eagerly to every operator's leaf and once PER ARGUMENT at a call, so nine instructions off the head do not pay for four in every arm that does work. `+556` was the fetch's last load and not the span's cost.** ~~**A NARROWER `Ins`.** `Ins` is **56 bytes** — `op: Op` at 40 (the widest variant is four `usize`: `CheckSlot(i,k,t,pk)` and `CallMethod(k,argc,names,c)`) plus `at: Span` at 16 (two `usize`). The head pays `mov w8,#0x38`, a `madd`, and **four loads that pull all 56 bytes on every instruction** — 5 of 22 head instructions, plus the cache footprint of a 56-byte stride. Two independent shrinks: **box the four-field variants** so `Op` fits in 24, and **make `Span` a `u32` pair or an index into a side table**, which no arm reads on a hot path. `Ins` at 16 bytes is one `ldp`~~ | **30.93%** is the loop; the head is ~46% of it and the fetch ~23% of the head | **2–4%** | INCREMENTAL, wholly slate's | `code.sysl` (`Ins`, `Op`), `emit.sysl`, `run_frames.sysl` |
| **2** | ~~**ONE JUMP TABLE INSTEAD OF TWO.**~~ **LANDED (`one-jump-table`, 2026-09-22): geometric mean −2.69% on an alternating best-of-9** — `methods` −11.5%, `fib` −9.2%, `dispatch` −9.0%, `funcs` −7.7% — above this row's own ceiling. **The cause was the order the ARMS are written in, not the tag numbering this row guessed at**: the back end folds the first **forty-two** arms of the `match` into one switch and every arm after them shares a second, whichever forty-two they are. The first table's forty-two were exactly the arm list's first forty-two lines. The fix is the arm list in two blocks — the forty-two the benchmarks execute, then a marked cold block — plus five variants moved up in `Op` (`Tick` and the four fused pairs held tags 105–109, above any table the hot arms could span) and three moved down (`PushNull`/`PushUndefined`/`PushBool` held tags 0–2 and cost a `sub` on **every** dispatch, worth 1.4% on its own). The write-up is [here](2026-09-22-one-jump-table.md) | ~55% of executions paid it, ~9 of ~31 head instructions | **1–2%** | INCREMENTAL, cheap, wholly slate's | `code.sysl` (the `Op` order), `run_frames.sysl` |
| **3** | **THREADED DISPATCH — AND IT IS A `sysl` GAP, NOT A slate ITEM (see below).** Replacing the shared `br x9` with a jump at the end of each arm removes the 10-instruction jump-table sequence and, more importantly, gives each arm its own branch-predictor history — the standard 20–40% on an interpreter of this shape. **sysl cannot express it today**: there is no labels-as-values, and `@tailrec` is self-recursion only, so a token-threaded loop cannot be written. Reported as a gap | the indirect jump is 10 of 22 head instructions, ~46% of the loop | **4–8%**, the largest on the list | **SYSL GAP** — needs a language feature | `run_frames.sysl`, and sysl itself |
| ~~**4**~~ | **DONE 2026-09-23 (`for-head`): geometric mean −3.16%/−2.99%** over two alternating best-of-9 runs, against this row's 1–1.5% ceiling — `loops` **−30.6%/−33.1%**, `nested` **−15.1%/−13.7%**, `branches` −3.3%/−5.6%. `UnpackFixed` takes apart a binding whose pattern is a row of BARE NAMES — an array of `n` names or an object of `n` keys, no default, no `?`, no rest, nothing nested — writing the cells straight out of the subject, so the matcher is never entered; anything else still walks, and the complaint a subject that does not fit gets is `unpack_complaint`'s, the matcher's own. It is a BINDING SITE's rule rather than a `for` head's, so `val { a, b } = p` takes it too. Instruction counts identical to the instruction (`UnpackSlots` → `UnpackFixed`, 8M on `loops`, 6M on `nested`). [The write-up](2026-09-23-for-head.md) | ~~**A `for`-HEAD SHAPE INSTRUCTION** — what is left of profile 4's item 3. `match_leaf` 2.07% + `match_walk` 1.79% = **3.86%**, and `match_leaf` is 17.8% of `dispatch`, 11.7% of `loops`, 6.5% of `nested`. Compiling a simple `for` head into the instruction means the matcher is never entered at all. This is codegen, and `match-leaf`'s write-up already scoped it~~ | **3.86%**; 32.7% of `loops`, 17.8% of `dispatch` | **1–1.5%**, and it took **3%** | INCREMENTAL, wholly slate's | `match.sysl`, `code.sysl`, `slots.sysl`, `run_frames.sysl` |
| **5** | **A REGISTER MACHINE — RE-PRICED UP, FOR THE FIRST TIME.** Profile 4 priced it down twice because it widens `Ins` and adds live values to a saturated loop. **This page changes the argument**: about half the loop's machine instructions are head, and a register machine's whole claim is *fewer instructions dispatched*. `LoadSlot`, `LoadSlot2`, `LoadSlotInt` and `PushInt` are still ~26% of executions and each is ~25 head instructions. But it still collides with items 1 and 2, and `run_frames` still has no registers spare. **Measure item 1 first**: if a 16-byte `Ins` moves the mean, the register machine's version of it is affordable; if it does not, nothing about the head is | ~26% of executions are pure stack traffic | **unknown, and no longer obviously small** | OPEN QUESTION | `code.sysl`, `emit.sysl`, `run_frames.sysl` |

**And what came off or stayed off.**

| | candidate | what this page says |
|---|---|---|
| — | ~~**Revert `inline-fused`**~~ | **DONE (`unfuse`).** The four are calls again at 6.99% weighted between them, and `run_frames` is 30.93% |
| — | ~~**The field and method lookup**~~ | **DONE (`lookup-hit-path`).** The group is 7.41% → **4.43%**; `key_here` and `field_from_site` are one `field_here` |
| — | ~~**`match_walk`**~~ | **DONE (`match-leaf`).** 4.49% → 1.79%, with `match_leaf` at 2.07% doing the entries. The `for`-head half is item 4 |
| — | ~~**Module-level `var` cells**~~ | **DONE (`module-cells`).** `Map<string,*>` + `hash_str` 3.91% → **1.78%** |
| — | ~~**Per-call allocation**~~ | **DONE (`gc` 0.2.4).** Allocation and the collector 11.88% → **7.78%**; `gc.alloc` 6.23% → **2.06%** |
| — | ~~**`gc.alloc`'s size-class classifier**~~ | ~~**A `sh.sysl.gc` ITEM, and the largest one left there.** `+1224`/`+1152` is an iterative shift-and-compare where `leading_zeros` would do. Worth ~1% of the mean and it is the package author's~~ — **BUILT IN THE PACKAGE (gc 0.2.5) AND MEASURED AT ZERO HERE**: geometric mean +0.51% / −0.09% over two alternating best-of-9 runs, `alloc` and `calls` straddling zero. **The ~1% was read off `gc$alloc`'s self time, and gc 0.2.4 had already taken that to 2.06%** — a share of a small function is not a share of the mean. [The write-up](2026-09-23-gc-0-2-5.md) |
| — | ~~**The allocator zeroes and the constructor overwrites**~~ | ~~**A `sh.sysl.gc` ITEM.** `memset` 1.06% + `__bzero` 0.81% = 1.87% weighted; an allocator entry point that does not zero is what it needs~~ — **gc 0.2.5 HAS ONE (`alloc_raw`) AND slate CANNOT USE IT.** Its second condition forbids assigning a reference-counted member into uncleared storage, and every slate heap object but `WeakRefObj` owns a sysl `string`, `Buf` or `Map`: nine of the ten constructors are out, `new_weak_ref` landed on it and is worth zero, and `new_promise` fails the first condition too (it never writes `thrown`). **What gc would need is a PREFIX-clearing entry point** — slate's counted members are the leading fields, so clearing 16 or 48 bytes of a 40-to-96-byte payload serves six of the nine. Ceiling is small: **no `gc` symbol appears in `arrays.sl`'s sample at all**, the `memset`/`__bzero` there being libmalloc's own under `_xzm_free` |
| — | **`u.strings.at(k)` on a field access** | **STRUCK, priced.** 3.0% of `fields`, which is 1.1x CPython — 0.03 points of the mean |
| — | **A narrower `Value`, or NaN-boxing** | **STRUCK as a near-term item**, unchanged for three pages |
| — | **`strings` quadratic concatenation** | **STRUCK for the mean, unchanged.** 82.5% `memmove` on one program already at 1.1x CPython |
| — | ~~**`arrays` spends 11.8% in `mach_absolute_time`**~~ | ~~**NOT A SPEED ITEM — a benchmark question.** The program is timing itself inside the measured region~~ — **WRONG, AND CHECKED 2026-09-23. `bench/arrays.sl` READS NO CLOCK**, and neither does any program in `bench/` in any of the four languages. `sample` names the caller: `mach_absolute_time` is called **from `_xzm_free` in `libsystem_malloc.dylib`** — macOS's xzone malloc reads the clock in its free path — so it is **`free` itself**, and the whole `free` node is **16.6%** of that program |
| **NEW** | **A BUILTIN PROPERTY READ STILL BUFFERS ITS ONE ARGUMENT** | **The item that was hiding under the row above.** `builtin_property` in `index.sysl` mallocs a `Buf[Value]`, pushes the receiver and calls `call_native_buf` — a malloc and a free **per `xs.length`, `s.length` or `m.size`** — which `native-args` took off every other builtin call in 0.0.60 and left here as one of "the callers that genuinely have one". It does not have one: the receiver is already standing on the operand stack. `arrays.sl` makes **5,000,010** of them, and `while i < xs.length` is ordinary slate with no way round it, `len(x)` having been removed from the language. `read_field_of_kind`/`builtin_receiver` in `index.sysl`; the standing path is `standing_native` in `execute.sysl` |
| — | **The second VM segfaults** | **A BUG, NOT A SPEED ITEM, and this page has no new evidence on it.** Listed here only so it is not lost among the performance items; it needs its own reproduction and its own agent |

### The `sysl` gap this page found, reported rather than worked around

**Item 3 cannot be written in sysl today.** A threaded dispatch needs one of:

- **labels as values** (`&&label` and `goto *p`, the GCC extension every fast interpreter in C uses), or
- **guaranteed tail calls**, so each arm can `return next_arm(state)` without growing the stack.

sysl has neither: there is no address-of-label, and `@tailrec` applies to **self**-recursion only, so
a set of mutually tail-calling arm functions is not expressible. The workaround — a hand-rolled
trampoline returning the next arm's tag — reinstates exactly the indirect branch the item exists to
remove, and would be slower than what is there.

**Nothing was written around it and nothing is proposed here.** The finding is: the single largest
remaining item in slate's interpreter, worth an estimated 4–8% of the geometric mean, is blocked on a
sysl language feature, and guaranteed tail calls are the smaller and more generally useful of the two.

### What the samples say plainly, beside the first four profiles

- **A PROFILE THAT CAN ONLY NAME FUNCTIONS WILL KEEP NAMING THE SAME FUNCTION.** Four pages said
  `run_frames` was the biggest thing and none could act on it, because "the interpreter loop is where
  the time is" is not an item. The thing that turned it into three items was **reading the jump table
  out of the binary**, which needed no new tool and could have been done on profile 1.
- **THE INSTRUMENT THAT WORKED IS THE ONE WITH NO SAMPLING IN IT.** The jump-table analysis is
  deterministic, repeatable on any commit, and costs one `--features profile` run. The lldb PC
  sampler that was meant to produce the same answer deadlocked and produced nothing. **Prefer the
  static instrument where the question is "how much work is in this code path" rather than "which
  code path runs"** — the sampler answers the second question and was being asked the first.
- **`sample`'s TWO-OFFSET TRUNCATION IS A CEILING ON WHAT THE OFFSET TRICK CAN DO, AND IT SHOULD BE
  SAID OUT LOUD.** It settled `gc.alloc` because the answer was a six-instruction loop. Against a
  hundred arms, two offsets per program is a *ranking* and never a share. The `gc.alloc` write-up
  should be read as "this works when the answer is small", not as a general instrument.
- **FIVE ITEMS LANDED AND THE DISPATCH'S SHARE WENT UP.** Lookup, allocation and the name path all
  fell by a third or more; `run_frames` went 35.26% to 37.92% counting the fused arms the same way.
  **A fixed cost becomes the whole problem as soon as the variable ones are paid off**, and the
  shortlist above is the first one on which every item is the same cost.
