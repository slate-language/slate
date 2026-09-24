# 2026-09-24 — A BUILTIN METHOD IS CALLED WHERE IT STANDS, AN INTEGER KEY IS ITS OWN HASH, AND A THROWN-AWAY ANSWER IS NEVER PUSHED

`mapset` was the last row far behind Lua after 0.1.5: **4.7x** on `run.sh`, every other row at 2.5x
or better. Its loop is `m.set(i % 1000, i)` and `s.add(i % 1000)` two million times. Sampled on a
PGO build of dev `81ad883` (`xctrace` Time Profiler, the loop run fifty times longer, leaf addresses
bucketed against `nm` — `sample` alone could not say where inside `run_frames` the time went, the
whole chain having been inlined into it):

- **`run_frames` 60%, `obj_put` 28%, the natives' closure bodies 10%.** Inside `run_frames`: the
  dispatch branch, then the builtin call path — two `_tlv_get_addr` calls (`current()` in
  `standing_native`, `profile_on` in `call_native`), and an **atomic increment and decrement of the
  `&sync` box** around `run_native`'s indirect call — plus a counted `string` retained and released
  for the method's name on every call (`Buf.at.string`, never looked at on a cache hit).
- **`obj_put`'s probe loop mispredicted.** The key hashed through splitmix and the probe started
  from its low bits, so about one lookup in three met another key first — and the branch that says
  so is a coin toss.
- **13 instructions a turn**: `LoadSlot2; PushInt; Rem` twice (the pair of loads took the head of
  the `SlotIntRem` run), and `CallMethodKept; Discard` twice.

What changed, in the order it was measured:

1. **The native table is `[MaxNatives]NativeGo`, filled with `unregistered`, and called where it
   stands** (`native_fn.sysl`). Matching `Some(go)` bound a copy of the `&sync` box — `retain_sync`
   before the call, `release_sync` after, both locked read-modify-writes. `native_go[i](args, at)`
   borrows the element (checked in the emitted IR), which is sound because a slot is written once,
   before its id is published, and never again. Every builtin call in every program loses both.
2. **`Args` carries the `*Vm`**, and `standing_native` is handed the one `run_frames` already holds.
   `Args.at` reads `self.vm.machine` rather than `machine()`, so the set and map natives take their
   arguments with no thread-local lookup at all.
3. **`profile_on` is read once where `run_frames` starts** (`timing_here`), and `standing_native`
   goes straight to `run_native` when it is off. **The method's name is read only on a miss**
   (`builtin_from_site` takes its place in the table).
   *Steps 1–3 together: `mapset` 83.1 → 72.0 ms (−13.4%).*
4. **An integer key already in an indexed table is found inline** — `obj_int_at` in `table.sysl`,
   `held_int` in the five set/map natives — writing the value with `obj_set_value_at` rather than
   calling `obj_put`. Everything it is unsure of goes back to the general road: no index, a table
   keyed by identity, a key not there, and an entry whose hash agrees but whose key is not an
   integer — `1.0` stored and `1` asked, which `same` calls one key. *71.1 → 63.3 (−10.9%).*
5. **A call whose answer is only discarded is marked** — `AnswerUnused`, bit 30 of the packed
   count, set by `fuse` on a `CallFn`/`CallMethod` followed by `Discard`. A builtin's answer is then
   not pushed and the `Discard` is stepped over; every other callee ignores the bit and returns to
   the `Discard`, which still stands. `standing_native` also skips the `undefined` refusal under
   `KeptArgs`, as the in-place path already did.
6. **A pair of loads no longer takes the head of a remainder run**: `LoadSlot; LoadSlot; PushInt;
   Rem` is `LoadSlot; SlotIntRem` (`slot_rem_at` in `emit.sysl`). With 5, the loop is **9
   instructions a turn instead of 13**. *5 + 6: 65.2 → 55.7 (−14.7%).*
