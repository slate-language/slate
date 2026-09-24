# 2026-09-24 — A `Value` IS SIXTEEN BYTES: A TAG AND ONE WORD

The shortlist's structural row 10, "a narrower `Value`, or NaN-boxing". `Value` was a 40-byte sysl
enum; every push, pop, slot read, array element and table entry moved five words of it. It is 16 now,
the width of Lua's `TValue`, and the enum is still an enum — every `match` in the tree reads the same
variants it did.

Control `3a6e23c` (dev); branch `narrow-value`.

## Why it was 40, and what it took to make it 16

A sysl enum is a tag and the widest variant's payload, so the width was decided by one variant:

| variant | payload before | what it is now |
|---|---|---|
| `RangeVal(lo, hi, inclusive, has_lo, has_hi, step)` | **32 B** — three `long`s, three flags | `RangeVal(p: *RangeObj)`, a cell |
| `DateTimeVal(day: int, us: long)` | 16 B | `DateTimeVal(p: *DateTimeObj)`, a cell |
| `ZonedVal(us: long, zone: usize)` | 16 B | `ZonedVal(p: *ZonedObj)`, a cell |
| `Socket`, `ChildVal`, `Gen`, `ActorVal` `(id: usize, gen: usize)` | 16 B | `(id: u32, gen: u32)` — two halves of one word |
| `MessageVal(id, gen, name: usize)` | 24 B | `(gen: u32, id: u16, name: u16)` — one word |

- **The three cells are `boxed.sysl`**: one `gc.Kind` whose tracer marks nothing and which has no
  finalizer, one reserve (`Vm.spare_cell`, taken at the largest size), and one constructor each
  (`range_value`, `date_time_value`, `zoned_value`). A cell is written where it is made and never
  again, so equality and hashing read what it holds; `range_reach` is now the one reading of "the
  last number a range covers" that `same` and `hash_plain` both call. `mark_value` marks the cell.
- **A day and a time of day are 69 bits**, and an instant is a whole word before its zone, so neither
  civil nor zoned readings could be packed without narrowing the calendar's range — they became cells
  rather than giving up years. A range could have been packed only for small ends and a step of one,
  which is two representations of one kind; it became a cell too. It is made once per `for` over it,
  not once per turn.
- **The packed pairs are 32 bits a half.** A slot table of four billion sockets is not one anything
  runs, and a generation wrapping would need four billion claims of one slot while a value from the
  first was still held. A message's actor slot is under `MaxActors` (1,024) and its handler name an
  index into a per-VM table: `message_value` in `actor.sysl` is now the only maker and refuses the
  65,537th distinct name rather than wrapping onto a name somebody else interned.
