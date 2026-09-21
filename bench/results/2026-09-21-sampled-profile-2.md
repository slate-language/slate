# A second sampled profile, after 0.0.122 and the superinstructions (dev `76128bf`)

**The first sampled profile's headline — 46.5% of wall time inside `sysl.buf`'s accessors — is
closed.** `Buf.at` in all four instantiations was 32.4% of weighted wall time and is now **0.61%**,
and `pop` was 6.68% and is **0.22%**. Both are inlined at every hot site; the out-of-line symbols
still exist and take no samples. So the old ranking says nothing about this tree, which is why this
page exists.

**THE NEW HEADLINE, AND IT IS THE SAME FUNCTION FAMILY WEARING THE OTHER HAT: `Buf.push<Value>` IS
15.3% OF WALL TIME AND IS STILL AN ORDINARY CALL.** 0.0.122 borrows a by-value `Buf` parameter when
the function **writes no memory** and every call in it is `-> never`. A push writes memory and may
call `malloc`, so it fails both halves of that condition by construction — it was never in scope for
the fix that inlined `at`. What is left is a `bl`, a 128-byte frame and **twelve callee-saved
registers spilled and reloaded** around ten instructions of real work, once per operand pushed.

### How it was taken

**Identical to the first profile, so the two are comparable.** macOS `/usr/bin/sample` at a 1 ms
interval, each program started and sampled in one shell call, run serially under `caffeinate -dimsu`
on a box at **90.6% idle** with `pgrep -x java` empty. `sample`'s **"Sort by top of stack, same
collapsed"** section is self time and is what every figure below reads; the denominator is the main
thread's sample total from the call graph's head.

- **The same twenty of the twenty-three programs.** `startup`, `strindex` and `strwalk` are left out
  for the reasons the first page gives — the last two exit before the sampler can attach, and both
  are already faster than CPython.
- **9,375 samples against the first profile's 19,349**, on the same twenty programs at the same
  interval. The tree is about twice as fast as it was: that halving *is* the 0.0.122 and
  superinstructions work, and it is why every per-program total below is smaller.
- `sample` truncates its self-time table at 5 samples per name, so a per-program column sums to a
  little under 100%.
- **The unnamed region has all but gone.** `???` inside the first ~500 KB of `__text` — sysl's ARC
  release and its deferred-free walk — was 1.65% and is now **0.67%** across six offsets, the largest
  of them 0.21%.

### The aggregate

Weighted by each program's **slate/CPython ratio**, as before, so the ranking favours what closes the
Python gap. The last column is the first profile's weighted share for the same name, where it had
one.

| self time | unweighted | weighted | first profile | what it is |
|---|---|---|---|---|
| `run_frames` | 21.39% | **21.87%** | 12.74% | the loop itself, and every instruction arm inlined into it |
| `Buf.push<Value>` | 14.72% | **15.34%** | 8.63% | every operand-stack push — **the finding, see below** |
| `_platform_memmove` | 5.99% | 1.98% | 1.11% | almost all of it is `strings` (81.2% of that one program) |
| `_tlv_get_addr` | 4.00% | **4.28%** | 2.99% | the thread-local getter — **`current()`, not ARC; see below** |
| `match_walk` | 3.52% | **3.84%** | 1.99% | `for` heads, `match` arms, destructuring |
| `gc.alloc` | 3.37% | **4.91%** | 2.25% | 23.5% `alloc`, 22.4% `csv`, 18.1% `calls` |
| `merge_sort` | 2.35% | 1.31% | — | 52.1% of `sorting`, which is now its own comparator walk |
| `scan_named` | 1.97% | 2.13% | 1.28% | a name in an object's table — 11.3% `methods`, 8.4% `fields` |
| `fused_add_store_slot` | 1.91% | 1.98% | — | a superinstruction; did not exist for the first profile |
| `_xzm_free` | 1.87% | 1.54% | — | `free` — 7.8% of `globals`, reached straight from `run_frames` |
| `Buf.push<Frame>` | 1.67% | 1.86% | — | one per call that pushes a frame |
| `maybe_collect` | 1.47% | 1.59% | — | the collection schedule, asked per statement |
| `Map.find<string,Value>` | 1.44% | 1.18% | 0.88% | 8.8% of `globals` alone |
| `placed_call` | 1.43% | 1.74% | 0.52% | which of the three call paths |
| `keepable` | 1.32% | 1.54% | 1.58% | the `undefined` refusal, on every store |
| `hash_str` | 1.30% | 1.11% | — | 7.2% of `globals` |
| `obj_get_name` | 1.09% | 1.12% | 0.71% | 5.7% of `methods` |
| `multiplied` | 1.02% | 1.05% | — | 6.8% of `loops` |
| `arith` | 1.01% | 0.68% | — | 14.2% of `sorting`, 9.0% of `reals` |
| `fused_less_jump_if_false` | 0.91% | 0.86% | — | a superinstruction |
| `read_field` | 0.81% | 0.92% | — | |
| `Map.get<string,Value>` | 0.78% | 0.57% | — | `globals` |
| `Map.put<string,Value>` | 0.76% | 0.39% | — | `globals` |
| `Buf.at<*>` (all four) | **0.71%** | **0.61%** | **32.4%** | **inlined — see below** |
| `pop` | 0.19% | 0.22% | 6.68% | inlined |

