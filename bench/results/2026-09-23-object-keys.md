# 2026-09-23 — AN OBJECT LITERAL'S KEYS ARE THE UNIT'S, WITH THEIR HASHES

The second half of the sixth profile's row 1, and `construction`'s *"What is left"*: after that item a
key was one cell, but every object literal still pushed each key with a `PushStr` and `obj_put` hashed
it again (`key_hash` → `hash_at` → `find_entry`, ~10% of `calls`).

**An object literal's keys are always literal strings** — slate has no computed key — so the compiler
knows all of them. `MakeObject(first: u32, n: u32)` now names a run of the new `Unit.object_keys`
(string indices, laid down by `intern_object_keys` in `literal.sysl`); only the VALUES are pushed.
`compose_object` takes each key's cell from `literal_on` and its hash from `Unit.string_hashes`, and
writes through the new **`obj_put_keyed`** in `table.sysl` — `obj_put_named`'s shape with the cell
handed in, so nothing is hashed or boxed and the summary bit (`obj_lacks`) skips the search for every
key but a repeat or a summary collision. The module-exports object (`export_object`) is built the same
way. Semantics are exact: a repeated key keeps its first place and its last value, `proto` is an
ordinary key, and the slot and hash are the ones `obj_put` would have given (pinned below).

**No pre-size was added**, and that was checked rather than assumed: a sweep's kept tables
(`collector.sysl`, `FirstTable` = 8) are exactly the size a first push gives, so every literal of up to
`SmallTable` keys already takes one with no `Buf.grow`, and a larger literal's entries are rebuilt by
`grow` when its index is made, so a pre-size there would be thrown away. Allocator steps did not move.

Control `b95fbcf` (dev, thin LTO); branch `object-keys`, same build.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), both orderings, a shared box (74% idle, another
agent's bench and a sysl test running — which is why both orderings were taken).

| program | dev ms | branch ms | change | reversed ordering |
|---|---|---|---|---|
| **alloc** | 252.9 | 192.6 | **−23.9%** | −23.1% |
| **calls** | 217.9 | 182.9 | **−16.0%** | −18.6% |
| **fields** | 167.3 | 150.0 | **−10.3%** | −11.6% |
| **options** | 242.0 | 222.3 | **−8.1%** | −7.2% |
| **csv** | 189.9 | 184.6 | **−2.8%** | −1.0% |
| fib | 287.1 | 260.1 | −9.4% | −11.7% |
| branches | 297.2 | 236.9 | −20.3% | −22.2% |
| globals | 204.3 | 164.1 | −19.7% | −17.4% |
| sorting | 524.0 | 529.9 | +1.1% | +0.9% |
| **geometric mean, all twenty-three** | | | **−8.65%** | **−8.0%** |

**Read the mean as an upper bound.** `branches`, `globals`, `loops` and `fib` build no object and
moved 10–20% in both orderings with identical instruction counts — code layout in the loop, the thing
`construction` saw the other way (+15% on `fib` from moving `PushStr`). What this change itself buys
is the instruction count: `fib` did **not** get slower, which was the risk named for `run_frames.sysl`
(992 lines before and after; the arm grew arguments, not lines).

`SLATE_PROFILE` (`--features profile`), dev against branch:

| | dev | branch |
|---|---|---|
| `calls` instructions | 40,000,044 | **36,000,038** (−10.0%) |
| `calls` `PushStr` | 4,000,007 | **1** |
| `alloc` instructions | 45,000,023 | **39,000,023** (−13.3%) |
| `alloc` `PushStr` | 6,000,000 | **0** |
| `calls` / `alloc` allocator steps | 1,998,745 / 2,998,742 | 1,998,745 / 2,998,742 (unchanged) |
| `calls` / `alloc` collections | 1,591 / 2,382 | 1,591 / 2,382 (unchanged) |

`bench/check.sh`: every answer unchanged in all four languages.

## The tests

- **`tests_object_keys.sysl`** — six: the keyed write puts every key where `obj_put` does (same hash,
  entry order, index slots, summary and mark flag) for 1 to 70 keys, across the small-table line and
  two rehashes, and the general lookup finds each; a key written twice is one entry with the later
  value; a key whose hash shares `proto`'s summary bit is its own entry; a `(val)` mark key is noted;
  an object literal emits no `PushStr` for its keys and its `MakeObject` names them in order; a
  literal's key is the literal's kept cell.
- **`tests/lang/objectkeys.sl`** — eight, both back ends: key order, a repeated key, every key found by
  a hashing lookup (including `proto` and `""`), a literal with `proto` delegating, a 12-key literal in
  a loop, a fresh object per turn, class/literal equality, and the absence refusal still firing.
- `tests_module_vars.sysl` reads the two-operand `MakeObject`.

## What is left

`with { … }` (`WithFields`) still pushes a `PushStr` per key and writes through `obj_put`; the same
`object_keys` run would serve it.
