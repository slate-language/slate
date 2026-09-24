# 2026-09-23 — A LITERAL IS ONE CELL, A CLASS'S `new` IS REMEMBERED, AND A BUILTIN'S NAME IS READ FROM A CELL

The two worst programs against CPython after `call-path` were `csv` (2.0x) and `calls` (1.6x), and its
*"What is left"* named three costs on them. All three are gone, with a fourth the first one exposed:

1. **A string literal was a fresh `StrObj` on every execution** — the sixth profile's row 1. `PushStr`
   called `str_counted` each time it ran, so a constructor's object literal `{ proto: Counter, n: n }`
   built two string cells per object for its two keys, and `line.split(",")` one per line for the
   comma: text that cannot change, allocated, charged, traced and swept again on every turn. Now the
   first execution makes the cell and keeps it in `Vm.literals` (a collector root, emptied by
   `reset_vm` with the unit whose numbering it is in), and every later one pushes it
   (`literal.sysl`). Sharing is sound because nothing a program does can change a string cell and
   nothing can tell two cells of equal text apart.
2. **The kept-table bound was sized for three allocations per object.** With the key cells gone a
   collection comes a third as often, so three times as many objects die in each sweep, and the
   1,024 tables `call-path` keeps ran out: `Buf.grow<Entry>` and malloc/free came back into `calls`'
   profile at 5%. `SpareEntries` is 4,096 now (two megabytes, in `collector.sysl`).
3. **`Counter(3)` asked the class for `new` by spelling on every construction** — `hook_of` hashing
   `"new"` and searching the table. `CallFn`'s eight bytes are full, so the memory is one position on
   the unit, `Unit.new_at`, where `new` stood the last time any constructor call looked; the entry
   standing there must be live, filed under `new_hash` and keyed `new` before it is believed, which is
   `site_cache.sysl`'s bargain — a `new` written over answers the new closure, one moved or removed
   misses and searches, and classes declared alike share the position (`class_call.sysl`). **It is
   `@noinline`**: inlined into `placed_call` it cost `fib`, which constructs nothing, +4–6%.
4. **A builtin's name was a `LoadName` on every call** — `number` and `string` in `csv`, 8.9% of its
   executions. A spelling the file reads and nothing in it binds is now claimed at its first read as a
   `Free` entry of `defs.sysl`'s table and read with **`LoadFree(cell, name)`**: an empty cell takes
   the lookup and keeps what it found, since the walk can only end in the builtin scope, whose
   bindings no program can write. The put-back is the one module definitions already have: a binding
   anywhere in the file shuts the entry and `settle_module_defs` writes `LoadName` back — and so that a
   binding compiled BEFORE the first read can say no too, `shadowed_name` now records a spelling it
   has no entry for as a shut `Bound` one.

And one small thing the profile showed once the allocation was gone: `val_key`, asked of every new
key of every object, called `starts_with("(val)")`; it asks the first byte first now.

Control `e9effa4` (dev, with `split-obj`, thin LTO); branch `construction`, landed as `f09df54` plus
the `@noinline` follow-up.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), both LTO builds, box 92.7% idle with `pgrep -x java`
empty.

| program | control ms | branch ms | change |
|---|---|---|---|
| **alloc** | 313.3 | 226.9 | **−27.6%** |
| **calls** | 271.6 | 202.8 | **−25.3%** |
| **csv** | 209.6 | 178.8 | **−14.7%** |
| strings | 30.6 | 26.7 | −13.0% |
| strindex | 6.29 | 5.83 | −7.3% |
| dispatch | 266.0 | 259.4 | −2.5% |
| methods | 282.7 | 276.7 | −2.1% |
| loops | 135.5 | 138.5 | +2.3% |
| globals | 164.4 | 167.8 | +2.0% |
| every other program | | | within ±1.3% |
| **geometric mean, all twenty-three** | | | **−4.37%** |

`loops` and `globals` execute the same instructions on both sides (`loops` reads its one builtin
1,001 times) and are this instrument's floor on a shared box.

`bench/run.sh -n 5` on the branch: **1.6x Lua / 1.2x node --jitless / 0.8x CPython / 1.0x qjs**;
against CPython `calls` **1.4x**, `alloc` **1.0x**, `csv` **2.1x** — `csv` is the collector now
(`gc.collect` alone is 16% of it) sweeping the pieces `split` makes, which only a small-string form of
`StrObj` changes.

`SLATE_PROFILE`, control against branch — instruction counts are identical, what moved is what they
allocate:

| | control | branch |
|---|---|---|
| `calls` allocator steps | 5,997,568 | **1,998,745** |
| `calls` collections | 2,466 | **1,591** |
| `alloc` allocator steps | 8,997,559 | **2,998,742** |
| `alloc` collections | 3,690 | **2,382** |
| `csv` allocator steps | 3,722,107 | **3,083,188** |
| `csv` `LoadName` | 1,280,001 | **0** (`LoadFree` 1,280,001) |

## The witness: `sample`

Four seconds a side, top-of-stack counts:

| | control | branch |
|---|---|---|
| `calls`: `obj_get_name` (the `new` search) | 85 | **0** |
| `calls`: `string.starts_with` (`val_key`) | 51 | **0** |
| `calls`: `gc.collect` + `gc.take` + `rebuild_free` | 544 | **230** |
| `calls`: `memset` | 140 | **7** |
| `csv`: `Map.find<string, Value>` + `lookup` (the name walk) | 108 | **0** |
| `csv`: `trace_str` + `finalize_str` | 49 | 22 |

## The tests

- **`tests_construction.sysl`** — fifteen: a literal that ran is one cell carrying its count; one that
  never ran has none; its cell outlives a collection over 3,000 dropped objects; `reset_vm` empties the
  table; growing on a literal leaves it as it was. `constructor_of` finds `new` wherever it stands and
  moves the remembered position; a `new` WRITTEN OVER answers the new value; a `new` that is not
  callable is no constructor, through the remembered position too; a `new` REMOVED is found through the
  proto. A builtin nothing binds compiles to `LoadFree` and no `LoadName`; one whose spelling a local
  binds AFTER the read, and one a parameter binds BEFORE it, compile to `LoadName` and answer the
  binding; a spelling the file writes keeps the lookup; an unbound name is refused in the sentence it
  always was, twice.
- **`tests/lang/construction.sl`** — eleven, both back ends: construction in a loop, two classes
  alternating, a `new` written over, a `new` at another position; a builtin in a loop, spellings bound
  by a local and by a parameter, a builtin taken as a value; a literal in a loop, built on, surviving
  20,000 objects of garbage, and indexed from two places.
- **`tests_call_path.sysl`**'s bound test drops three times `SpareEntries` rather than 3,000.

## What is left

An object literal with literal keys still hashes each key at run time (`key_hash`/`hash_at`/`find_entry`,
~10% of `calls`): the second half of the sixth profile's row 1, a `MakeObject` that carries its keys'
interned hashes and sizes the table up front.
