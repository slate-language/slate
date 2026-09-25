# 2026-09-24 — A TABLE'S READS ASK NOTHING ABOUT WHERE ITS ENTRIES ARE

[`inline-object`](2026-09-24-inline-object.md) put up to three of an object's entries in its own
cell and spilled the whole table to a `Buf` at the fourth. Construction got faster (`alloc` −7.9%,
`calls` −7.0%), but every read of a large table then asked whether the table had spilled, and the
spilled side was a `Buf.at` with a count check and a slice bounds check behind it. `mapset` +3.9%,
`methods` +3.5%, `options` +2.2% and `csv` +2.3% paid for it. This item takes that cost back without
giving up the construction rows.

## What changed

`ObjectObj` carries **`at: *Entry`**, pointing at the cell's `small[0]` or at the spill block, so
`entry_at`, `entry_set` and `entry_value_set` are each one unchecked index off `at` with no branch.
The `Buf` is gone from the cell. A spilled table lives in a **`malloc`ed block** of `FirstOverflow`
(6) entries, doubled with `realloc`, with **`spill_cap`** beside `at` saying how much room it has
(0 while the table is in its cell). Only three places change `at`, all of them in `entries.sysl`:

- `home` points it at the cell. It is called by a new object (`entries_fresh_on`), an emptied table
  (`entries_drop`) and a freed one (`entries_release`).
- the first spill points it at the block it took, either a kept one from `spare_entries` or a fresh
  `malloc`.
- a doubling points it at whatever `realloc` answered, which may be a new address.

A rehash compacts in place and moves nothing. An actor's copy is a new object filled through
`entry_push`, so it gets its own pointer. `Vm.spare_entries` is now `Buf[*Entry]`, and
`entries_spares_free` gives the blocks back where the list used to be dropped (`reset_heap` and
`dispose_vm`). `Entry` holds nothing counted, so raw storage is legal for it.

Control: dev `56f28f9` (with the inline layout) and `effd368` (before it), each in a detached
worktree. All three sides were built with `bench/pgo.sh`.

## The shape was measured, not chosen

Alternating best-of-9 (`bench/alternate.pl 9`), PGO against PGO, run in both orders against dev.
Each cell below gives the two orders:

| variant | `mapset` | `methods` | `options` | `fields` | `alloc` | `calls` |
|---|---:|---:|---:|---:|---:|---:|
| A: `at` beside the `Buf` (cell 248 bytes) | −7.3 / −6.6% | −1.6 / −2.0% | −5.3 / −3.2% | −2.7 / −2.9% | **+3.9 / +3.7%** | +0.7 / +0.8% |
| B: no pointer; the spilled read unchecked (`&stored.elems[0]`) | −4.1 / −3.3% | −1.8 / −1.8% | +0.7 / −0.1% | −0.1 / −0.1% | +1.3 / +0.7% | +2.5 / +2.4% |
| **C: `at` + a `malloc`ed block (cell 232 bytes, landed)** | **−5.8 / −5.8%** | **−2.9 / −2.7%** | **−4.5 / −2.2%** | **−2.8 / −2.3%** | **+0.5 / +0.4%** | **−0.3 / −0.3%** |

- **A** recovered the large-table rows. It gave back half of `alloc`'s gain because the cell grew
  by 8 bytes, across a 16-byte size class.
- **B** kept `alloc` roughly flat, but compared with the layout before `56f28f9` it left `options`
  at +3.6%, `csv` at +3.3% and `methods` at +1.7%. The spilled branch was not the only cost; the two
  bounds checks were part of it.
- **C** has the pointer at 16 bytes of header (`at`, `spill_cap`) where the `Buf` took 24, so the
  cell is **8 bytes smaller than dev's**. Reads carry no branch and no bounds check. Construction is
  unchanged.

## Timing (the landed build)

The three columns are the layout before `56f28f9` (`effd368`), dev (`56f28f9`) and this branch, each
from its own alternating run against the branch:

