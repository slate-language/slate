# 2026-09-22 — A MODULE'S OWN `val` AND `var` GET A CELL — profile 4's item 4

**`globals` −35.8% and −36.1%, geometric mean −1.82% and −1.87%** over profile 4's twenty-three, two
alternating best-of-9 runs from the same pair of binaries. Control is dev `7f2ee08` (sysl 0.0.125).
The item's ceiling was 0.6–0.9% of the mean and it took about **twice that**, because what it removed
from `globals` was not the hashing alone.

`bench/check.sh` says *answers unchanged* for all four implementations. **No instruction was added to
or removed from any program** — `bench/globals.sl` executes 102,000,020 instructions before and
after, the same instructions in the same order under different names.

## What a module-level name was paying

A module never slots. Its names are what an import reads — a load per export — so they have to stay
findable by spelling from a chunk that is not this one, and `slots.sysl` gives a module's names
neither a cell nor a slot. What was left was the scope chain, and the scope chain is a
`Map<string, Value>` per `EnvObj`:

```
total = total + i * 2 - 1
```

is, per turn, four `lookup`s (hash the spelling, walk outward to the module's own scope, read the
entry) and two `assign_name`s — and an `assign_name` is **three** hash lookups, not one:

```
if scope.names.has(name)                                   // is it here
    if !scope.mutable.get_or(name, false) then …           // may it be written
    scope.names.put(name, v)                               // write it
```

Ten hashes of a string a turn, for two questions the compiler had already answered — whether the
name is writable, and which scope it lives in. Sampled at 1 ms, that is `Map.find` 108 of 975, plus
`hash_str` 69, `Map.get<string,bool>` 52, `Map.get<string,Value>` 35, `lookup` 25, `assign_name` 30.

## What changed

**The table `LoadDef` already reads is opened to a file's own `val` and `var`.** `defs.sysl` claimed
a cell for every `def` written at a file's top level and resolved a read of one to `LoadDef(d)`, an
array index; `open_module_defs` now claims a cell for a top-level `Val` and `Var` as well, and three
instructions join it in `code.sysl`:

| | what it does |
|---|---|
| `LoadCell(d, k)` | push `defs[d]`, or take the lookup by spelling where the cell is empty |
| `DeclareCell(d, k, mutable)` | bind the scope exactly as `DeclareVal`/`DeclareVar` did, and fill the cell beside it |
| `StoreCell(d, k)` | write the cell, and write through to the module's own scope |

**A `var`'s cell is empty until its statement runs, which is the whole difference from a definition**
— a definition is hoisted, so its cell holds a closure before the first statement of the file. The
empty marker is `Undefined`, and it can be, because absence is the one value a program may not keep:
`keepable_on` refuses to bind or store it and both instructions that fill a cell go through that
refusal. So a cell reading `Undefined` says "nothing has been put here" and can say nothing else, and
a read or a write that finds one falls back to `lookup`/`assign_name` and says the sentence it always
said — which covers a function called above the `var` and the declarations-only load an actor runs.

**The scope is written through on every store, and that is not redundant.** The cell is the fast path
and the scope is still the only one an import's load per export, `declared_here` in `actor_copy.sysl`
looking a class up by name, and any read the compiler could not resolve will take. So the ten hashes
become **one**: the `Map.put` that keeps the two saying the same thing.

**Nothing new is refused and nothing is resolved that was not resolvable before.** The rule is
`defs.sysl`'s, unchanged in words: a binding written at the file's own top level whose spelling
nothing else in the file binds or writes. `put` still shuts a cell on every `DeclareVal`,
`DeclareVar`, `DeclareAbsent`, `DefineFn` and `StoreName`, a claimed slot and a pattern's names still
shut it, and `settle_module_defs` still puts every site of a shut name back — now reading the
instruction at the site to know which of the four it goes back to, rather than carrying a fifth field
that could disagree with the code.

One `StoreName` arm moved: a write to a spelling the file declared as a top-level `var` emits
`StoreCell` instead and does **not** shut the cell, which is what made the whole item possible —
before this, `total = …` was enough to put `total` back to a lookup everywhere.

## A bug the suite found on the way, and it was older than this change

