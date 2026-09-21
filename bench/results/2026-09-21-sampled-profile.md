# What the sampled profile shows (dev `c26567e`)

**Nothing on the shortlist above was read off a clock. This is.** Every item on that page was chosen
from `--features profile`'s instruction COUNTS, and the one-instruction-per-operator win is the
standing proof that counts are a poor guide: it changed no count at all and took 5.69% off the
geometric mean. So the interpreter was sampled instead, and the answer is not on the shortlist.

**THE HEADLINE, AND IT IS ONE LINE: 45.6% OF ALL SAMPLES ARE INSIDE `sysl.buf`'s ACCESSORS.**
`Buf.at`, `Buf.push`, `Buf.set` and `Buf.len` are not inlined, they are ordinary calls, and each one
**retains and releases the buffer** and does **two** bounds checks before it copies the element out.
The interpreter spends about as much time entering and leaving those functions as it does doing
everything else put together.

### How it was taken

macOS `/usr/bin/sample` at a 1 ms interval, each program started and sampled in one shell call, run
serially under `caffeinate -dimsu` on a box at 94.0% idle with `pgrep -x java` empty. `sample`'s
**"Sort by top of stack, same collapsed"** section is self time and is what every figure below reads;
the denominator is the main thread's sample total from the call graph's head.

- **The build keeps its symbols with no flag.** `sysl build .` does not strip, so `nm` and the
  sampler name every sysl function. `sysl build --help` has no symbol option and none is needed.
- **Twenty of the twenty-three programs are here.** `startup` was not sampled; `strindex` (12.2 ms)
  and `strwalk` (13.7 ms) **exit before the sampler can attach** and produced no report at all. Both
  are already faster than CPython (0.72x and 0.90x), so neither has anything to contribute to the
  gap this page is about.
- **`sample` truncates its self-time table at 5 samples per name**, so a per-program column sums to
  a little under 100%; the aggregate accounts for 96.7%.
- **An unnamed region.** The first ~500 KB of `__text` carries no symbols, so the sampler reports
  `???`. The routine at `__text+0xa7ac` is a refcount decrement followed by the deferred-free walk —
  **sysl's ARC release** — and it is named that below. Its address is reported as an ASLR-varying
  absolute, so it is keyed by the load-relative offset.

### The aggregate

Weighted by each program's **slate/CPython ratio**, so the ranking favours what closes the Python
gap. Unweighted is the plain share of all 19,349 samples. The two agree closely, which is itself
worth knowing: nothing here is an artefact of one slow program.

| self time | unweighted | weighted by slate/py | what it is |
|---|---|---|---|
| `Buf.at<Value>` | **14.33%** | **14.18%** | every operand-stack and slot read |
| `run_frames` | **12.56%** | **12.74%** | the loop itself, and every instruction arm inlined into it |
| `Buf.at<Ins>` | **12.37%** | **12.26%** | ONE per dispatch — fetching the instruction |
| `Buf.push<Value>` | **8.60%** | **8.63%** | every operand-stack push |
| `pop` | **6.97%** | **6.68%** | slate's own stack pop |
| `Buf.at<Chunk>` | 3.48% | 4.02% | the chunk, re-read per call (13.0% on `fib`) |
| `_platform_memmove` | 3.30% | 1.11% | almost all of it is `strings` (78.3% of that one program) |
| `_tlv_get_addr` | 2.83% | 2.99% | thread-local lookup, reached from the ARC free list |
| `Buf.at<Entry>` | 2.21% | 2.48% | an object's table (11.5% `fields`, 10.8% `methods`) |
| `match_walk` | 1.84% | 1.99% | `for` heads, `match` arms, destructuring |
| `gc.alloc` | 1.63% | 2.25% | 15.8% `alloc`, 15.0% `csv`, 9.7% `calls` |
| `keepable` | 1.50% | 1.58% | the `undefined` refusal, on every store |
| ARC release (`__text+0xa7ac`) | 1.44% | 1.65% | 8.1% on `fib`, 4.1% on `closures` |
| `scan_named` | 1.18% | 1.28% | a name in an object's table |
| `Map.find<string,Value>` | 0.98% | 0.88% | 7.6% on `globals` alone |
| `Buf.set<Value>` | 0.96% | 0.85% | 8.1% on `sorting` |
| `peek` | 0.92% | 1.04% | |
| `obj_get_name` | 0.65% | 0.71% | 3.5% on `methods` |
| `hash_str` | 0.54% | — | 5.4% on `globals` |
| `lay_standing` | 0.45% | 0.55% | laying a call's window |
| `placed_call` | 0.43% | 0.52% | which of the three call paths |
| **`methods_of`** | **0.18%** | — | **see the correction below** |