7. **An integer hashes as itself, and every probe starts from the TOP bits of the hash times the
   golden ratio** (`home` in `table.sysl`, Knuth's multiplicative hashing). Consecutive integers
   land in distinct slots with no collision, and — the reason a low-bit mask could not take an
   identity hash — so do keys a power of two apart, and so does a class's own `hash`, which is
   whatever integer the program answered. *53.3 → 42.7 (−20.0%).*

Not built: a new `Op` for "call cached native N" — once 1–3 and 5 had landed the builtin arm was a
bounds check, an indirect call and a result test, with no general machinery left to skip; and
inlining `placed_call`'s `Native` arm into `placing`, which PGO had already done.

Control: a detached PGO build of dev `81ad883`; branch `mapset-chain` at its last commit before the
merge of `origin/dev`. Both `bench/pgo.sh`, sysl 0.0.131.

## The numbers

Alternating best-of-9 (`bench/alternate.pl`), PGO against PGO, lowest of each. The box was 77–86%
idle, other agents' builds running.

| program | dev `81ad883` | `mapset-chain` | change |
|---|---|---|---|
| alloc | 134.576 | 134.376 | −0.1% |
| arith | 86.116 | 84.482 | −1.9% |
| arrays | 127.472 | 120.622 | −5.4% |
| branches | 158.827 | 164.364 | +3.5% |
| calls | 124.973 | 121.713 | −2.6% |
| closures | 76.646 | 78.689 | +2.7% |
| csv | 140.155 | 132.148 | −5.7% |
| dispatch | 142.772 | 139.280 | −2.4% |
| fib | 146.878 | 144.953 | −1.3% |
| fields | 92.686 | 91.459 | −1.3% |
| funcs | 75.799 | 78.115 | +3.1% |
| globals | 107.952 | 106.163 | −1.7% |
| loops | 103.320 | 100.676 | −2.6% |
| **mapset** | 82.359 | 44.889 | **−45.5%** |
| methods | 176.034 | 165.188 | −6.2% |
| nested | 163.968 | 162.364 | −1.0% |
| options | 161.518 | 157.303 | −2.6% |
| reals | 125.434 | 127.292 | +1.5% |
| sorting | 133.868 | 122.383 | −8.6% |
| startup | 4.954 | 4.960 | +0.1% |
| strindex | 5.377 | 5.474 | +1.8% |
| strings | 11.866 | 11.672 | −1.6% |
| strwalk | 6.596 | 6.448 | −2.2% |
| **geometric mean** | | | **−4.11%** |

The rows that read slower were run again, best-of-15 alternating: `branches` −0.2%, `funcs` −2.8%,
`closures` +1.7%, `reals` −0.4%, `strindex` +0.9% — PGO layout, which moves call-free programs
±3% between two builds of one tree; none of the five touches a builtin or a table in its loop.

Against the yardsticks, `bench/run.sh -n 9` on each binary:

| program | dev | branch | dev/lua | branch/lua |
|---|---|---|---|---|
| mapset | 82.0 | 44.6 | 4.7x | **2.4x** |

## The witness

`SLATE_PROFILE` on a `--features profile` build: `mapset` executes 26,011,038 instructions on dev
and 18,011,037 on the branch — `LoadSlot2` 4,002,000 → 2,000, `PushInt` and `Rem` 4,000,003 → 3,
`SlotIntRem` 0 → 4,000,000, and the 4,000,000 `Discard`s stepped over rather than dispatched.
`bench/check.sh pgo/slate`: all four runtimes' answers unchanged. The branch's profile of `mapset`
has no `obj_put`, no `Buf.at.string` and no atomic in the builtin path; what is left is the
dispatch branch, `Rem`'s divide, and the probe itself.

Tests: `tests_mapset_chain.sysl` — an unregistered id still answers its sentence; a window carries
its VM; `1.0` stored and `1` asked is one key in a map and a set; negative keys and both ends of a
`long`; keys 4096 and 65536 apart all found; **`longest_probe`** (the witness for `home`) under 16
for a run of 2,000 integers and for strides of 4096 and 1,048,576; a discarded call is marked and
stands over its `Discard`; every kind of callee called as a statement leaves the stack balanced; a
refused call as a statement is caught; `SLATE_PROFILE` still counts a discarded builtin; the
remainder run is folded after another load. `tests/lang/mapchain.sl` asks the same of both back
ends. `tests_vm_state.sysl`'s type census now names `[MaxNatives]NativeGo`.

## What is left

- **`mapset` is 2.4x Lua.** Lua keeps integer keys `1..n` in an array part: a set is one indexed
  store. Here it is a hash, a probe and an entry read — cheap now, but three dependent loads.
- **`Rem` is a hardware divide** by a literal; a multiply-by-reciprocal fold is the obvious next
  piece and is not specific to this program.