- **NaN-boxing into eight bytes was rejected.** slate's integers are full 64-bit with promotion to
  `Big` past that, and its reals are full doubles; an eight-byte box has room for one of those and
  not both, so either every integer past 48 bits becomes a heap cell (changing `arith`'s costs) or
  every real does. It would also need a `u64`/`f64` reinterpretation and pointer tagging, which sysl
  has no safe spelling for — and it would end every `match` over the union. Sixteen bytes keep the
  enum and every site that reads it.
- **`Step` does NOT shrink.** It is `Result[Value, Signal]` and its widest variant is `Signal.Fail`
  (a span, a sentence and two 32-bit numbers), so it stays 64 bytes; `Ok(v)` and `Ret(v)` are
  narrower inside it. `tests_carried.sysl`'s pin is unchanged; narrowing `Fail` is a separate item.

## Sites

**About 120 constructor and match lines across 24 source files**, every one found by the compiler —
most of them `calendar.sysl` and `time.sysl`'s civil and zoned readings, the rest the ranges and the
packed pairs' conversions at each place a slot or a generation is handed to a table that is `usize`.
No `Op` changed, `Ins` is untouched, and `run_frames.sysl` changed one arm in place (still 999 lines).

**One defect found and fixed on the way, in the JavaScript back end's actor wire**: a zone arriving in
a message was decoded as `zone(name)`'s *result* rather than the zone, so `ask(e.back, z)` answered
`{ ok: true, value: … }` and a zoned reading sent back came with an `undefined` zone name and faulted.
`zoneArrived` in `js_rt_actor.sysl` decodes the zone itself; `tests/lang/actors.sl` now sends a zone, a
zoned reading, a civil reading, a stepped range, an open range and a message through an echo actor on
both back ends.

## The table

PGO builds both sides (`bench/pgo.sh`), alternating best-of-9, `perl bench/alternate.pl 9 <control>
<branch>`, milliseconds, 86.4% idle and no JVM:

| program | dev `3a6e23c` | branch | change |
|---|---|---|---|
| alloc | 154.154 | 139.053 | −9.8% |
| arith | 101.753 | 83.169 | −18.3% |
| arrays | 159.565 | 133.506 | −16.3% |
| branches | 188.791 | 167.096 | −11.5% |
| calls | 144.943 | 131.863 | −9.0% |
| closures | 88.785 | 79.767 | −10.2% |
| csv | 148.846 | 139.178 | −6.5% |
| dispatch | 168.370 | 149.086 | −11.5% |
| fib | 171.801 | 162.428 | −5.5% |
| fields | 115.655 | 99.127 | −14.3% |
| funcs | 95.166 | 79.442 | −16.5% |
| globals | 111.814 | 97.546 | −12.8% |
| loops | 117.810 | 99.038 | −15.9% |
| mapset | 96.114 | 86.189 | −10.3% |
| methods | 212.088 | 188.925 | −10.9% |
| nested | 185.243 | 160.891 | −13.1% |
| options | 187.786 | 179.134 | −4.6% |
| reals | 170.820 | 140.954 | −17.5% |
| sorting | 135.694 | 137.268 | +1.2% |
| startup | 4.685 | 4.519 | −3.5% |
| strindex | 5.308 | 5.165 | −2.7% |
| strings | 12.547 | 12.442 | −0.8% |
| strwalk | 6.154 | 6.164 | +0.2% |
| **geometric mean** | | | **−9.75%** |

**The other ordering agrees**: branch first, control second, the control reads +10.89% — the same
−9.8% seen from the other side, program by program (`arith` +22.3%, `reals` +21.3%, `loops` +20.3%).
`sorting` and the string programs do not move, their work being inside builtins that move bytes
rather than `Value`s.

Against Lua (best of 5, same session):

| program | dev/lua | branch/lua |
|---|---|---|
| fields | 1.99x | **1.71x** |
| methods | 1.54x | **1.37x** |
| arith | 2.18x | **1.78x** |
| reals | 2.98x | **2.46x** |
| fib | 2.18x | 2.06x |

## The witness

`sizeof(Value)` 40 → **16**, pinned by `A_VALUE_IS_A_TAG_AND_ONE_WORD` in `tests_narrow_value.sysl`;
`sizeof(Step)` 64 → 64. Instruction counts are identical under `--features profile` (`fields`
45,000,026, `methods` 75,000,051, `arith` 70,000,023, `reals` 70,000,025, `fib` 96,949,078, `loops`
64,103,036, every kind's count equal), so the whole of the change is the width under every
instruction. `bench/check.sh` answers unchanged for all four implementations.

## The tests

`tests_narrow_value.sysl`: the width; a socket, a child and a generator at the top of their 32-bit
halves, compared and hashed, and a socket and a generator with the same halves kept apart; a message's
three parts; the handler-name ceiling refused rather than wrapped; ranges compared, hashed, printed,
sliced and walked; twenty thousand range cells held across collections, with the collection count as
the control; a big integer and NaN/±0/±∞ unchanged; civil and zoned readings compared, hashed and
moved. `tests/lang/actors.sl` carries the wire round trips on both back ends.
