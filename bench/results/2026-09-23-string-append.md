# 2026-09-23 — A STRING BUILT BY APPENDING SHARES ONE GROWING BUFFER: `strings` 740 → 33 ms

`out = out + piece` in a loop copied everything `out` held on every turn, so building a string of n
characters one piece at a time was n²/2 bytes of copying — `strings` was **44x QuickJS** and slower
than CPython, both of which append in place. This is that trick for a heap whose cells carry no
reference count. Control `b1dc161` (dev); branch `string-append`.

## What was built

`str_room.sysl`, and one hook each in `arith.sysl` (a `+` of two strings goes to `joined`),
`obj.sysl` (a `StrObj` names its room and marks it) and `vm_state.sysl` (`pending_room`, rooting a
room across the allocation of the cell that will name it).

- **A ROOM is a heap cell holding a buffer with spare capacity and a `used` mark.** Every string made
  by appending into it is a sysl `string` VIEWING `store[0..<its length]` — `sysl.text.str_view`,
  new in sysl **0.0.129**, which shares the slice's owner instead of copying it. That compiler gap
  was what blocked this: the first cut used `from_utf8_unchecked`, which copies, and measured 758 ms
  with the whole mechanism in place.
- **The TIP is the string whose length is `used`.** `x + y` where `x` is the tip and `y` fits writes
  `y` into the spare bytes, raises `used`, and makes a new cell viewing the longer prefix. **No byte
  any string can see is ever written**, so `val a = s; s += t` leaves `a` reading what it read, and
  a later `a + u` finds `used` past its end and copies into a room of its own.
- **A room is made only where it can pay for itself**: the result at least 64 bytes and the left side
  at least as long as the right. It grows by half as much again, so a run of appends copies each byte
  a bounded number of times.
- **The room is charged, once, at its capacity**; its strings charge nothing (`str_payload`). The
  mark-phase recount therefore stays exact, and a thousand prefixes of one buffer are one buffer.
- **Only a proven-unique header could be reused, and slate cannot prove it** — the heap is traced,
  so nothing says the tip's cell is held by the one slot being assigned. Every append makes a new
  cell; that is the remaining allocation below.

### And one follow-up the sample named: `string(n)` of an integer

The sample of the branch (below) put a third of what was left in `string(i % 10)`. `printed_value` in
`render.sysl` answers a string as itself and an integer's digits with their count known (one byte
each) — no printer walk, no held root, no path buffer, no character scan. Everything else takes the
walk it always took.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `b1dc161` against the branch, box 88% idle,
no JVM.

| program | control | branch | change |
|---|---|---|---|
| **strings** | 739.8 | **32.6** | **−95.6%** |
| strwalk | 8.74 | 6.87 | −21.4% |
| strindex | 7.46 | 6.45 | −13.5% |
| startup | 4.80 | 4.44 | −7.5% |
| branches | 323.4 | 306.8 | −5.1% |
| alloc | 340.6 | 329.0 | −3.4% |
| globals | 698.9 | 681.2 | −2.5% |
| options, funcs | | | −2.2% |
| every other program | | | −1.9% to +1.1% |
| **geometric mean, all twenty-three** | | | **−15.39%** |

The geometric mean is `strings` alone, near enough: one program of twenty-three going 22.7x faster
is 13.6% of the mean by itself. `strwalk` and `strindex` build their subject strings by appending.

**The `string()` fast path alone**, the room binary against the full branch, same method:
`strings` 34.1 → 32.1 ms (**−5.9%**), geometric mean −0.77%, nothing else outside ±2%.

| | strings (ms) | vs QuickJS 16.8 | vs CPython 629 |
|---|---|---|---|
| dev `b1dc161` | 739.8 | 44.0x | 1.18x |
| rooms, copying view (`from_utf8_unchecked`) | 758 | 45x | 1.21x |
| rooms, `str_view` | 34.1 | 2.03x | 0.054x |
| **branch** (rooms + `string()` fast path) | **32.6** | **1.94x** | **0.052x** |

`SLATE_PROFILE`: 221 collections, heap high water 891 KB, 597,306 allocator steps on the branch.

## What the remaining 33 ms is

`sample` of the branch over a 3,000,000-turn copy of `strings.sl` (447 main-thread samples, before
the `string()` fast path; LTO flattens most of it into `run_frames`):

| share | what |
|---|---|
| ~34% | **`string(i % 10)`**: `snprintf` through `push_int` (~12%), the printer's builder and `finish` (~8%), the global-name `Map.find` and call path (~6%), the character scan (`new_str_scanned`, 3%). The fast path took the scan and the walk; `snprintf` and the name lookup remain |
| ~21% | the collector: `gc.take` zeroing and free-list work, `collect`, `rebuild_free` — two cells a turn (the join's and the digit's), 221 collections |
| ~15% | `malloc`/`free` of each digit string's storage and the `arc.reap` that frees it |
| ~11% | instruction dispatch |
| ~6% | **the append itself** — `arith` → `joined` → `in_room`, a `memmove` of one or two bytes |

So appending is no longer the cost of this benchmark. **The next steps, in order of size:** an
integer rendered without `snprintf` (a sysl `push_int` finding, not slate's); `string` resolved at
compile time rather than looked up by name each turn (shortlist item 8); and a one-character string
of an ASCII digit or letter interned, so `string(i % 10)` allocates nothing. The per-append cell is
the one thing that stays: reusing the tip's header needs the uniqueness a traced heap does not have.

## Tests

- `tests_str_room.sysl` (seven): the tip appends in place and an alias is unchanged; a non-tip
  append copies and leaves the extended string's bytes alone; short joins and prepends get no room;
  a string joined to itself, and an empty append making a second tip; 20,000 appends move the room a
  logarithmic number of times with the text exact; a room is charged once at capacity and two
  collections recount it exactly, dropping it gives all of it back; a room held only by its shorter
  prefixes survives `collect_now` with every prefix intact; a program keeping prefixes in a
  one-megabyte heap reads every one back.
- `tests/lang/append.sl` (seven), both back ends: aliasing, non-tip copies, kept prefixes, self-join,
  the empty append, characters across pieces, and `string()` of an integer (including one past 64
  bits) and of a string.