Rolled up: **`Buf.*` 45.6% / 46.5%**, allocator plus collector 4.2% / 4.8%, ARC release plus its
thread-local 4.3% / 4.6%, `Map<string, Value>` 2.1%.

### Per program, the top five

| benchmark | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| arith | `Buf.at<Ins>` 22.0 | `Buf.at<Value>` 21.7 | `Buf.push<Value>` 14.9 | `pop` 14.2 | `run_frames` 12.0 |
| reals | `Buf.at<Ins>` 19.3 | `Buf.at<Value>` 18.8 | `pop` 14.5 | `Buf.push<Value>` 13.4 | `run_frames` 12.8 |
| globals | `Buf.at<Ins>` 10.3 | `run_frames` 8.6 | `Buf.push<Value>` 7.9 | `Map.find` 7.6 | `pop` 6.4 |
| funcs | `Buf.at<Value>` 21.0 | `run_frames` 16.2 | `Buf.at<Ins>` 13.9 | `Buf.push<Value>` 10.6 | `pop` 7.9 |
| fib | `run_frames` 17.7 | `Buf.at<Ins>` 15.1 | `Buf.at<Value>` 14.2 | `Buf.at<Chunk>` 13.0 | `Buf.push<Value>` 8.2 |
| calls | `gc.alloc` 9.7 | `Buf.at<Ins>` 9.6 | `Buf.at<Value>` 7.4 | `Buf.at<Chunk>` 7.3 | `run_frames` 7.0 |
| methods | `run_frames` 19.2 | `Buf.at<Value>` 11.2 | `Buf.at<Entry>` 10.8 | `Buf.at<Ins>` 10.3 | `Buf.push<Value>` 6.7 |
| closures | `run_frames` 17.6 | `Buf.at<Value>` 15.0 | `Buf.at<Ins>` 12.7 | `Buf.at<Chunk>` 10.5 | `Buf.push<Value>` 7.6 |
| nested | `Buf.at<Value>` 15.5 | `run_frames` 11.7 | `Buf.at<Ins>` 10.6 | `Buf.push<Value>` 8.6 | `Buf.at<Chunk>` 8.2 |
| loops | `Buf.at<Value>` 19.1 | `match_walk` 16.0 | `Buf.at<Ins>` 14.2 | `Buf.push<Value>` 10.9 | `run_frames` 8.3 |
| options | `run_frames` 14.2 | `Buf.at<Value>` 12.2 | `Buf.at<Ins>` 9.2 | `Buf.push<Value>` 7.5 | `pop` 5.5 |
| fields | `run_frames` 12.7 | `Buf.at<Value>` 12.3 | `Buf.at<Entry>` 11.5 | `Buf.at<Ins>` 10.9 | `Buf.push<Value>` 7.5 |
| alloc | `gc.alloc` 15.8 | `Buf.at<Ins>` 10.1 | `run_frames` 8.7 | `Buf.push<Value>` 8.5 | `Buf.at<Value>` 8.0 |
| arrays | `Buf.at<Value>` 17.9 | `Buf.at<Ins>` 17.0 | `Buf.push<Value>` 11.2 | `run_frames` 11.1 | `pop` 9.4 |
| mapset | `Buf.at<Value>` 16.0 | `Buf.at<Ins>` 11.3 | `run_frames` 11.1 | `Buf.push<Value>` 7.6 | `methods_of` 7.2 |
| dispatch | `Buf.at<Ins>` 16.4 | `run_frames` 15.7 | `Buf.at<Value>` 15.4 | `Buf.push<Value>` 10.1 | `pop` 7.6 |
| branches | `run_frames` 24.9 | `Buf.at<Ins>` 18.9 | `Buf.at<Value>` 18.1 | `pop` 13.8 | `Buf.push<Value>` 11.0 |
| sorting | `Buf.at<Value>` 40.3 | `merge_sort` 20.3 | `arith` 11.7 | `Buf.set<Value>` 8.1 | `int_arith` 6.8 |
| csv | `gc.alloc` 15.0 | `run_frames` 7.0 | `Buf.at<Value>` 7.0 | `Buf.push<Value>` 7.0 | `Buf.push.string` 4.8 |
| strings | `memmove` 78.3 | `Cursor.next` 7.8 | `mach_absolute_time` 1.9 | `trace_env` 1.9 | `gc.alloc` 1.1 |