`tests/lang/isbind.sl` went red: `if i is tag then …` inside a module-level loop read the file's `val
tag` instead of the name the pattern had just bound.

**A binding `is` binds at run time and no instruction says so**, which is exactly the hole
`shadowed_pattern` exists to cover for the forms that declare — and `IsPattern` was the one form that
never called it. It was not visible before because a top-level `val` was not resolvable, but **a
top-level `def` always was**, and dev has the same defect:

```
labelled() = "the definition"
var turn = 0
while turn < 2
    if turn is labelled then print(string(labelled))   // dev prints `<function>` twice
    turn = turn + 1
```

`compile_expr.sysl`'s `IsPattern` arm now calls `shadowed_pattern(u, pat)`, and
`A_BINDING_is_OVER_A_DEFINITIONS_SPELLING_IS_THE_ONE_THAT_ANSWERS` in `tests/lang/isbind.sl` pins it
on both back ends.

## The witness

`/usr/bin/sample` at 1 ms over `bench/globals.sl`, "Sort by top of stack, same collapsed", main
thread. `sample` truncates the table at 5 samples per name, so *absent* below means under 5.

| | control (975 samples) | branch (612 samples) |
|---|---|---|
| `Map.find<string,Value>` | **108** | **absent** |
| `Map.get<string,bool>` | 52 | absent |
| `Map.get<string,Value>` | 35 | absent |
| `lookup` | 25 | absent |
| `assign_name` | 30 | absent |
| `hash_str` | **69** | **14** |
| `Map.put<string,Value>` | 46 | 56 |
| `compose_store_name` / `compose_store_cell` | 33 | 34 |
| `_xzm_free` | 80 | 59 |
| `run_frames` | 120 | 122 |
| **total for the same work** | **975** | **612** |

The whole `Map<string, *>` read path goes off the profile and the one `put` that is left grows — that
is the write-through, doing the work all three of `has`/`get_or`/`put` used to share.

Instruction counts, `--features profile`, `bench/globals.sl`:

| control | branch |
|---|---|
| `LoadName` 24,000,003 (23.5%) | `LoadCell` 24,000,002 (23.5%), `LoadName` 1 |
| `StoreName` 12,000,000 (11.7%) | `StoreCell` 12,000,000 (11.7%) |
| `DeclareVar` 2 | `DeclareCell` 2 |
| **102,000,020 total** | **102,000,020 total** |

## The numbers

`bench/alternate.pl 9`, control `7f2ee08` against the branch, on a box at 94% idle with `pgrep -x
java` empty, run twice from the same pair of binaries.

| program | run A | run B |
|---|---|---|
| **globals** | **−35.8%** | **−36.1%** |
| **calls** | **−5.8%** | **−5.7%** |
| closures | −2.4% | −2.1% |
| nested | −0.9% | −3.0% |
| startup | −4.9% | −3.4% |
| dispatch | −0.8% | +0.8% |
| **branches** | **+4.2%** | **+4.9%** |
| methods | +3.3% | +1.0% |
| arith | +2.3% | +2.2% |
| loops | +2.3% | +1.8% |
| funcs | +1.5% | +1.8% |
| fields | +1.3% | +1.6% |
| **geometric mean, all twenty-three** | **−1.82%** | **−1.87%** |

`bench/run.sh -n 5` afterwards: **3.3x lua / 2.5x node --jitless / 1.7x CPython / 2.1x qjs** over the
twenty-three, and `globals` itself goes from 19x qjs to **12.1x** (7.0x lua, 1.8x CPython).

**`branches` is +4.2%/+4.9% in both runs and it is not noise, but it is not this change's arithmetic
either**: `bench/branches.sl` does all of its work inside `run()` and holds no module-level variable,
so not one of its instructions is different. What moved is `run_frames` — three arms longer, and the
loop's layout with it. This is the effect the `unfuse` write-up measured from the other side, where
**adding** code to the same dispatch cost `branches` 6.7%. `calls` (−5.8%) and `closures` (−2.4%)
moved the other way by the same mechanism. The net over twenty-three programs is −1.85%, and a
narrower `Ins` (item 5) is the item that addresses the dispatch's shape rather than its contents.

## What is left of the item

The one hash a store still pays is the write-through, and it is there because the module's scope is a
second, by-spelling way to the same binding. Removing it means making every by-spelling reader go
*through* the cell — `lookup`, `assign_name`, `export_object`'s load per export, `declared_here` —
which is a change to the scope object rather than to the instruction set, and a separate item. It is
worth about a third of what this one took on `globals` and nothing at all anywhere else.