**Rolled up, weighted:** `Buf.*` **19.2%** (of which `push` is 18.5% and `at` 0.6%); allocation
**8.9%** (`gc.alloc` 4.9 + `gc.collect` 1.0 + `maybe_collect` 1.6 + `memset`/`bzero` 1.5); method and
field lookup **6.5%**; the thread-local getter **4.3%**; `Map<string, Value>` plus `hash_str`
**3.7%**; the call path **4.6%**; remaining retain/release traffic **2.2%**.

### Per program, the top five

| benchmark | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| arith | `run_frames` 39.2 | `Buf.push<Value>` 33.1 | `fused_add_store_slot` 5.3 | `_tlv_get_addr` 4.5 | `fused_less_jump_if_false` 4.1 |
| reals | `run_frames` 29.3 | `Buf.push<Value>` 28.0 | `arith` 9.0 | `real_arith` 6.4 | `fused_add_store_slot` 6.2 |
| globals | `run_frames` 17.3 | `Map.find` 8.8 | `_xzm_free` 7.8 | `hash_str` 7.2 | `Buf.push<Value>` 7.1 |
| funcs | `run_frames` 36.4 | `Buf.push<Value>` 23.6 | `fused_add_store_slot` 5.4 | `added` 5.0 | `keepable` 4.3 |
| fib | `run_frames` 39.0 | `Buf.push<Value>` 19.2 | `_tlv_get_addr` 9.1 | `placed_call` 5.5 | `Buf.push<Frame>` 4.8 |
| calls | `gc.alloc` 18.1 | `Buf.push<Value>` 9.8 | `run_frames` 8.2 | `scan_named` 5.2 | `Buf.push<Entry>` 3.7 |
| methods | `run_frames` 30.5 | `Buf.push<Value>` 16.2 | `scan_named` 11.3 | `obj_get_name` 5.7 | `Buf.push<Frame>` 5.1 |
| closures | `run_frames` 28.3 | `Buf.push<Value>` 20.2 | `placed_call` 6.4 | `Buf.push<Frame>` 6.0 | `fused_add_store_slot` 5.2 |
| nested | `run_frames` 25.2 | `Buf.push<Value>` 19.7 | `match_walk` 15.2 | `Buf.push<Frame>` 5.5 | `placed_call` 4.4 |
| loops | `run_frames` 35.6 | `match_walk` 29.5 | `Buf.push<Value>` 14.2 | `multiplied` 6.8 | `_tlv_get_addr` 4.7 |
| options | `run_frames` 22.8 | `Buf.push<Value>` 15.1 | `match_walk` 11.2 | `scan_named` 5.0 | `Buf.push<string>` 4.2 |
| fields | `Buf.push<Value>` 17.2 | `run_frames` 17.0 | `scan_named` 8.4 | `_xzm_free` 6.2 | `write_named` 5.9 |
| alloc | `gc.alloc` 23.5 | `run_frames` 10.1 | `Buf.push<Value>` 8.4 | `Buf.push<Entry>` 6.7 | `_tlv_get_addr` 4.3 |
| arrays | `Buf.push<Value>` 20.0 | `run_frames` 18.8 | `fused_add_store_slot` 8.4 | `mach_absolute_time` 7.5 | `_tlv_get_addr` 5.5 |
| mapset | `run_frames` 16.2 | `Buf.push<Value>` 12.7 | `find_entry` 9.6 | `methods_of` 9.6 | `_tlv_get_addr` 8.7 |
| dispatch | `run_frames` 31.9 | `Buf.push<Value>` 20.4 | `match_walk` 17.3 | `_tlv_get_addr` 5.6 | `maybe_collect` 5.0 |
| branches | `run_frames` 44.6 | `Buf.push<Value>` 30.2 | `fused_add_store_slot` 5.4 | `remainder_of` 4.0 | `is_equal` 3.4 |
| sorting | `merge_sort` 52.1 | `arith` 14.2 | `on_values` 12.3 | `int_arith` 11.6 | `Buf.push<Value>` 4.7 |
| csv | `gc.alloc` 22.4 | `run_frames` 7.6 | `Buf.push<Value>` 7.6 | `gc.collect` 5.9 | `Buf.push<string>` 4.0 |
| strings | `memmove` 81.2 | `Cursor.next` 6.8 | `mach_absolute_time` 1.7 | `trace_env` 1.5 | `gc.alloc` 1.4 |

