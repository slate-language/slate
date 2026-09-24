# 2026-09-24 — AN OBJECT LITERAL OF DISTINCT KEYS WRITES ITS FRESH TABLE WITHOUT A LOOKUP

`calls`, `alloc` and `arrays` were the three rows where `node --jitless` and PHP beat slate, while
`fib` and `funcs` — pure calls — did not. The item arrived with a hypothesis: a slate object is an
`ObjectObj` plus a separate entry table, so every class instance is two or more allocations, and
node lays declared fields inline in one. **The profile said otherwise, and this write-up follows the
profile.**

## What the profile ranked

`calls.sl` on the 0.1.7-shaped PGO build of dev `defb8e7`, 110 ms. Three instruments:

- **Variants of the loop** (best of 5, same binary): `bump` answering `self` through a plain call —
  same two calls, same field read, no construction — runs in **56.6 ms**; answering a literal
  through a plain function instead of the class's `new`, **107.6 ms**. So **the construction and its
  reclamation are ~54 ms of the 110**, ~27 ns an object, and calling `Counter(…)` rather than an
  ordinary function costs nothing measurable.
- **`SLATE_PROFILE=1`**: 986 collections, 12.7 ms of collector, 1,997,975 allocator steps — one
  allocation per instance. **The "two allocations per object" of the hypothesis was already gone**:
  `call-path` (2026-09-23) made a sweep keep a small object's emptied entry table for the next
  object, so a steady construction loop asks `malloc` for nothing.
- **A sampled profile of a plain build with the construction helpers held out of line** (`sample`,
  4 s, 3,416 samples, 100M turns): of the ~39% the construction and collection cost, the largest
  single part was **the key lookups**: `obj_put_keyed` 214, `literal_on` 100, `Buf.at<string>` 49
  and `Buf.at<u32>` 32 — **~12% of wall asking, twice per object, whether a key the object has never
  held is already there**, and copying each key's text out of the unit (a retain and a release) to
  ask it. Then `new_object_on` 186, `compose_object` 182, `gc.take` 165, `entry_push_on` 125,
  `finalize_object` 123, `rebuild_free` 66, `gc.collect` 60, `_tlv_get_addr` 29.

**Inline small-object storage (candidate (a)) was not taken.** What it would remove is the spare
table's pop and push and one `Buf` push per field — `new_object_on`/`finalize_object`/
`entry_push_on`'s share, well under the lookup's — for a layout change across ~180 readers of
`.entries` in some 30 files, and a larger cell for every object. The profile does not rank it first.

## What changed

1. **`compose_object` holds the VM the instruction loop already has** (`new_object_on`,
   `keepable_on`, `root_values` directly, and `entry_push_on`/`obj_put_keyed` taking it), so a
   literal asks the thread-local nothing where it asked eight times. Measured alone: `alloc` −3.8%,
   `calls` −0.3% — the TLV was not the cost.
2. **A literal of up to `SmallTable` (8) distinct keys writes its fresh table without a lookup**
   (`obj_push_fresh` in `table.sysl`). A fresh object's table is empty and in the small case, and
   `intern_str` gives equal texts one index, so `distinct_keys` comparing the run's indices is
   comparing the keys; nothing can be found, nothing can grow, and there is no index to place in.
   What is left per key is the push, the summary bit, `live`, and the `val`-mark question — read
   through the key's cell, so it retains nothing. A literal naming a key twice, or longer than eight,
   takes `obj_put_keyed` as before. Every generated constructor is such a literal.
3. **`compose_object` is `@noinline`.** Inlined into `run_frames` it moved call-free programs by PGO
   layout: `loops` +9.2%/+6.6% and `reals` +4.6%/+3.7% on two runs. Out of line, `loops` +2.4% and
   `reals` +0.9%, and `calls` gained a further point.

Control: dev `defb8e7`, built in a detached worktree; both sides `bench/pgo.sh`.

## The witness

No emitted code changed, so the instruction counts are identical: `calls` 34,000,035 with
`MakeObject` 2,000,003 on both sides. The witness is the sample above and the three tests below that
pin the fresh write to the general one.

## Timing

Alternating best-of-9, `bench/alternate.pl 9`, PGO against PGO, box 82–90% idle:

| program | dev | branch | change |
|---|---:|---:|---:|
| alloc | 117.4 | 110.6 | **−5.8%** |
| calls | 112.0 | 104.0 | **−7.2%** |
| arrays | 114.2 | 114.7 | +0.5% |
| methods | 159.1 | 156.7 | −1.5% |
| fields | 85.9 | 86.0 | +0.1% |
| csv | 101.5 | 101.4 | −0.2% |
| fib | 137.4 | 136.9 | −0.4% |
| arith | 78.8 | 79.0 | +0.3% |
| globals | 48.6 | 48.2 | −0.8% |
| loops | 86.5 | 88.6 | +2.4% |
| sorting | 125.9 | 131.6 | +4.5% |
| **geometric mean** | | | **−0.33%** |

`sorting` read +4.2% again on a reversed-order recheck and constructs no object; `loops` holds none
either. Both are PGO layout — the training set changes with the code, and `run_frames` moves.
`arrays`, `methods` and `fields` construct nothing in their loops, so this change could not reach
them: `arrays`' cost against PHP is elsewhere.

`bench/run.sh -n 5 pgo/slate calls alloc arrays` on the branch:

| | slate | node-jl | php | ruby | lua | /node | /php |
|---|---:|---:|---:|---:|---:|---:|---:|
| calls | 103.0 | 77.2 | 95.1 | 107.1 | 150.7 | 1.3x (was 1.4x) | 1.1x (was 1.2x) |
| alloc | 109.6 | 81.2 | 95.0 | 156.4 | 158.6 | 1.4x (was 1.5x) | 1.2x (was 1.3x) |
| arrays | 114.8 | 160.3 | 78.1 | 190.0 | 91.9 | 0.7x | 1.5x |

**Peak RSS** (`/usr/bin/time -l`): `alloc` 6.44 → 6.49 MB, `calls` 6.60 → 6.64 MB — the layout of
an object is unchanged, so no object grew.

## Tests

- `tests_object_keys.sysl`: the fresh write builds the table the plain one does for every size 1–8
  (entries, hashes, summary, `live`, index) and nine is refused it; it notes a `val` mark, and not a
  key merely starting with `(`; a literal naming a key twice still takes the general write; and a
  quarter of a million literals on a one-megabyte heap, a fiftieth of them kept, keep every field
  while the collector hands their tables round.
- `tests/lang/freshkeys.sl`, both back ends: eight keys and nine keep their order and answer every
  lookup; equality across the line in any order; `with` carrying a small literal to nine and
  `without` bringing it back; a JSON round trip; a class built by the fresh write still refusing a
  write to its `val`.

## What is left

The rest of the construction is the allocator (`gc.take`), the spare table's pop and push, the
sweep and the finalizer — about as much again as the lookup was, spread over five functions. The
inline layout is the lever for the table half of that and would have to beat it by more than the
~180 readers it touches; a collector that sweeps a dead object without a finalizer call is the lever
for the other half, and is `sh.sysl.gc`'s.
