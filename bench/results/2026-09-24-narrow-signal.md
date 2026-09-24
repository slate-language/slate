# 2026-09-24 — A `Signal` IS NO WIDER THAN A `Value`, AND `Step` IS 32 BYTES

The follow-up `narrow-value` named: with `Value` at 16 bytes, `Step = Result[Value, Signal]` was
still 64, held there by `Signal.Fail`. It is 32 now. **The measured answer is that the width no longer
matters**: the geometric mean moves −0.34%, inside the noise, both orderings agreeing.

Control `38dfd77` (dev); branch `narrow-signal`.

## What was wide, and where it went

A sysl enum is a tag and its widest variant's payload. After `signal-slim` and `narrow-value`:

| variant | payload before | now |
|---|---|---|
| `Fail(at: Span, src: u32, carried: u32, message: string)` | **48 B** — a span (two words), two halves of one word, a string (three words) | `Fail(raised: &Raised, carried: u32)`, 12 B |
| `Skip(at: Span, src: usize, reason: string)` | 48 B | `Skip(raised: &Raised)`, 8 B |
| `Quit(at: Span, src: usize, status: long)` | 32 B | `Quit(raised: &Raised, status: long)`, 16 B |
| `Ret(v: Value)` | 16 B | unchanged, and now the widest |

- **The place and the sentence are behind a COUNTED BOX, `&Raised { at, src, text }`, not in a VM
  table.** The brief suggested a `Vm.faults` table indexed by a `u32`, as `carried` is. That shape was
  forced on `carried` because a `Value` in sysl memory is no root; a span and a sysl `string` are not
  collected values at all, so the box is enough — and a counted box needs no rule about which reader
  frees the entry. A `Signal` is copied freely while it travels (into `suppressed`, into a promise
  and back, across `guarded`'s loop); the last copy dropped gives the box back. A table would have
  needed a take-exactly-once discipline over the message, which has several readers per fault (the
  reporter, `fault_value`, `settle_thrown`, `assertFaults`, the page rejection), and a leak on every
  path that drops a fault without taking it.
- **`carried` stays a `u32` in the variant.** It is still an index into `Vm.carried` for the root
  reason, and still taken exactly once by the reader that consumes the fault.
- **`raised(at, src, text)` in `runtime.sysl` is the one constructor**, called by `failure_in` (which
  every fault still comes down to), `quit`, `skipped`, and the three places a promise's remembered
  `Quit` is rebuilt. `fail_source` is gone — `src` is a `usize` again, there being no word to share.
- **What a fault costs is one more malloc**, at the point it is raised — beside the string the
  sentence already was. Nothing on the no-fault path allocates or changes.

## Sites

`runtime.sysl` (the enum, `Raised`, the constructor, `signal_span`/`signal_source`/`signal_message`),
`execute.sysl` (`guarded` and the disposal's suppressed fault, `fault_value`'s `suppressed`),
`async.sysl` (`finish_call`, `settle_quit`, `promise_signal`, the two awaited-rejection rebuilds),
`generator.sysl`, `assert.sysl`, `window.sysl`, `run.sysl`, `script.sysl`, and
`tests_narrow_value.sysl`'s one match. Every one found by the compiler; `run_frames.sysl` untouched
(still 999 lines), `Op` and `Ins` untouched.

## The table

PGO builds both sides (`bench/pgo.sh`), alternating best-of-9, `perl bench/alternate.pl 9 <control>
<branch>`, milliseconds, 91.6% idle and no JVM:

| program | dev `38dfd77` | branch | change |
|---|---|---|---|
| alloc | 136.030 | 135.374 | −0.5% |
| arith | 83.115 | 80.623 | −3.0% |
| arrays | 130.698 | 129.295 | −1.1% |
| branches | 161.392 | 161.325 | −0.0% |
| calls | 127.299 | 127.859 | +0.4% |
| closures | 77.927 | 76.944 | −1.3% |
| csv | 134.830 | 133.496 | −1.0% |
| dispatch | 148.259 | 146.790 | −1.0% |
| fib | 158.753 | 159.443 | +0.4% |
| fields | 97.133 | 96.999 | −0.1% |
| funcs | 79.988 | 85.440 | +6.8% |
| globals | 95.618 | 100.117 | +4.7% |
| loops | 96.669 | 96.956 | +0.3% |
| mapset | 84.515 | 82.687 | −2.2% |
| methods | 184.664 | 193.945 | +5.0% |
| nested | 159.469 | 158.714 | −0.5% |
| options | 171.611 | 173.639 | +1.2% |
| reals | 138.326 | 129.475 | −6.4% |
| sorting | 126.576 | 128.525 | +1.5% |
| startup | 4.451 | 4.297 | −3.5% |
| strindex | 4.975 | 4.854 | −2.4% |
| strings | 11.549 | 11.027 | −4.5% |
| strwalk | 5.724 | 5.728 | +0.1% |
| **geometric mean** | | | **−0.34%** |

**The other ordering agrees on the mean**: branch first, the control reads +0.33%. **The rows that
move by 5–7% move the same way in both orderings** — `funcs` +6.8% / +6.1%, `globals` +4.7% / +5.8%,
`reals` −6.4% / −7.2% — so they are real properties of these two binaries, and they are code layout:
the profile-guided build lays out a different program when a type's width changes, and three programs
land on either side of it. They cancel.

**Why so little, when `signal-slim`'s 112 → 64 was worth 19%?** The likely reading, not measured
further: that regression put a `Value` into
every `Step`'s *copy*: `{ i32, [13 x i64] }` is past what the ABI returns in registers, so every arm
wrote a 112-byte aggregate through memory. At 64 bytes (`{ i32, [7 x i64] }`) the result was already
returned indirectly, and at 32 it still is (AArch64 returns only up to 16 bytes in registers); what an
arm writes on the hot path is `Ok(v)` — the tag and the 16-byte `Value` — whatever the declared size.
The bytes past the widest *written* variant were never touched. So the width stops mattering once no
hot arm writes into it, and this item confirms it rather than finding speed.

## The witness

`sizeof(Signal)` 56 → **24**, `sizeof(Step)` 64 → **32**, `sizeof(Raised)` 48, all three pinned
exactly by `A_STEP_IS_NO_WIDER_THAN_A_VALUE_AND_A_SIGNAL_THAT_HOLDS_ONE` in `tests_carried.sysl`
(the old pin was `<= 64`). Instruction counts identical under `--features profile` (`funcs` 56,000,025,
`fib` 96,949,078, every kind's count equal). `bench/check.sh` answers unchanged for all four
implementations.

## The tests

`tests_carried.sysl`: the three widths; a fault built by `failure_in` and kept in a `Buf` after the
copy that made it is gone still reads its span, file and sentence (the box outliving its maker); a
`quit` and a `skip` keep their place and what they say. The semantic net is the existing one, all green
unedited: `tests/lang/faults.sl` on both back ends, the carried tests (a thousand caught throws, a
rejection crossing a promise, a release's suppressed fault), `tests_async.sysl`'s rejections, the
generator and page paths — full suite 3104/0.