**`strings` is not an interpreter benchmark and should stop being read as one** — it is one
`memmove`, and it is already 1.29x CPython. **`sorting` is `Buf.at<Value>` and nothing else**, its
comparator walking the array through the same accessor the interpreter reads its stack with.

### The dispatch: a jump table, one range check, and a CALL to fetch the instruction

`run_frames` compiles to 17,493 instructions — every arm is inlined into it — and its `match` has
exactly **one** indirect branch. This is the top of the loop, read out of the shipped binary with
`otool -tvV`:

```
1004cfde4  bl   _sysl.buf$Buf.at.dev.slatelang.slate$Ins   ; <- the fetch is a CALL
1004cfde8  mov  x21, x1
1004cfdec  add  x23, x19, #0x1                             ; pc += 1
1004cfdf0  cmp  w0, #0x65                                  ; 101 opcodes
1004cfdf4  b.hi 0x1004d1c18                                ; -> the switch default
1004cfdf8  mov  w8, w0
1004cfdfc  adrp x11, 648 ; 0x100757000
1004cfe00  add  x11, x11, #0x96e                           ; the jump table
1004cfe04  adr  x9, #-496
1004cfe08  ldrh w10, [x11, x8, lsl #1]                     ; a 16-bit offset per opcode
1004cfe0c  add  x9, x9, x10, lsl #2
1004cfe10  br   x9                                         ; ONE indirect branch
```

So, plainly, and each of these was asked:

- **Is the `match` a jump table?** **Yes** — a compact 16-bit-offset table indexed by the opcode,
  resolved in five instructions and one `br`. There is no chain of compares. Nothing to win here.
- **Is there a bounds check per dispatch?** **Yes, two, and they are inside `Buf.at<Ins>`.** The
  `cmp w0, #0x65` above is the switch's own range check on the opcode and is one instruction. The
  real checks are the length and capacity compares in the accessor.
- **Is `Buf.at<Ins>` inlined?** **No.** It is a `bl` to an out-of-line function, once per
  instruction executed, and that function is 12.37% of all sampled time.

### What `Buf.at` actually does, which is the finding

`Buf.at<Ins>` in full, to the element load:

```
10060d5c4  sub  sp, sp, #0x70            ; a 112-byte frame
10060d5c8  stp  x28, x27, [sp, #0x10]    ; six pairs: twelve callee-saved registers spilled
10060d5cc  stp  x26, x25, [sp, #0x20]
10060d5d0  stp  x24, x23, [sp, #0x30]
10060d5d4  stp  x22, x21, [sp, #0x40]
10060d5d8  stp  x20, x19, [sp, #0x50]
10060d5dc  stp  x29, x30, [sp, #0x60]
10060d5e0  mov  x19, x0
10060d5e4  cbz  x0, 0x10060d5f4
10060d5e8  ldr  x8, [x19]                ; RETAIN self
10060d5ec  add  x8, x8, #0x1
10060d5f0  str  x8, [x19]
10060d5f4  cmp  x4, x3                   ; bounds check 1 (length)
10060d5f8  b.hs 0x10060d748
10060d5fc  cmp  x4, x2                   ; bounds check 2 (capacity)
10060d600  b.hs 0x10060d754
10060d604  mov  w8, #0x38                ; sizeof(Ins) = 56 bytes
10060d608  madd x8, x4, x8, x1
10060d60c  ldp  x21, x20, [x8, #0x18]    ; the element, four loads
10060d610  ldp  x23, x22, [x8, #0x8]
10060d614  ldr  w0, [x8]
10060d618  ldp  x24, x25, [x8, #0x28]
10060d61c  cbz  x19, 0x10060d710
10060d620  ldr  x8, [x19]                ; RELEASE self
10060d624  subs x8, x8, #0x1
10060d628  str  x8, [x19]
10060d62c  b.ne 0x10060d710              ; ...and if it hit zero, the deferred-free walk,
10060d630  adrp x26, 733 ; 0x1008ea000   ;    two thread-local getter calls below
```

