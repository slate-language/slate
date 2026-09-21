# 2026-09-21 — A FIELD READ REMEMBERS WHERE IT LOOKED — shortlist item 4

**Looking a name up in an object was 6.5% of weighted wall time and 28.2% of `fields`, 25.3% of
`methods` and 19.2% of `mapset`.** The
[second sampled profile](2026-09-21-sampled-profile-2.md) named the parts: `scan_named` 2.13%,
`obj_get_name` 1.12%, `read_field` 0.92%, `find_entry` 0.60%, `field_from` 0.57%. Every one of them
is the same walk, made from scratch at every turn of every loop.

**Measured: -2.33% on the alternating best-of-9 geometric mean**, against a ceiling of 3–4%.
`fields` **-40.2%** and `methods` **-10.5%**. Control is dev `b12a193`.

## The idea, and why it needs no invalidation at all

**A site remembers a POSITION and never a value, and never the object it saw.** That single decision
is what removes the whole invalidation problem. The usual difficulty with an inline cache is knowing
when the answer has stopped being the answer — a field added, a method reassigned, a class
redefined, a proto swapped under it, a module reloaded, another thread writing — and each of those
is a rule that has to be found, written down and kept.

**A remembered position is not believed. It is CHECKED.** `key_here` reads the key standing at that
position in *this* object's *current* table and compares it with the name being looked up; an answer
built from a hit is right by construction, and a guess that has gone stale is a miss costing the
search it was trying to save. There is no rule to keep, and nothing anywhere has to tell the cache
that the world changed.

**AND THAT IS WHY IT HELPS EVERY INSTANCE OF A CLASS RATHER THAN ONE.** Two objects a constructor
made take their fields in the same order, so `x` is at the same position in both — the site's guess
is right for every one of them, and right again for the class object each instance delegates to. A
site that genuinely alternates between two shapes pays one key comparison before falling back. A
cache keyed on the receiver's identity would have needed a GC-safe way to hold a pointer and would
have missed on the second instance; this needs neither.

## The three pieces

| piece | where | what it is |
|---|---|---|
| the cell | `SiteCache` in `code.sysl`, a `Buf` on the `Unit` | `own`, `hop`, `up` — where the name sat in the receiver, where `proto` sat, where the name sat in that proto |
| the slot | a second number on `GetField`, `SetField` and `CallMethod` | `fresh_site(u)` hands one out per instruction at compile time |
| the summary | `ObjectObj.keys_bloom`, a `u64` | one bit per key the table has ever held, taken from the key's hash |

**The summary is what makes a MISS cheap, and a miss is what a method call is.** `a.dot()` asks the
receiver for a name the receiver does not have — every time, by construction, the method being the
class's — and that question used to walk the whole table. `obj_lacks(o, h)` is one `and`. A removed
key leaves its bit behind on purpose: the set only ever grows, so the answer is only ever
conservative and being wrong costs the search that would have happened anyway.

**The name's hash is computed ONCE, when it is interned** (`Unit.string_hashes`, beside
`string_chars` and for its reason). Hashing walks the text, and a field name written inside a loop
was being walked on every turn; the three instructions that look a name up carry the answer with
them.

