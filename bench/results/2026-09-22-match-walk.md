# 2026-09-22 — A LEAF PATTERN IS ANSWERED WHERE IT IS REACHED — profile 4's item 3

**`loops` −9.8% and −8.0%, `dispatch` −3.3% and −5.0%, `nested` −1.5% and −3.1%, geometric mean
−0.59% and −0.89%** over profile 4's twenty-three, two alternating best-of-9 runs from the same pair
of binaries. Control is dev `ab511ea` (sysl 0.0.125); no instruction was added, removed or renamed,
so every program compiles to exactly the bytes it did and what moved is what a pattern costs to run.

`bench/check.sh` says *answers unchanged* for all four implementations.

## What a pattern was paying, and it was not the matching

`match_walk` is one jump table over every kind of `PatKind`, and **it is entered once per pattern
and once per pattern INSIDE that pattern**. `for [a, b] in pairs` enters it three times a turn: once
for the shape, and once for each of the two names it puts down. `w match "add" -> …` enters it once
per arm tried, to compare two strings.

The two inner entries of the `for` head do nothing the outer one could not — they read a tag and
push a value. What they cost is the **function**, and `-O2` prices that off the deepest arm the
dispatch has rather than off the arm being taken:

```
_dev.slatelang.slate$match_walk:
        sub     sp, sp, #0x1f0          ; a 496-byte frame
        stp     x28, x27, [sp, #0x190]  ; seven callee-saved pairs, plus d9/d8
        ...
        ldr     x8, [x2] ; add x8, x8, #0x1 ; str x8, [x2]   ; a retain on the pattern's box
        ldp     x21, x25, [x28, #0x78]  ; six `ldp`s of the enum payload, BEFORE the jump table
        ldrh    w10, [x20, x8, lsl #1]
        br      x9
```

`match_array`, `match_object`, `in_range`, `is_kind` and `hold_places` are all `private` to
`match.sysl` and all inlined into it, so the one function is **10,808 bytes** and every leaf shape
pays its frame, its register saves, its retain and the payload preload on the way to a tag compare.

Sampled at 1 ms against the control, self time (`sample`'s "Sort by top of stack"):

| `bench/loops.sl`, control | samples of 203 | `bench/dispatch.sl`, control | samples of 365 |
|---|---|---|---|
| `run_frames` | 54 | `run_frames` | 172 |
| **`match_walk`** | **85** | **`match_walk`** | **76** |
| `compose_unpack_slots` | 20 | `placed_call` | 16 |

## What was tried first and measured WRONG, because it is the instructive half

**Cutting the dispatch up made it slower.** `match_array` and its neighbours were moved into a file
of their own so they could not be inlined, which took `match_walk` from 10,808 bytes to 4,600 and
left the frame at 464 — and the alternating best-of-9 read **+0.69% geometric mean, `loops` +6.5%,
`nested` +4.0%, `options` +2.7%**. The inlined bodies were worth more than the smaller function: a
compound pattern now paid a real call with eight arguments, one of them a 40-byte `Value`, where it
had paid none.

So the frame is not the thing to shrink. **The thing to cut is the number of times it is entered.**

## What changed

`match_leaf` in `match.sysl` answers the patterns with no pattern inside them — a name, a wildcard,
a string, an integer, a boolean, a null — and hands everything else to `match_walk` unchanged. It is
reached from four places: the element loop of `match_array`, the value loop of `match_object`, the
`TestSlots` arm in `run_frames.sysl`, and `compose_test_pat`/`compose_is_pat` in `run_compose.sysl`.

Its arms are the SAME arms `match_walk` answers with, written a second time rather than shared, so a
name binds and a literal compares identically whichever route reached it — and **`match_walk` stays
the one exhaustive reading of `PatKind`**, which is what names the sites a new pattern kind has to be
written into. That exhaustiveness is worth more than the duplication it costs.

What it buys is the frame:

```
_dev.slatelang.slate$match_leaf:
        sub     sp, sp, #0x50           ; 80 bytes against 496
        stp     x22, x21, [sp, #0x20]   ; three pairs against seven, and no d8/d9
```

## The witness

Same sampling, the branch:

| | control | branch |
|---|---|---|
| `loops`: `match_walk` self | **85 of 203 (41.9%)** | **34 of 177 (19.2%)** |
| `loops`: `match_walk` + `match_leaf` | 85 (41.9%) | 60 of 177 (**33.9%**) |
| `loops`: total samples for the same work | 203 | **177** |
| `dispatch`: `match_walk` self | **76 of 365 (20.8%)** | **below the 5-sample floor — absent** |
| `dispatch`: `match_leaf` self | — | 69 of 364 (18.9%) |

`dispatch` is the clean case: every arm of `kind(w)` is a `StrPat`, so after the change the big
dispatch is not entered at all and `match_walk` falls off that program's profile entirely.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `ab511ea` against the branch, on a box at
94% idle with `pgrep -x java` empty, run twice from the same pair of binaries.

| program | run A | run B |
|---|---|---|
| **loops** | **−9.8%** | **−8.0%** |
| **dispatch** | **−3.3%** | **−5.0%** |
| **nested** | −1.5% | **−3.1%** |
| **branches** | **−3.0%** | −2.2% |
| **options** | −0.9% | −1.3% |
| alloc | −1.1% | −2.0% |
| methods | −0.3% | −1.7% |
| strings | +0.0% | −2.0% |
| csv | −0.4% | +0.3% |
| **geometric mean, all twenty-three** | **−0.59%** | **−0.89%** |

The rows the item named all move and they move in both runs; the unrelated rows drift ±2% in both
directions between the two, which is this instrument's floor for a change that moves code around.
**The ceiling on the shortlist was 2–3% and what it took is about 0.75%** — the leaves were most of
the *entries* and the compound arms are most of the *work*, and this change touches only the first.

## What is left of the item

`match_array` and `match_object` still enter the big dispatch once per compound pattern, and
`compose_unpack_slots` (13 of 177 on `loops`) is still the instruction that drives it. The thing that
would close the rest is the one the shortlist named first — **compiling a `for` head's simple shape
into the instruction so the matcher is never entered at all** — which is a codegen change and a new
instruction rather than a runtime fast path, and is a separate item.