**`Buf.at` takes `self` by value, so reading one element of an array retains and releases the array.**
`Buf.at<Value>` is the same function with `#0x28` (a `Value` is 40 bytes) in place of `#0x38`. That
pair is 26.7% of all sampled time, and between them they do: one call, twelve register spills, one
atomic-free increment, two bounds checks, a 40- or 56-byte copy, one decrement, and a branch to a
free-list walk that is where `_tlv_get_addr`'s 2.83% comes from.

**THIS IS A FINDING ABOUT `sysl.buf`, NOT ABOUT slate.** `Buf.at` is sysl's standard module. Nothing
in this repository can inline it or stop it counting, so the fix is one of two things and only the
second is slate's: a sysl change that lets `Buf.at` take `self` by reference and be inlined at `-O1`,
or slate holding its operand stack, its code array and its chunk table in raw memory it indexes
itself. **Neither is a thing to start without the user, and the first belongs to `sysl-bootstrap` and
its own release.**

**CLOSED, PARTIALLY, IN sysl 0.0.122.** The first fix landed: a by-value `Buf` parameter is borrowed
— no retain, no release — when the function writes no memory and every call in it is `-> never`,
which is `Buf.at`'s shape once its index panic was moved out of line. `Buf.at`/`len`/`cap`/… now
inline at `-O1` with no frame of their own. **What remains is the SECOND of the two bounds checks
inside `Buf.at`** — the length check is gone with the retain/release, the capacity check is not — an
open sysl design question rather than a slate one. See the 2026-09-21 write-up below for what this
was worth measured on slate's own source.

### The re-ranked shortlist

Share is the weighted aggregate above. A ceiling is what the item could take off the geometric mean
if it removed **all** of the named cost, which none will.

