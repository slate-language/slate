# 2026-09-23 — INTEGERS SORT AS INTEGERS, AN INTEGER KEY IS ONE COMPARISON, AND `undefined`'S CHECK IS INLINE

`mapset` was the worst row against Lua (11.3x on `run.sh`) and `sorting` the one builtin-heavy row
the brief expected Lua to win. Sampled on a fresh build of dev `b95fbcf` (`bench/profile.sl`,
`mapset` with its loop ten times longer so `sample` can attach):

- **`sorting`** was `merge_sort` 57.4%, `int_arith` 13.8%, `arith` 13.4%, `on_values` 8.4%,
  `Buf.grow<Value>` 3.5%. Every comparison of two integers went through the general `<`
  (`on_values` → `arith` → `int_arith`), which has to be ready for reals, text, big integers and a
  mixture it refuses in a sentence.
- **`mapset`** was `run_frames` 28.8%, `find_entry` 12.7%, `keepable_on` 6.1%, `_tlv_get_addr` 5.8%,
  `Args.at` 4.4%, `standing_native` 3.9%, `hash_at` 3.8%, `keys_match` + `same_in` + `same_plain`
  8.9%. The table's probe is one step (1,000 keys in a 2,048-slot index); what cost was around it.

What changed, in the order it was measured:

1. **An array of nothing but integers with no comparator is sorted as `long`s** (`array_sort.sysl`,
   new): taken out into a `Buf[long]`, put in order by `sysl.slices.sort` (introsort, inlined `<`),
   written back. Unstable, and nothing can tell — two equal integers are the same value. One non-`Int`
   (a real, a `Big`, a NaN, text) sends the whole array down the old merge unchanged, and so does a
   comparator. `copy_of` also reserves its length up front (`Buf.grow<Value>` gone).
2. **An integer key is answered in `table.sysl` without the general machinery**: `key_hash` hashes an
   `Int` directly (`hash_plain`'s own arm, without `hash_at`'s hook question) and `keys_match`
   compares two `Int`s with `==` rather than walking `same` → `same_in` → `same_plain`. An `Int`
   against anything else still asks `same`, so `1` still finds `1.0` and a class's `==`/`hash` are
   still consulted.
3. **The set and map natives take `current()` once** — `Args.at` finds the running machine through a
   thread-local on every read, so `do_map_set` paid five `_tlv_get_addr` calls for its arguments and
   two more in `keepable`. `Args.on(vm, i)` reads through a VM already held; `standing_native` takes
   `current()` once for its argument checks too.
4. **`keepable_on` is `@inline` with its sentence `@noinline`** (`absent_refusal`), and so are
   `takes_n` (`too_few`) and `set_of`/`map_of` (`not_a`). **This is the step that moved everything**:
   `run_frames` asks `keepable_on` on every local bind and every argument passed, and out of line the
   call cost more than the one comparison it makes. Measured on `fib` against the binaries before and
   after it: 290.8 → 252.7 ms (−13%), with steps 1–3 alone at 287.6 → 290.8 (noise).
5. **`call_native` reads `profile_on` once** and returns straight from `run_native` when it is off —
   it was read twice per builtin call (`profile_began`, `profile_native`), each a thread-local.
   `mapset` 151.3 → 142.7 ms on its own.

Control: a detached build of dev `b95fbcf`; branch `mapset-sorting`. Both `sysl 0.0.129`, thin LTO.

## The numbers

Alternating best-of-9 on `bench/timeit.pl`, control and branch back to back, lowest of each. The box
was not idle (60–80%: a long-running VM process at ~100% of one core and other agents' builds), which
is what the alternating method is for.

| program | dev `b95fbcf` | `mapset-sorting` | change |
|---|---|---|---|
| arith | 172.121 | 152.315 | −11.5% |
| reals | 286.983 | 262.329 | −8.6% |
| globals | 217.388 | 178.960 | **−17.7%** |
| funcs | 152.145 | 129.561 | **−14.8%** |
| fib | 302.360 | 258.804 | **−14.4%** |
| calls | 230.103 | 215.590 | −6.3% |
| methods | 322.826 | 289.174 | −10.4% |
| closures | 135.206 | 121.754 | −9.9% |
| nested | 275.849 | 261.227 | −5.3% |
| loops | 166.209 | 156.597 | −5.8% |
| options | 263.733 | 233.321 | −11.5% |
| fields | 177.144 | 156.484 | −11.7% |
| alloc | 269.193 | 251.540 | −6.6% |
| arrays | 240.460 | 219.596 | −8.7% |
| **mapset** | 216.425 | 146.638 | **−32.2%** |
| dispatch | 346.987 | 307.080 | −11.5% |
| strings | 19.480 | 19.210 | −1.4% |
| strindex | 9.441 | 6.991 | −26.0% |
| strwalk | 7.708 | 7.553 | −2.0% |
| **sorting** | 543.454 | 132.425 | **−75.6%** |
| csv | 210.338 | 200.556 | −4.7% |
| branches | 320.667 | 256.767 | **−19.9%** |
| **geometric mean** | | | **−16.8%** |

Against the yardsticks, `bench/run.sh` (best of 5) on each binary:

| program | dev | branch | dev/lua | branch/lua | branch/python |
|---|---|---|---|---|---|
| mapset | 203.8 | 146.3 | 11.3x | **7.2x** | 1.2x |
| sorting | 560.5 | 135.7 | 0.9x | **0.2x** | 0.3x |
| geomean | | | 1.7x | **1.4x** | 0.7x |

`sorting` is now 4.7x faster than Lua's `table.sort` on the same work (Lua's sorts with a Lua-level
`<` through its VM; slate's is compiled sysl with nothing slate-level in the loop).

Sub-steps on `mapset` (same method): control 203.4 → steps 1–3 168.0 → + step 4 146.9 → + step 5
142.7 ms. On `sorting`: 541.8 → 130.9 (step 1), unchanged after.

## The witness

`bench/check.sh ./slate`: all four runtimes' answers unchanged. The branch's profile of `sorting` is
one symbol, `sysl.slices$intro_sort.long` at 100%; `mapset`'s is `run_frames` 39.4%, `find_entry`
16.3%, `standing_native` 7.9%, `obj_put` 5.9%, with `keepable_on`, `hash_at`, `same_in`,
`same_plain`, `Args.at`, `profile_native` gone from the top and `_tlv_get_addr` 5.8% → 2.3%.

Tests: `tests_int_fast_paths.sysl` (sort edges: empty, one, all equal, both ends of a `long`, a
hundred values none lost, a real / a `Big` / a NaN / a mixture taking the old road, `sort` vs
`sorted`, a frozen array refused, a comparator still asked; integer keys in an indexed map, `1.0`
finding `1`, a set of integers beside reals and big integers, a class key's own `==`/`hash` beside
an integer key) and `tests/lang/intsort.sl` on both back ends.

## What is left

- **`mapset` is still 7.2x Lua.** `find_entry` (16%) is one probe per call and does its job; what
  remains is the builtin call itself — `standing_native` → `call_native` → `run_native`'s switch →
  `do_map_set` — and `run_frames` (39%). The profile's row 6 (a builtin method cached at its site)
  is the next piece of that.
- **Other homogeneous sorts** (all reals without NaN, all strings) still take the merge; a real
  sort would have to keep `-0.0`/`0.0` and `1`/`1.0` in their order, so it is stability that
  decides, not the comparison.