**`strings` and `sorting` are still not interpreter benchmarks.** `strings` is one `memmove` and
`sorting` is `merge_sort` plus its comparator; both are at or under 1.4x CPython.

### `Buf.at` IS inlined, and the second bounds check is not the item it was left as

This is the top of the instruction loop in the shipped binary, read with `objdump --macho` and
compared against the first profile's excerpt of the same site:

```
100492fe4  mov  x20, x19
100492fe8  cmp  x19, x28              ; bounds check 1
100492fec  b.hs 0x1004a28fc
100492ff0  cmp  x20, x26              ; bounds check 2
100492ff4  b.hs 0x1004a1e20
100492ff8  mov  w8, #0x38             ; sizeof(Ins) = 56
100492ffc  madd x9, x20, x8, x27
100493000  ldp  x21, x23, [x9, #0x10] ; the element, four loads
100493004  ldr  x24, [x9, #0x8]
100493008  ldr  w8, [x9]
10049300c  ldp  x15, x14, [x9, #0x28]
100493010  add  x19, x20, #0x1        ; pc += 1
100493014  cmp  w8, #0x65             ; 101 opcodes
100493018  b.hi 0x100494a6c           ; -> the switch default
10049301c  adrp x12, 611
100493020  add  x12, x12, #0xb86      ; the jump table
100493024  adr  x10, #16
100493028  ldrh w11, [x12, x8, lsl #1]
10049302c  add  x10, x10, x11, lsl #2
100493030  br   x10                   ; ONE indirect branch
```

- **The `bl` to `Buf.at<Ins>` is gone.** Where the first profile read `bl _sysl.buf$Buf.at…$Ins` —
  a call, twelve register spills, a retain, two bounds checks, a 56-byte copy, a release and a branch
  to the free-list walk — there is now a `madd` and four loads. `Buf.at<Ins>` still exists as a
  symbol at `0x1005bc828` for cold callers and takes **no samples on any program**.
- **The retain and release are gone with it.** Neither appears at this site or in `push` (below).
- **Both bounds checks are still here**, at `100492fe8` and `100492ff0` — four instructions of a
  twenty-instruction dispatch head. **The remaining check is worth well under 1% of wall time**, and
  that is the whole answer to the question the first page left open: `run_frames`' self time is 21.9%
  weighted, the dispatch head is about twenty of its instructions, and this is two of them — a
  perfectly predicted compare against a register, on a core that issues several per cycle. It is not
  worth a sysl design change on this evidence, and it is struck below.

### `Buf.push<Value>`, which is where the cost went

`push` takes its buffer by pointer, so there is no ARC traffic — and it is still not inlined,
because the borrowed-read rule asks that the function write no memory. The **entry**:

```
1005b072c  sub  sp, sp, #0x80          ; a 128-byte frame
1005b0730  stp  x28, x27, [sp, #0x20]  ; six pairs: twelve callee-saved registers spilled
1005b0734  stp  x26, x25, [sp, #0x30]
1005b0738  stp  x24, x23, [sp, #0x40]
1005b073c  stp  x22, x21, [sp, #0x50]
1005b0740  stp  x20, x19, [sp, #0x60]
1005b0744  stp  x29, x30, [sp, #0x70]
   … six moves …
1005b0760  ldp  x27, x8, [x0, #0x10]
1005b0764  cmp  x8, x27                ; is it full?
1005b0768  b.ne 0x1005b0c2c            ; -> the fast path; FALL THROUGH is the grow
```

and the **fast path it branches to**, which is the whole of an ordinary push:

```
1005b0c2c  ldp  x9, x8, [x20, #0x10]
1005b0c30  cmp  x8, x9
1005b0c34  b.hs 0x1005b0c7c
1005b0c38  ldr  x9, [x20, #0x8]
1005b0c3c  mov  w10, #0x28             ; sizeof(Value) = 40
1005b0c40  madd x8, x8, x10, x9
1005b0c44  stp  x23, x24, [x8, #0x8]   ; the element, three stores
1005b0c48  str  w22, [x8]
1005b0c4c  stp  x21, x19, [x8, #0x18]
1005b0c50  ldr  x8, [x20, #0x18]       ; len += 1
1005b0c54  add  x8, x8, #0x1
1005b0c58  str  x8, [x20, #0x18]
   … then six `ldp` reloading the twelve registers, and `ret`
```

**Ten instructions of work behind a call, a 128-byte frame and twenty-four register moves**, and the
prologue is that large because the **grow** path in the same function needs the registers. That is
exactly the shape `Buf.at` was in before 0.0.122 moved its index panic out of line so the remainder
could inline. The same move for `push` — the grow out of line, the store-and-bump inlinable — is a
`buf.sysl` change and is the largest single item on this page.

### The four things the brief asked to be measured, with their numbers

| what | weighted share | where it concentrates |
|---|---|---|
| **the call path** — frame set-up, argument passing, `Ret` | **4.6%** (`placed_call` 1.74 + `Buf.push<Frame>` 1.86 + `lay_standing` 0.41 + `trailing_defaults` 0.28 + `Buf.at<Frame>` 0.18), plus an unattributable share of `run_frames`' `Call`/`Ret` arms | `closures` 14.6, `fib` 13.8, `nested` 11.9, `funcs` 8.1 |
| **method lookup and field reads** (the case for inline caches) | **6.5%** (`scan_named` 2.13 + `obj_get_name` 1.12 + `read_field` 0.92 + `find_entry` 0.60 + `field_from` 0.57 + `methods_of` 0.50 + `write_named` 0.29 + `obj_put` 0.23 + `key_hash` 0.08) | `fields` 28.2, `methods` 25.3, `mapset` 19.2, `calls` 10.8 |
| **`gc.alloc` and allocation** | **8.9%** (`gc.alloc` 4.91 + `gc.collect` 0.96 + `maybe_collect` 1.59 + `memset` 0.89 + `bzero` 0.58) | `alloc` 23.5, `csv` 22.4 + 5.9, `calls` 18.1 |
| **remaining retain/release traffic** | **2.2%** (`_xzm_free` 1.54 + the unnamed ARC region 0.67) | `globals` 7.8, `fields` 6.2 — and in `globals` it is reached **straight from `run_frames`**, which is the module-level name path building and dropping a sysl `string` per access |

**`_tlv_get_addr` at 4.28% is NOT retain/release, and the first profile said it was.** Its callers in
the call graph are `run_frames`, `maybe_collect`, `keepable`, `pop` and `fused_less_jump_if_false` —
slate's own module state reached through a thread-local, which is what `current()` compiles to. It is
9.1% of `fib`, 8.7% of `mapset`, 5.6% of `dispatch`. `run_frames` already takes `val vm = machine()`
once; the helpers it calls each ask again.

### The re-ranked shortlist

Share is the weighted aggregate above. A ceiling is what an item could take off the geometric mean if
it removed **all** of the named cost, which none will.