| rank | candidate | measured share | ceiling | kind | files |
|---|---|---|---|---|---|
| — | ~~**Borrowed reads: stop `Buf.at`/`push`/`set` retaining, and get them inlined**~~ | **46.5%** of wall | **LANDED in sysl 0.0.122** (not here): a by-value `Buf` parameter is borrowed when the function writes no memory and every call in it is `-> never`, so `Buf.at`/`len`/`cap`/… inline at `-O1` with no frame and no retain/release. See the 2026-09-21 sysl-0.0.122 write-up below | STRUCTURAL, landed in `sysl-bootstrap` | `sysl-bootstrap`'s `buf.sysl` |
| 2 | **A narrower `Value`, or NaN-boxing** | 24.8% (`Buf.at/push/set/len<Value>`) | 10-15% — 40 bytes to 16 cuts the copy at every read, push, set and frame lay | **STRUCTURAL — not piecemeal** | `value.sysl` and every native |
| 3 | **A register machine instead of a stack machine** | 15.3% (`Buf.push<Value>` + `pop` + `peek`), plus its share of `Buf.at<Ins>` | 10-15%, and it subsumes 4 | **STRUCTURAL — not piecemeal** | `emit.sysl`, `run_frames.sysl`, `slots.sysl` |
| — | ~~**Superinstructions**~~ | 12.3% (`Buf.at<Ins>`), pro rata with dispatches removed | **LANDED (`superinstructions`, 2026-09-21): -9.17% geometric mean, `branches` -24.1%, `arith` -19.3%, `reals` -18.8%, `arrays` -18.1%, twenty-two of twenty-three faster** — the largest single win on this page, and the estimate of 4-6% was less than half of it. **The four pairs were MEASURED and three of the five guessed here were wrong**: `LoadSlot`+`PushInt`, `LoadSlot`+`LoadSlot`, `Add`+`StoreSlot`, `Less`+`JumpIfFalse`; `Dup`+`StoreSlot` and `LoadSlot`+`Ret` are not in the top eighteen at all. The write-up is at the foot of this page | INCREMENTAL | `code.sysl`, `emit.sysl`, `run_frames.sysl`, `run_fused.sysl` |
| — | ~~**Cheaper frames — stop re-reading the `Chunk` per call**~~ | 4.0%, and **13.0% on `fib`**, 10.5% `closures`, 8.2% `nested`, 7.3% `calls` | **LANDED (`chunk-per-call`, 2026-09-21): -3.02% geometric mean, `fib` -16.9%, `funcs` -13.3%, `closures` -8.4%, `nested` -8.3%** — the write-up is at the bottom of this page | INCREMENTAL | `run_frames.sysl`, `execute.sysl`, `vm.sysl`, `generator.sysl` |
| — | ~~**`-O2` as the default**~~ | **-2.3% geometric mean, no program >3% slower (dev `4820c05`, see the 2026-09-21 write-up below)** | **LANDED (sysl 0.0.122, `optimization = "2"` in `package.hocon`): -6.52% geometric mean over the two builds alternated, on top of the 0.0.122 compiler gain itself.** See the 2026-09-21 sysl-0.0.122 write-up below | INCREMENTAL | `package.hocon` |
| 7 | **Module-level `var` cells, `StoreDef`** | 2.6% over the set, **23% of `globals`** (`Map.find` 7.6 + `hash_str` 5.4 + `Map.get` 4.5 + `Map.put` 3.8) | 0.5% of the mean, 15%+ of one program — the reach column's usual reading | INCREMENTAL | `defs.sysl`, `emit.sysl`, `compile.sysl` |
| 8 | **Inline caches for a field or a method** | 4.5% (`Buf.at<Entry>` 2.5 + `scan_named` 1.3 + `obj_get_name` 0.7); 22% of `fields`, 21% of `methods` | 2-3% | INCREMENTAL, and the largest incremental item that is wholly slate's | `index.sysl`, `table.sysl`, `run_frames.sysl` |
| — | ~~**`methods_of` looking a method up by name at every call**~~ | **0.18%** | **STRUCK.** It was the named remainder of item 11 and it is not a cost: 7.2% on `mapset` and invisible on all nineteen others | — | — |
| — | ~~**`lay_frame`**~~ | **below 5 samples on every program** | **STRUCK.** It does not appear in any self-time table. `lay_standing` beside it is 0.55% | — | — |

### What the samples contradict, and it is worth saying plainly

- **`methods_of` was the stated next item and it is 0.18% of wall.** The shortlist's item 11 ends
  *"`methods_of` looking a method up by name every time is what is LEFT of this item"* — true as a
  description and worth nothing as a target. `mapset` is the only program that can see it.
- **`lay_frame` was a suspect and is not measurable.** It never reaches the five-sample floor.
- **The earlier partial profile put ARC on operand-stack reads at "11-12% of a call-heavy profile"
  and the dispatch at "~17%".** Both figures were low and both were attributed too narrowly: the ARC
  traffic is not a property of operand-stack reads, it is a property of **every** `Buf` access, and
  the "dispatch loop" figure lumped `run_frames` with `Buf.at<Ins>` when those are two separate
  costs with two separate fixes.
- **`LoadSlot` at 18.0% and `PushInt` at 8.6% of instructions were finding 9's argument for a
  register machine.** The sampler agrees with the direction and halves the prize: the stack traffic
  those instructions cause is 15.3% of wall, not 26.6%, because an instruction's count says nothing
  about what it costs.
- **The honest summary of the gap, restated.** slate is **4.29x** CPython and **8.21x** Lua on the
  geometric mean today. Nearly half of the wall clock is the cost of reaching into a `Buf`, and that
  is one decision — `Buf.at` taking `self` by value — repeated a few hundred million times a second.
  Everything else on the list above is worth single-digit percentages.

