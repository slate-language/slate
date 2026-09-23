# 2026-09-23 — A MODULE-LEVEL `var` IS WRITTEN TO ITS CELL AND NOWHERE ELSE

`globals.sl` — `arith`'s loop at a file's top level, where `total` and `i` are module-level `var`s —
was 683 ms against `arith`'s 243 ms, 11x qjs. `module-cells` had already made every read and write of
such a variable an index into `Vm.defs` (`LoadCell`/`StoreCell`), so the question was what a
`StoreCell` still paid over a `StoreSlot`. It is now **165 ms: −75.8%**, below `arith` itself.

Control `bdf593e` (dev, sysl 0.0.128, `lto = "thin"` both sides); branch `module-vars`.

## What a write cost

The instructions did not change and neither did their count: `globals` executes **102,000,020**
instructions on both sides — 24,000,002 `LoadCell`, 12,000,000 `StoreCell`, and the fused pair
`LoadCell PushInt` at 17.6% of adjacent pairs. What changed is what `compose_store_cell` does per
`StoreCell`. Before, on every write:

1. **An interpolated sentence**, `s"written to \`${name}\`"`, was built as `keepable_on`'s argument —
   a `malloc`, a zeroing and a `free` — and thrown away, since the value was never absent. The same
   eager string sat in `compose_declare_name`, `compose_store_name` and `compose_declare_cell`, which
   is every by-name binding and write in the interpreter.
2. **The module's scope was written through**: `def_scopes.at(d).names.put(name, stored)`, a hash of
   the spelling and a probe of the scope's table, so that anything reading the scope by name would
   see the latest value.

A `sample` of a 60,000,000-turn `globals` on the control, top of stack: `run_frames` 402,
**`_xzm_free` 399, `Map.put<string,Value>` 92, `__bzero` 89, `free` stub 86**, `memmove` 81,
`memset` 70, `_tlv_get_addr` 63, `_xzm_xzone_malloc` 62. On the branch: `run_frames` 744 and `added`
113, **and nothing else above five samples** — every allocator frame and the hash map are gone.
`_tlv_get_addr` was the allocator's own thread-local, not the interpreter's.

## The change

- **The sentence is built only when it is said**: `if is_absent(v) then keepable_on(...)?` at all four
  sites, which is the shape `site_cache.sysl` already used.
- **A filled cell is the variable, and the scope is not written after the binding.** Every read the
  compiler emits of a cell-backed spelling is the cell — the file's own statements, its functions and
  closures, and now **the export object** (`export_object` in `compile.sysl` goes through
  `read_module_name`, so an exported `var` is a `LoadCell` and a spelling that is put back is a
  `LoadName` as before). A spelling read by name anywhere in the file takes all of its sites back to
  the lookup (`settle_module_defs`), so nothing compiled reads a cell-backed `var` through the scope.
- **The scope binds a `var` as `null`** at its declaration (a `val` keeps its value — it is never
  written again). The name is still bound, so the scope still says the file has it; a copy of the
  first value would have been stale and would have kept it alive for the life of the run.
  `Vm.defs` is a collector root, and for a `var` it is now the only holder of the latest value.
- `Vm.def_scopes` is gone.

`run_frames.sysl` is untouched (the arms were already `LoadCell`/`StoreCell`), so no `Op`, no `Step`
width and no jump-table order moved.

## Wall time

Alternating best-of-9 on `bench/timeit.pl` (`bench/alternate.pl 9`), control and branch back to back,
nine times, lowest of each kept, under `caffeinate -dimsu`. Box 88.9% idle at the start (the run
waited for it), `pgrep -x java` empty; 82.9% at the end.

| | dev `bdf593e` | module-vars | change |
|---|---|---|---|
| **globals** | 683.0 | **165.4** | **−75.8%** |
| funcs | 238.0 | 185.6 | −22.0% |
| dispatch | 435.0 | 339.7 | −21.9% |
| branches | 332.9 | 265.9 | −20.1% |
| methods | 431.4 | 351.2 | −18.6% |
| options | 323.5 | 271.0 | −16.2% |
| nested | 334.5 | 283.6 | −15.2% |
| closures | 196.1 | 169.2 | −13.7% |
| reals | 337.7 | 301.2 | −10.8% |
| fields | 205.9 | 186.5 | −9.4% |
| alloc | 373.3 | 341.0 | −8.7% |
| loops | 156.0 | 143.2 | −8.2% |
| fib | 443.2 | 408.9 | −7.7% |
| startup | 5.15 | 4.76 | −7.6% |
| strwalk | 9.43 | 8.76 | −7.1% |
| arith | 242.7 | 226.0 | −6.9% |
| mapset | 215.2 | 204.6 | −4.9% |
| csv | 220.5 | 214.0 | −3.0% |
| arrays | 239.8 | 232.8 | −2.9% |
| calls | 333.1 | 325.9 | −2.2% |
| strindex | 7.55 | 7.39 | −2.1% |
| strings | 744.4 | 749.4 | +0.7% |
| sorting | 522.7 | 529.3 | +1.3% |
| **GEOMEAN** | | | **−14.73%** |

**Only `globals` is this change.** `funcs` executes no `StoreCell`, `DeclareVar`, `DeclareVal` or
`StoreName` at all (its profile: `LoadName` 1, `DeclareSlot` 2), yet reads −22%; a three-round recheck
of `funcs` alone gave the branch −6% to −13%. The rest of the column is the binary's layout: the two
`run_frames` bodies differ by 428 bytes and start at different alignments (`…db00` in the control,
`…d9ac` in the branch), which is the thin-LTO lottery `one-jump-table` and `sysl-0-0-128` describe.
Read the geometric mean as **globals's −75.8% over 23 programs, ≈ −6%**, plus layout that the next
build may take back.

## Position

`globals`, best of five each, same box: **slate 165 ms, qjs 61 ms (2.7x, was 11x), Lua 103 ms
(1.6x), CPython 399 ms (0.41x — slate is 2.4x faster)**. `arith`, the same loop in a function, is
226 ms: a module-level `var` now costs less than a slot, `arith` paying a call and its frame.

## What is left

`LoadCell PushInt` is still the top pair at 17.6% of `globals`'s pairs, and the `LoadCell` arm still
bounds-checks and matches `Undefined` before it pushes. A fused arm is the next step if the counter
still says so after `superinstructions-2` lands on `run_frames.sysl`; at 2.7x qjs it is no longer the
outlier it was.

## Tests

`tests_module_vars.sysl` (5): the export object reads an exported `var` from its cell and a put-back
spelling by name; a loop, a function and an early closure all read the last write; all four refusals
of absence still name the variable (cell write, cell binding, by-name write, by-name binding); a
value written to a module `var` survives collections in a one-megabyte heap with the cell as its only
holder. `tests/lang/modulevars.sl` (7, both back ends) with `tests/lang/lib/tallied.sl`: a top-level
loop, a function writing the file's variable, a closure reading the latest value, an import of a
variable the module wrote after declaring it (`settled` 1 → 24, `shape` rebound to another kind), an
import of a put-back spelling, a refused absent write, and a closure another module hands out writing
its own variable while the importer's snapshot stays.