| rank | candidate | measured share | ceiling | kind | files |
|---|---|---|---|---|---|
| 1 | **Inline `Buf.push` the way 0.0.122 inlined `Buf.at`** — move the grow path out of line so the store-and-bump can inline | **18.5%** (`push<Value>` 15.34 + `<Frame>` 1.86 + `<Entry>`/`<string>`) | **10–15%** — it is a call, a 128-byte frame and 24 register moves around 10 instructions | STRUCTURAL, and it is **sysl's, not slate's** | `sysl-bootstrap`'s `buf.sysl` |
| 2 | **A register machine instead of a stack machine** | 15.5% (`Buf.push<Value>` + `pop` + `peek`), plus its share of `run_frames` | 10–15%, and it is slate's own way at most of item 1 | STRUCTURAL | `emit.sysl`, `run_frames.sysl`, `slots.sysl` |
| 3 | **Stop re-asking `current()` in the hot helpers** — pass the `*Vm` into `keepable`, `pop`, `maybe_collect` and the fused arms | **4.3%**; 9.1% `fib`, 8.7% `mapset`, 5.6% `dispatch` | 3–4% | INCREMENTAL, wholly slate's — **NEW, and the first profile mis-read this as the ARC free list** | `vm_state.sysl`, `run_frames.sysl`, `obj.sysl` |
| 4 | **Inline caches for a field or a method** | **6.5%**; 28.2% of `fields`, 25.3% of `methods`, 19.2% of `mapset` | 3–4% | INCREMENTAL, the largest incremental item that is wholly slate's | `index.sysl`, `table.sysl`, `run_frames.sysl` |
| 5 | **Module-level `var` cells, `StoreDef`** | 3.7% over the set, and **~30% of `globals`** (`Map.find` 8.8 + `_xzm_free` 7.8 + `hash_str` 7.2 + `Map.put` 6.4) | 0.5% of the mean, 25%+ of one program — the reach column's usual reading | INCREMENTAL | `defs.sysl`, `emit.sysl`, `compile.sysl` |
| 6 | **`match_walk` — `for` heads, `match` arms, destructuring** | **3.8%**; 29.5% `loops`, 17.3% `dispatch`, 15.2% `nested`, 11.2% `options` | 2–3% | INCREMENTAL — **NEW to the shortlist**; it was 1.99% and is now the fifth-largest name | `match.sysl`, `index.sysl`, `run_frames.sysl` |
| 7 | **Allocate less on the call-heavy programs** | 8.9% over the set, but 18.1% of `calls` and 22.4% of `csv` — the two worst programs against CPython | unknown until somebody asks **what** `calls` allocates per call; that is the next question, not the next item | OPEN QUESTION | `obj.sysl`, `execute.sysl` |
| 8 | **A narrower `Value`, or NaN-boxing** | 15.5% (`Buf.push<Value>` alone) | **5–8%**, down from the first page's 10–15%: 40 bytes is now three stores per push and a 56-byte `Ins` fetch, the read side having been inlined | STRUCTURAL — not piecemeal | `value.sysl` and every native |
| — | ~~**Borrowed reads: stop `Buf.at`/`len`/`cap` retaining, and get them inlined**~~ | was 46.5% | **DONE in sysl 0.0.122.** `Buf.at<*>` is **0.61%** and `pop` is **0.22%**; the dispatch fetch is a `madd` and four loads with no call, no frame and no ARC | — | — |
| — | ~~**The second bounds check inside `Buf.at`**~~ | **two instructions of a twenty-instruction dispatch head** | **STRUCK.** Under 1% of wall, perfectly predicted, and it would cost a sysl design decision to remove. The first page left this open; it is closed by the disassembly above | — | — |
| — | ~~**Superinstructions**~~ | — | **LANDED**: -9.17% geometric mean. `fused_add_store_slot` is 1.98% of wall and `fused_less_jump_if_false` 0.86%, which is the fused work now visible under its own names | — | — |
| — | ~~**Cheaper frames — stop re-reading the `Chunk` per call**~~ | was 4.0% | **LANDED**: `Buf.at<Chunk>` no longer reaches the five-sample floor on any program | — | — |
| — | ~~**`methods_of` looking a method up by name at every call**~~ | 0.50% | **STILL STRUCK.** It is 9.6% of `mapset` and invisible on the other nineteen | — | — |
| — | ~~**`lay_frame`**~~ | below five samples everywhere | **STILL STRUCK.** `lay_standing` beside it is 0.41% | — | — |

### What the samples say plainly, beside the first profile

- **Half the wall clock is no longer one decision.** The first page's honest summary was that nearly
  half of everything was `Buf.at` taking `self` by value. The tree is now about twice as fast and the
  largest single name is `run_frames` itself at 21.9% — the interpreter doing its own work.
- **The cost did not move to slate, it moved along the `sysl.buf` bench.** `push` has become what
  `at` was, for the mirror-image reason: the borrowed-read rule is a rule about **reads**, and a stack
  machine pushes as often as it reads.
- **`_tlv_get_addr` rose from 2.99% to 4.28% and is a slate item, not a sysl one.** It was attributed
  to the ARC free list, and the call graph says it is `current()`.
- **`match_walk` doubled its share without changing**, which is what happens to every honest cost when
  a larger one is removed. The same is true of `gc.alloc` (2.25% → 4.91%) and `scan_named`
  (1.28% → 2.13%) — none of them got slower.
- **The position, from the 0.0.122 write-up's own run:** 4.34x Lua, 3.35x `node --jitless`, 2.29x
  CPython on the geometric mean, with `calls` 4.99x, `csv` 4.75x, `methods` 4.09x, `fib` 3.53x and
  `globals` 3.36x the worst against CPython. Four of those five are explained by exactly two names on
  this page: `gc.alloc` (`calls`, `csv`) and the method/field lookup (`methods`), with `globals` its
  own `Map<string, Value>` item and `fib` the call path plus `current()`.
