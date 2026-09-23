# 2026-09-23 — A PROPERTY READ HANDS THE NATIVE THE RECEIVER WHERE IT STANDS — profile 5's new item

Profile 5's newest row, the one that was hiding under the struck `mach_absolute_time` row. `xs.length`,
`s.length` and `m.size` are builtin calls: `length` **is** the free function `NLen`, so a property read
runs a native with exactly one argument, the value being read from. `native-args` (0.0.60) took the
argument buffer off every other builtin call in the language and left this path on it, listed in
`CLAUDE.md` among "the callers that genuinely have one". **It does not have one.** The receiver is
already standing on the operand stack when the read is made — the field instruction keeps it there
across the read, a `get` property being able to run slate code — so the window points at the cell the
value is already in.

Control `c44de94` (dev, slate 0.1.2, sysl 0.0.126); branch `property-reads`.

## What the read path was

`GetField` → `read_field_site` (`site_cache.sysl`) → `read_field_of_kind` (`index.sysl`), which asked
`builtin_property` for the native and then:

```sysl
builtin_property(target, name) match
    Some(p) ->
        var args: Buf[Value] = buf()

        args.push(target)

        return call_native_buf(p, args, at)
```

A `Buf` malloc, a push, a copy onto the stack inside `call_native_buf`, a truncate and a free — **per
property read**, 5,000,010 of them in `bench/arrays.sl`.

## What it is

`read_field_of_kind` takes a fourth argument, `standing: bool`, which says whether the target is the
top cell of the operand stack. The two callers answer it from what they know and nothing else changes:

- **`read_field_site` passes `true`.** Its only caller is the `GetField` arm, which reads
  `peek_on(vm, 0)` and leaves it standing; that is now written on the function as what the caller owes.
- **`read_field` passes `false`.** Its callers (`actor.sysl`, `actor_run.sysl`, `tests_decls.sysl`)
  hold the value in a sysl local, where there is nothing for a window to point at.

`standing_property(f, at)` in `execute.sysl` is the new half, and it is `standing_native` with the
geometry of a read rather than of a call:

```sysl
standing_property(f: NativeFn, at: Span) -> Step
    val vm = machine()
    val top = vm.stack.len()
    val answer = call_native(f, Args(top - 1, 1), at)

    answer match
        Err(Wait) -> ()
        _ -> vm.stack.truncate(top)

    answer
end standing_property
```

**The receiver is not cut off here, because the instruction cuts it** — `GetField` truncates by one
and pushes the answer, which is `standing_native`'s own move written at the caller. Taking it off here
as well would cut into whatever stands underneath. The height is restored so a builtin that pushed
does not leave something else standing where the receiver was, and the restore is skipped after a park
for `call_native_buf`'s reason.

**Nothing else moved.** `builtin_receiver` never ran the native — it answers *"`length` is a property,
not a method"* — the checker's `property_result` asks the table for a TYPE, `SetField`'s read-only
refusal only asks whether a property exists, and the JavaScript back end has no operand stack and was
untouched. `apply`, the callback path and a spread call keep `call_native_buf` unchanged.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `c44de94` against the branch, on a box at 83%
idle with `pgrep -x java` empty.

| program | control | branch | change |
|---|---|---|---|
| **arrays** | 507.0 | 365.9 | **−27.8%** |
| **strwalk** | 9.93 | 9.07 | **−8.7%** |
| **csv** | 320.0 | 303.3 | **−5.2%** |
| **strindex** | 8.18 | 7.79 | **−4.7%** |
| startup | 4.65 | 4.43 | −4.7% |
| arith | 356.7 | 348.6 | −2.3% |
| nested | 404.7 | 398.2 | −1.6% |
| methods | 540.1 | 534.0 | −1.1% |
| reals | 551.8 | 547.3 | −0.8% |
| fib | 562.2 | 558.4 | −0.7% |
| strings | 723.0 | 718.4 | −0.6% |
| loops | 202.9 | 202.1 | −0.4% |
| globals | 740.4 | 737.4 | −0.4% |
| mapset | 384.2 | 385.5 | +0.4% |
| funcs | 277.4 | 282.7 | +1.9% |
| **geometric mean, all twenty-three** | | | **−2.59%** |

`bench/run.sh -n 5`, both binaries in the same run: the geometric mean against Lua goes **3.5x →
3.4x**, against `node --jitless` **2.7x → 2.6x**, against CPython **1.9x → 1.8x**, against QuickJS-ng
unchanged at 2.2x. `arrays` alone goes **5.5x → 4.0x** Lua and 3.2x → 2.3x `node --jitless`; `csv`
1.1x → 1.0x Lua.

