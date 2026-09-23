# 2026-09-22 — one jump table instead of two — profile 5's item 2

**Profile 5 found that `Op` split at tag 27 and that most of the hot instructions were on the far
side of the split**, paying a second `sub`/`cmp`/`b.hi`/`adrp`/`add`/`adr`/`ldrh`/`add`/`br` — nine
more instructions and a second unpredictable indirect branch — on every execution. Its shortlist
guessed the cause was the tag NUMBERING and put the ceiling at 1–2%.

**The cause is the order the ARMS ARE WRITTEN IN, and the rule is exact: the back end folds the
first FORTY-TWO arms of the `match` into one switch and every arm after them shares a second.**
Which forty-two is decided by nothing but source order. Reordering the arm list so the forty-two the
benchmarks execute are written first — and moving five variants in `Op` so those forty-two hold a
dense enough band of tags for a table to be built over them at all — puts the whole hot path behind
one indirect branch.

**Measured: geometric mean −2.69% on an alternating best-of-9**, above the page's own ceiling, with
`methods` −11.5%, `fib` −9.2%, `dispatch` −9.0% and `funcs` −7.7%. Instruction counts are identical
to the instruction, and `bench/check.sh` reports all twenty-three programs answering what they
answered before on all four implementations.

## What the two tables actually were, read out of the binary

`run_frames` at dev `85e8f80` is `0x10021c384`, and its dispatch ends in
`ldrh w10,[x11,x8,lsl #1]; add x9,x9,x10,lsl #2; br x9` — 16-bit word-scaled displacements from an
`adr`-computed base. Reading that table out of `__TEXT,__const` gives every arm's entry point, and
the first table's entries say which arms it really serves:

| | first table | second table |
|---|---|---|
| range | tags **0..104** (105 entries) | tags **27..109** (83 entries) |
| arms it serves | **42** | 68 |
| other entries | 63, all pointing at the second table's head | — |
| density | 42/105 = **40.0%** | 82% |

**The forty-two the first table served were exactly the first forty-two arms as WRITTEN in
`run_frames.sysl`**, and that correspondence is total: sorted, they are `{0..26}` plus
`{46, 64, 65, 87, 94..104}`, which is `SealData`, `PushNull`, `PushUndefined`, `PushBool`, `PushInt`,
… through `Add` — the arm list's first forty-two lines, in source order, whatever their tags. The
forty-third arm written is `Sub`, and `Sub` is the second table's first entry.

**So the numbering was the symptom and the source order was the cause.** The first table had to span
0..104 only because `PushModule` (tag 104) is the NINTH arm written and the handler group (94..103)
is written just after it — eleven cold instructions dragging the range out to 105 entries and leaving
it exactly at the 40% floor a jump table is built at.

### The experiment that settled it, before anything was designed

Moving fifteen cold high-tag arms (`SealData`, `PushModule`, the four `Check*`/`Define*`, the six
handler ops, `JumpIfBound`, `JumpIfGiven`, `JumpIfSet`) out of the head of the arm list and changing
nothing else gave:

| | first table | second table |
|---|---|---|
| range | tags **0..41** (42 entries) | tags 42..109 (68 entries) |
| arms | **42**, no redirect entries at all | 68 |

**Forty-two again, at 100% density, with room to spare** — so the boundary is a fixed count of arms
and not the density rule. That is the whole finding, and it is what the fix is built on.

## What changed

**`run_frames.sysl` — the arm list is in two blocks.** The forty-two instructions the benchmarks
execute are written first, then a marked `---- THE COLD BLOCK ----` comment, then everything else.
The forty-two are the thirty-five ops that appear at all in `SLATE_PROFILE=1` over `bench/*.sl` with
a share above 0.29% — which together are **99.99%** of the 1,542,746,861 instructions those programs
execute — plus `Div`, `IntDiv`, `LessEq`, `Greater`, `GreaterEq`, `NotEqual` and `Less`, which no
benchmark reaches and an ordinary program does. Nothing else about any arm changed; the file is 980
lines.

**`code.sysl` — five variants moved up and three moved down.** A jump table is built over a RANGE of
tags, so the hot arms have to hold near-neighbouring tags as well as near-neighbouring arms:

- **`Tick` and the four fused pairs were declared LAST**, at tags 105–109, which is above the first
  table's range however the arms are ordered — and they are the 1st, 2nd, 4th, 6th and 7th heaviest
  instructions in the mix (`LoadSlotInt` 11.0%, `Tick` 9.6%, `AddStoreSlot` 7.1%, `LoadSlot2` 5.8%,
  `LessJumpIfFalse` 5.2%, 38.8% between them). They are declared among the slot instructions they
  fuse now.
- **`PushNull`, `PushUndefined` and `PushBool` held tags 0, 1 and 2** and are three of the four
  coldest instructions in the whole mix (14,079 executions between them, 0.001%). A cold variant
  *below* every hot one costs a `sub` on the dispatch of every instruction the machine executes,
  because the table then begins at the lowest hot tag rather than at zero. They are at the end of the
  constants group now and `PushInt` holds tag 0.

Nothing reads an `Op`'s tag as a number: there is no `Op`-to-integer conversion anywhere in the tree,
no test names an ordinal, and nothing writes a tag to disk — a compiled `Unit` never leaves the
process, and `actor_wire.sysl` carries values rather than code. So the order is free to be chosen for
the dispatch, and **that is now the rule the two files state**, each pointing at the other.

## The `otool` proof

**Before (dev `85e8f80`), at `run_frames+564`:**

```
+564  cmp  w8, #0x68            -- 104
+568  b.hi <second table>
+572  adrp x11, ... ; +576 add x11,x11,#0x378 ; +580 adr x9,#-152
+584  ldrh w10, [x11, x8, lsl #1]
+588  add  x9, x9, x10, lsl #2
+592  br   x9
```
and then, for every tag from 27 up, again at `+3916`:
```
+3916 sub  w9, w8, #0x1b
+3920 cmp  w9, #0x52
+3924 b.hi <the default>
+3928 adrp x12, ... ; +3932 add x12,x12,#0x44a ; +3936 adr x10,#16
+3940 ldrh w11, [x12, x9, lsl #1]
+3944 add  x10, x10, x11, lsl #2
+3948 br   x10
```

**After, at `run_frames+492`:**

```
+492  cmp  w8, #0x5e            -- 94
+496  b.hi <second table>
+500  adrp x11, ... ; +504 add x11,x11,#0xa04 ; +508 adr x9,#-80
+512  ldrh w10, [x11, x8, lsl #1]
+516  add  x9, x9, x10, lsl #2
+520  br   x9
```

**Eight instructions, the same eight — and the forty-two arms behind them are now the hot ones.**
Read out of the binary:

| | first table | second table |
|---|---|---|
| range | tags **0..94** (95 entries) | tags 3..109 (107 entries) |
| arms it serves | **42 — every op in the hot set** | 64 |
| ops that still pay the second table | the 53 redirect entries plus tags 95..109 | — |

`+3940`, the second table's `ldrh` and a top-two program counter on `arith`, `nested`, `arrays` and
`csv` in profile 5, is not on the path of any instruction those programs execute any more.

**The `sub` is worth measuring on its own, and it was.** The first build of this branch left
`PushNull` at tag 0, so the first table spanned 3..94 and the head read
`sub w9,w8,#3; cmp w9,#0x5b; b.hi …` — **nine** instructions rather than eight. That build measured
**−1.32%**; moving three cold constants down to take the `sub` off took it to **−2.69%**. One
instruction on the dispatch of every instruction executed is worth about 1.4% of the whole set, which
is a useful number to have for its own sake.

## Wall time: alternating best-of-9

Control is dev `85e8f80` built in a detached worktree, branch is this one; both sysl 0.0.125,
`bench/alternate.pl 9`, box at **89% idle** with `pgrep -x java` empty, everything under
`caffeinate -dimsu`. The **without-`sub`** column is the final tree; the **with-`sub`** column is the
same branch before the three constants moved, and is kept because the two together price the
subtract.