**Where the cells live is what answers the actor question.** They are a `Buf` on the `Unit`, and a
`Unit` is a field of the `Vm` (`vm_state.sysl`'s `current_unit`). An actor compiles the program's
declarations into a unit of its own on its own thread, so no two lines of execution ever write one
cell and there is nothing here to make atomic.

**`Ins` DID NOT GROW.** `CallMethod` took a fourth number, which fits inside the four `CheckSlot`
already asked for. `AN_INSTRUCTION_IS_NO_WIDER_FOR_CARRYING_A_CACHE_SLOT` in `tests_site_cache.sysl`
pins `sizeof(Ins)` at 56 bytes, because the instruction is fetched and copied once per dispatch and
its width is the interpreter's hottest constant.

**`run_frames.sysl` did not grow either** — two arms changed and `write_named` moved out of
`run_compose.sysl` into the new `site_cache.sysl`, which is where the bodies are.

## The write path pays twice over

`o.name = v` used to make **two** searches of the same table: `write_property` opens by asking
whether the object has the field itself, and `obj_put_name` then looks for it again. A checked
position answers the first question, so an ordinary write to an ordinary field is now one key
comparison and one store. The frozen check is NOT skipped with it — a data value refuses a write to
a field it has, so that refusal stands in front of the fast path.

**And the refusal's sentence is built only where it is going to be said.** `keepable_on(…, s"stored
in \`${name}\`")` interpolates a string, which allocates; it was being built on every field write in
every program to describe a refusal that almost never happens.

## THE TWO THINGS THAT MADE THE DIFFERENCE BETWEEN -0.96% AND -2.33%, AND BOTH ARE WORTH KEEPING

The first build of this measured **-0.96%** on the mean with the same -36% on `fields`, and a broad
+1.5% to +5.6% on programs that read no field at all. Neither cause was the cache.

- **A CALL ADDED UNDER `obj_get_name` COST 2.3% ON `options`.** The two-way switch (walk the entries,
  or probe the index) had been written out in `obj_get_name`; factoring it into `obj_index_named` so
  the cache could reach the position put one more frame under a function a pattern match asks twelve
  million times. It is written out in both places now, with a comment saying why.
- **A VALUE HELD IN A `run_frames` ARM IS LIVE ACROSS THE WHOLE LOOP, and two of them cost about 2%
  on programs that never execute that arm.** The loop is one function, so `u.strings.at(k)` and
  `u.string_hashes.at(k)` computed *in the `GetField` arm* raise register pressure everywhere. Moving
  both reads inside the called function — the arm passes `u`, `k` and the cache slot — took `arith`,
  `fib`, `funcs`, `closures` and `nested` back and took the mean from -1.40% to **-2.33%**, with
  `methods` going -4.1% to **-10.5%** in the same build.

**This is the same lesson `native-args` and the `InPlace` arm ordering already wrote down**, from a
third direction: the hottest `match` in the interpreter is paid for by everything the program does,
so what an arm *holds* matters as much as what it does.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `b12a193` against the branch, on a box at
88.2% idle with `pgrep -x java` empty, under `caffeinate -dimsu`. `bench/check.sh` says every
program's answer is unchanged.

| program | control | branch | change |
|---|---|---|---|
| **fields** | 554.744 | 331.506 | **-40.2%** |
| **methods** | 766.667 | 686.225 | **-10.5%** |
| alloc | 706.457 | 686.190 | -2.9% |
| calls | 680.924 | 663.500 | -2.6% |
| strings | 791.753 | 778.421 | -1.7% |
| sorting | 549.468 | 545.109 | -0.8% |
| loops | 379.103 | 376.312 | -0.7% |
| globals | 1277.346 | 1277.931 | +0.0% |
| csv | 414.117 | 414.454 | +0.1% |
| mapset | 300.258 | 302.068 | +0.6% |
| options | 687.978 | 692.143 | +0.6% |
| reals | 453.052 | 456.205 | +0.7% |
| strwalk | 11.392 | 11.532 | +1.2% |
| nested | 627.703 | 636.575 | +1.4% |
| closures | 301.997 | 306.636 | +1.5% |
| arrays | 484.648 | 492.648 | +1.7% |
| funcs | 306.603 | 312.113 | +1.8% |
| fib | 665.692 | 678.072 | +1.9% |
| strindex | 9.480 | 9.693 | +2.2% |
| arith | 369.659 | 379.432 | +2.6% |
| dispatch | 563.581 | 586.045 | +4.0% |
| branches | 418.821 | 445.028 | +6.3% |
| startup | 5.328 | 4.858 | -8.8% |
| **GEOMEAN** | | | **-2.33%** |

**`mapset` did not move, and the profile said it would.** Its 19.2% is `Map`/`Set` work reached
through `setmap.sysl`'s natives, which look a key up by VALUE through `obj_get`; only a field read
written in the source gets a site to remember anything with.

**THE PER-PROGRAM COLUMN SWINGS BY SEVERAL PERCENT BETWEEN BUILDS OF NEARLY IDENTICAL CODE, AND THE
EVIDENCE IS IN THIS PAGE'S OWN THREE RUNS.** `branches` read -0.9%, +0.3% and +6.3% across the three;
`closures` read +5.6%, +3.6% and +1.5%; `options` +2.3%, +1.8% and +0.6%. What moved monotonically
was the mean, as real overhead came out. `bench/results/2026-09-20-branches-benchmark.md` and the
`InPlace` ordering note in `CLAUDE.md` both say the same about this loop: it is layout-sensitive at
the few-percent level, and a single program's column is not evidence on its own.

## The witness

`/usr/bin/sample` at 1 ms over `bench/methods.sl`, both binaries, self time from "Sort by top of
stack", against the main thread's own sample total.

| | before (611 samples) | after (576 samples) |
|---|---|---|
| `scan_named` | 77 | — |
| `obj_get_name` | 42 | — |
| `field_from` | 33 | — |
| `read_field` | 28 | — |
| `field_from_site` | — | 52 |
| `key_here` | — | 41 |
| `read_field_site` | — | 24 |
| **the lookup, together** | **180 — 29.5%** | **117 — 20.3%** |

The whole program is 576 samples where it was 611, so the lookup fell by **35% in absolute time** and
by nine points of share. What is left is the two calls the fast path still makes and the key
comparison inside them.

## What is NOT cached, and why

- **A negative answer about a name the object genuinely holds nowhere on its chain.** The summary
  makes each step cheap, but a walk of the whole chain still happens. Nothing here remembers absence.
- **`CallMethodSpread`.** It carries no slot; a spread call is rare and already builds an array.
- **A builtin kind's method table.** `xs.push` is an array read in `method.sysl` already.
- **The uncached callers.** `field_from`, `read_field` and `write_named` are unchanged for everything
  that is not one of the three instructions — a native, an actor's delivery, a property accessor —
  and they share cell zero of the unit, which is a guess like any other and is checked like any other.

## What the tests pin

`tests/lang/sitecache.sl` is the half that matters to a reader, and every test in it runs ONE place
in the program twice with the answer changed in between — the only shape that can catch a cache
handing back what it found last time. A field added after a read missed; a table grown past its small
case so every position moved; one place reading two shapes; a write landing in either shape and
making a field in one of them; a method replaced on the class; a field written on the object winning
over the one its class shares; a proto swapped; a property and a setter still reached at a place that
has seen a plain field; a data value still refusing a write; and an actor reading its own fields,
properties and classes on its own thread. **They run under `slate js` too**, where there is no cache
at all, which is what makes them tests of the language rather than of this.

`tests_site_cache.sysl` is what only sysl can ask: that the summary never hides a key that is there
(across the line an index is built at), that a removed key leaves its bit and is still not found,
that a rehash moves every position and the answers survive it, and that `Ins` is still 56 bytes.
