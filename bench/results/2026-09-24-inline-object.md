# 2026-09-24 — A SMALL OBJECT KEEPS ITS FIELDS IN ITS OWN CELL

[`object-layout`](2026-09-24-object-layout.md) left the table half of a construction standing: after
it, an object is one allocation (a sweep hands the emptied entry table to the next object through
`Vm.spare_entries`), but the entries are still a separate `Buf[Entry]` the `ObjectObj` owns — a
second block to read through on every field access, a spare-table pop and a `Buf` push on every
construction, and a second block for the finalizer. This item moved a small object's entries into the
cell, in two commits.

## What changed

1. **The accessor** (no layout, no behaviour): `entries.sysl` is now the only file that names where
   an object's entries live. The ~180 readers and writers in 30 files — the compact dict, the tracer,
   `weaken`, the printer, the matcher, `keys`/`values`/`entries`, the actor copy, JSON, `with`, the
   site caches and the subsystems that walk an options object — ask `entry_count`, `entry_at`,
   `entry_set` and `entry_value_set`. The storage field was renamed so the compiler found every site.
   Gated green on its own (3198/0).
2. **The layout**: an `ObjectObj` carries `small: [InlineEntries]Entry` and a `count`. A table of up
   to **three** entries lives in the cell; the entry that does not fit **spills the whole table** into
   `stored` (sized `2 × InlineEntries` = 6, then doubling), and from then on every position is there.
   A rehash compacts in place. A sweep keeps an emptied spill table (`FirstOverflow`) for the next
   object that outgrows its cell, bounded as before. An `Entry` holds no counted member (a hash, two
   `Value`s, a flag), so it is legal in zeroed collected memory.

Control: dev `effd368`, built in a detached worktree; both sides `bench/pgo.sh`.

## The shape was measured, not chosen

Alternating best-of-9, `bench/alternate.pl 9`, PGO against PGO, one full run per variant:

| variant | `alloc` | `calls` | `mapset` | `methods` | geomean |
|---|---:|---:|---:|---:|---:|
| first 4 inline, the rest in a `Buf` | −6.4% | −3.4% | +3.7% | +3.5% | +0.06% |
| first 8 inline, the rest in a `Buf` | +3.7% | +2.8% | +3.4% | +2.6% | −0.53% |
| first 3 inline, the rest in a `Buf` | −7.9% | −7.2% | +3.7% | +2.9% | −1.19% |
| up to 3 inline, then the whole table spills | −7.4% | −5.6% | +5.0% | +4.0% | −0.03% |
| the same, cell fields reordered, value writes in place (**landed**) | **−7.9%** | **−7.0%** | +3.9% | +3.5% | **−0.65%** |

- **Eight is too many**: the cell is 480 bytes and zeroing it costs more than the table it saves.
  Three is a class instance's `proto` and two fields (`calls`' `Counter`, `methods`' `Vec`) and a
  literal pair or triple (`alloc`), and it is the smallest cell that holds them.
- **Keeping the first N inline** asked `i < N` of a position the hash had just chosen, which a map
  read at random mispredicts. **Spilling the whole table** asks whether the object has spilled — the
  same answer for every read of one object. It did not remove the `mapset`/`methods` cost, which is
  the check itself on every large-table read: **those two rows pay +3.5–4% for the layout** and the
  construction rows take −7–8%.

## Timing (the landed build)

| program | dev | branch | change |
|---|---:|---:|---:|
| alloc | 107.6 | 99.1 | **−7.9%** |
| calls | 102.6 | 95.4 | **−7.0%** |
| loops | 101.8 | 96.1 | −5.6% (PGO layout; no object) |
| nested | 152.4 | 147.0 | −3.5% |
| dispatch | 126.5 | 124.7 | −1.4% |
| fib | 139.1 | 137.1 | −1.4% |
| arith | 77.9 | 78.7 | +1.0% |
| options | 154.2 | 157.5 | +2.2% |
| csv | 92.7 | 94.9 | +2.3% |
| fields | 87.8 | 89.8 | +2.4% |
| methods | 158.7 | 164.2 | +3.5% |
| mapset | 39.3 | 40.9 | +3.9% |
| **geometric mean** | | | **−0.65%** |

`bench/run.sh -n 5 pgo/slate calls alloc methods fields` on the branch:

| | slate | node-jl | php | /node | /php |
|---|---:|---:|---:|---:|---:|
| calls | 95.2 | 82.3 | 99.4 | 1.2x (was 1.3x) | **1.0x** (was 1.1x) |
| alloc | 99.3 | 84.4 | 99.3 | 1.2x (was 1.4x) | **1.0x** (was 1.2x) |
| methods | 168.6 | 175.3 | 128.9 | 1.0x | 1.3x |
| fields | 90.8 | 87.3 | 92.6 | 1.0x | 1.0x |

No emitted code changed, so instruction counts are identical.

## Memory

The cell is 88 → **240 bytes** (`count` and three 48-byte entries; `tests_cell_fields.sysl` pins it).
Peak RSS (`/usr/bin/time -l`), dev → branch:

| program | dev | branch |
|---|---:|---:|
| `alloc` | 6.14 MB | 5.30 MB |
| `calls` | 6.28 MB | 5.39 MB |
| `methods` | 5.14 MB | 5.20 MB |
| `csv` | 15.33 MB | 15.05 MB |
| 100,000 live objects of 2 fields | 87.5 MB | **40.1 MB** |
| 100,000 live objects of 5 fields | 87.4 MB | 93.8 MB (+7%) |
| 100,000 live objects of 12 fields | 167.9 MB | 167.3 MB |

An object of up to three fields no longer owns a 384-byte table; one of four to six pays its cell plus
a table of six (528 bytes against 472); a large one is unchanged.

## Tests

- `tests_cell_fields.sysl`: the cell size; a small object holds no payload and the fourth field moves
  the table out in order; a rehash compacts tombstones on both sides; a tombstone keeps its cell
  position; a weak map drops by position on both sides of the line; the recounted payload is exact
  with small and spilled objects alive; an actor's copy of 0, 1, 3, 4 and 9 fields comes back in order
  on the same side of the line.
- `tests_call_path.sysl`: the spare-table tests now make objects that outgrow the cell, and an object
  that fits its cell takes no kept table.
- `tests/lang/cellfields.sl`, both back ends: every size 0–7 keeps its order and lookups; writes on
  both sides; `with`/`without` across the line; remove and re-add; equality and hashing in a `Set` and
  a `Map`; class instances of two and four fields; data values of two and four fields, and the refusal
  sentence for a field neither declared; a weak map outgrowing its cell; JSON round trips.

## What is left

The `mapset`/`methods` cost is the spilled check on every large-table read. A table whose storage
pointer is kept beside the cell (pointing at `small` or at the spilled `Buf`) would read with no
branch at all — at the price of a self-pointer every push and rehash must keep right.