| program | control (ms) | branch (ms) | change | (with the `sub`) |
|---|---|---|---|---|
| methods | 494.485 | 437.498 | **−11.5%** | −8.6% |
| fib | 532.946 | 483.679 | **−9.2%** | −8.0% |
| dispatch | 455.557 | 414.580 | **−9.0%** | −9.2% |
| funcs | 231.297 | 213.548 | **−7.7%** | −7.0% |
| strindex | 8.495 | 8.034 | **−5.4%** | −2.2% |
| closures | 244.090 | 234.798 | **−3.8%** | +4.5% |
| calls | 436.413 | 422.218 | **−3.3%** | −1.7% |
| branches | 335.467 | 325.045 | **−3.1%** | −2.9% |
| startup | 4.660 | 4.536 | −2.7% | −1.7% |
| options | 585.676 | 571.255 | −2.5% | −2.0% |
| mapset | 248.107 | 242.713 | −2.2% | −3.1% |
| strwalk | 9.912 | 9.748 | −1.7% | +1.0% |
| arrays | 439.957 | 432.828 | −1.6% | −3.6% |
| fields | 236.275 | 233.001 | −1.4% | −3.2% |
| arith | 282.276 | 278.852 | −1.2% | +1.4% |
| strings | 734.397 | 727.826 | −0.9% | +1.4% |
| csv | 324.837 | 324.337 | −0.2% | +0.7% |
| alloc | 487.524 | 489.154 | +0.3% | +2.5% |
| reals | 358.392 | 359.937 | +0.4% | +4.3% |
| nested | 475.823 | 478.901 | +0.6% | +1.7% |
| sorting | 527.580 | 533.860 | +1.2% | +3.9% |
| globals | 715.583 | 725.144 | +1.3% | +0.1% |
| **loops** | 269.466 | 277.537 | **+3.0%** | +3.0% |
| **geometric mean** | | | **−2.69%** | −1.32% |

**`loops` is up 3.0% in BOTH runs and that is the one number this page cannot explain.** It is the
program the change should have paid best — `LessJumpIfFalse`, `AddStoreSlot`, `LoadSlotInt` and
`Tick` are 62% of its instructions and all four moved from the second table to the first. Everything
the instrument can see says it should be faster: the counts are identical, the head is one
instruction shorter than dev's for those ops by eight, and the same four ops carry `fib` (−9.2%) and
`dispatch` (−9.0%). What is left is code LAYOUT — the arms moved, so what shares a cache line with
what moved with them — which nothing here measures. It is worth a look if a later item touches the
arm order again; it is not worth holding this one for.

`globals` (+1.3%) and `sorting` (+1.2%) are the other two above zero, both inside the spread the
`with-sub` column shows for programs that barely dispatch.

## Position

`bench/run.sh -n 5`, the same box, control then branch:

| | /lua | /node --jitless | /CPython | /qjs |
|---|---|---|---|---|
| control (dev `85e8f80`) | 3.2x | 2.4x | 1.7x | 2.0x |
| branch | 3.2x | 2.4x | **1.6x** | 2.0x |

**`run.sh` is two separate passes and is not the yardstick here** — its branch pass ran second and
the box had drifted, so every one of its absolute figures is higher than the control's (`startup` 5.1
against 4.3, `arith` 304 against 281) while the alternating run, which interleaves them, has the
branch ahead. This is the shape `bench/README.md` warns about and the reason `alternate.pl` exists;
the ratios are here for position only.

## What the change owes, and what it does not

**No new test, under rule 4-0.** Nothing a program can observe changed: the instruction counts are
identical op by op over all twenty-three programs (`LoadSlotInt` 170,174,922, `Tick` 148,180,171,
`LoadSlot` 119,084,291, … totalling 1,542,746,861 on both sides), `bench/check.sh` reports every
implementation answering exactly what it answered before, and all three gate shapes are green. There
is no behaviour here to pin that the existing suite does not already pin — the whole diff is which
order two lists are written in.

**What IS owed is that the invariant stays readable, and both files carry it.** `run_frames.sysl`'s
`match` opens by saying that only the first forty-two arms get the single-level table and that the
cold block's comment is the boundary; `code.sysl` says why `Tick`, the four fused pairs and the three
dead constants are declared where they are. **An instruction added above the cold block's marker
pushes the last hot one over the edge**, silently and for free, which is exactly the kind of thing a
comment is for and no test can catch.