**`strwalk` and `strindex` are the reading to keep**, because they are the ordinary shape: a character
walk is `while i < s.length`, so the read is once a turn beside the work, and there is no way to write
round it — `len(x)` was taken out of the language in favour of the property.

## `SLATE_PROFILE` COULD NOT SEE THIS, AND THAT IS WORTH KNOWING BEFORE READING ANOTHER PROFILE

The item was priced off `SLATE_PROFILE=1`'s per-builtin table, where `length` reads 5,000,010 calls
and ~200,000 µs on `arrays.sl`. **That number does not move.** Three runs a side:

| | control | branch |
|---|---|---|
| `length` µs | 196,415 / 193,033 / 197,004 | 198,511 / 192,722 / 200,275 |

`profile_began()`/`profile_native()` bracket `run_native` inside `call_native`, and the `Buf` malloc,
the push, the copy and the free all happened **outside** it, in `call_native_buf`. So the instrument
timed the only part of the call that was already cheap: `length` costs ~39 ns and `push` ~44 ns on the
same page, which reads as a builtin doing its share of real work. **A per-builtin timer prices the
native and not the call**, and what was removed here is about 28% of a program the timer said was
fine.

## The witness that could see it: `sample`

One 1 ms sample of `./slate bench/arrays.sl` a side, main thread:

| | control | branch |
|---|---|---|
| samples | 369 | **269** |
| the `free` node | **52 (14.1%)** — three `_xzm_free` frames, with `mach_absolute_time` 32 under the first | **0** |
| `Buf.grow<Value>` + malloc | **31 (8.4%)** — `_xzm_xzone_malloc_tiny` 17, `_xzm_xzone_malloc` 6, `_malloc_zone_malloc` 3 | **0** |
| `call_native_buf` | 10 | **gone from the binary's hot set** |
| `standing_property` | — | 10 |

**Not one malloc or free frame appears anywhere in the branch's sample** (`grep -c` over the whole
report: 10 → 0). The 27.8% of wall and the 27% of samples agree, and the `free` node the gc write-up
measured at 16.6% on an older tree was this and nothing else.

## The tests

**`Vm.args_buffered` is the witness and it had to be able to disagree.** The buffered property path now
charges it, exactly as the two call instructions do, so a revert of the standing path would show up as
ten thousand charges rather than as nothing at all.

- **`A_PROPERTY_READ_OF_A_BUILTIN_KIND_COPIES_NOTHING_EITHER`** (`tests_slots.sysl`) — 10,000 reads of
  `xs.length`, `s.length` and `m.size`, each asserted under the incidental floor, with the program's
  own printed answer asserted so a program that did not compile cannot pass.
- **`A_PROPERTY_READ_ADDS_NOTHING_TO_A_CALL_THAT_DOES_BUFFER`** — the control that could disagree, and
  it stands in the same program as the reads: `abs(...[0 - xs.length])` is charged once a turn for the
  spread, and the ten thousand property reads beside it leave the count at one each rather than two.
- **`A_PROPERTY_READ_READS_THE_RECEIVER_THE_INSTRUCTION_LEFT_STANDING`** (`tests_native_args.sysl`) —
  the megabyte heap, `tests_native_args`' own method: `[deep(200).a, 2, 3].length` in a loop that
  collects under it, where the receiver is a value nothing else holds, plus a `Set` built the same way
  read through `size`. **A window off by one reads whatever stands beneath**, which here is the running
  total — an integer, which `length` refuses — so a misread is a fault and not a wrong number.
- **`A_PROPERTY_IS_A_BUILTIN_CALL_ON_THE_VALUE_IT_IS_READ_FROM`** (`tests/lang/builtinargs.sl`, both
  back ends) — every kind that answers either name, in one loop that allocates under them: an array, a
  string, `bytes`, a range, a `Set` and a `Map`, plus a read on an expression rather than on a name.
- **`A_PROPERTY_CALLED_AS_A_METHOD_IS_STILL_TOLD_WHICH_IT_IS`** — the sentence beside the read, which
  does not go through it, on both back ends.

**Instruction counts are unchanged and could not have changed**: no `Op` was added, removed or emitted
differently, and nothing under the compiler was touched — the whole change is below `GetField`'s
callee. `sysl test . --features profile` is green, and `bench/check.sh` reports all four
implementations' answers unchanged.