| program | before layout | dev | branch | vs before | vs dev |
|---|---:|---:|---:|---:|---:|
| mapset | 37.5 | 39.1 | 36.8 | **−1.8%** | **−5.8%** |
| methods | 156.1 | 161.6 | 156.9 | **+0.5%** | **−2.9%** |
| options | 150.7 | 153.0 | 146.9 | **−2.6%** | **−4.5%** |
| csv | 94.1 | 89.9 | 90.7 | **−3.7%** | +0.2% |
| fields | 85.7 | 88.0 | 85.3 | **−0.5%** | **−2.8%** |
| dispatch | 123.6 | 123.4 | 122.9 | −0.6% | −0.6% |
| alloc | 104.2 | 96.1 | 96.4 | **−7.5%** | +0.5% |
| calls | 100.7 | 93.7 | 93.2 | **−7.4%** | −0.3% |
| nested | 144.6 | 146.7 | 143.6 | −0.7% | −3.4% |
| fib | 137.8 | 135.9 | 137.5 | −0.2% | +1.1% |
| arith | 77.8 | 76.8 | 76.6 | −1.6% | −1.0% |
| **geometric mean** | | | | **−1.29%** | **−0.83%** (reverse order +0.20%) |

Each of the six rows the item named is back at or under its time before the layout. `methods` is
+0.5%, inside the 1% bar, and `mapset` is −1.8% below it. `calls` and `alloc` keep the whole of the
layout's gain. `fib` and `arith` touch no object and move within noise. `reals` and `loops` swung
±10% under variant A and are flat under C, which is PGO code layout and not this change.

`bench/run.sh -n 5 pgo/slate` on the rows that moved (ms, and slate's ratio to each yardstick):

| | slate | lua | node-jl | php | /lua | /node | /php |
|---|---:|---:|---:|---:|---:|---:|---:|
| mapset | 36.4 | 17.1 | 83.7 | 45.2 | 2.1x | 0.4x | 0.8x |
| methods | 155.8 | 141.3 | 164.7 | 121.7 | 1.1x | 0.9x | 1.3x |
| options | 146.9 | 86.3 | 109.1 | 139.2 | 1.7x | 1.3x | 1.1x |
| csv | 91.6 | 293.2 | 132.4 | 74.9 | 0.3x | 0.7x | 1.2x |
| fields | 85.6 | 63.9 | 81.8 | 86.7 | 1.3x | 1.0x | 1.0x |
| calls | 92.5 | 154.5 | 78.0 | 95.1 | 0.6x | 1.2x | 1.0x |
| alloc | 96.4 | 159.6 | 81.6 | 96.4 | 0.6x | 1.2x | 1.0x |

## Memory

The cell is 240 → **232 bytes**: an 88-byte header (`at`, `spill_cap`, `count`, the index, `live`,
the flags, the summary) and three 48-byte entries. `tests_cell_fields.sysl` pins it. Peak RSS
(`/usr/bin/time -l`), dev → branch: `alloc` 5.54 → 5.44 MB, `methods` 5.49 → 5.34 MB.

## Tests

- `tests_cell_fields.sysl`:
  - the cell size;
  - the pointer is where the entries are after every field from 1 to 25, with every field read back
    at each step, across 6 → 12 → 24 → 48;
  - the pointer is right after a rehash;
  - a table taking a kept block from a sweep points at it;
  - an emptied table points back at its cell;
  - an actor's copy points at its own storage and never at the original's;
  - **a table read while it grows, in a 1 MB heap that collects while it runs** (the sum over every
    read is exact).
- The negative control: growing the block without re-pointing `at` fails both new growth tests and
  two existing ones (`A_MAP_AND_A_SET_THAT_GROW_PAST_THEIR_FIRST_SIZE_MID_LOOP_KEEP_EVERY_KEY` and an
  actor's heap test).
- `tests_call_path.sysl`: a kept table is a bare block now, so the test asserts that it is one and
  that no block is kept twice.
- `tests/lang/cellfields.sl`, both back ends:
  - a table read at every size from 1 to 30;
  - `without` shrinking an eight-field object one field at a time, back into its cell.
