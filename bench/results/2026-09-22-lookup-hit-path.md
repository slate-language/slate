# 2026-09-22 — THE HIT PATH OF A FIELD READ IS ONE LOOK AT THE ENTRY — profile 4's item 2

**`fields` −9.1% and −9.7%, `methods` −12.1% and −10.8%, geometric mean −0.60% and −0.75%** over
profile 4's twenty, two alternating best-of-9 runs from the same pair of binaries. Control is dev
`507d978`; nothing in the compiler, the emitter or the instruction set changed, so every program is
the same program and what moved is what a `GetField`, a `SetField` and a `CallMethod` pay once they
have guessed right.

## What the hit path was paying, measured rather than reasoned

`sample` at 1 ms against the control, on `bench/fields.sl` and `bench/methods.sl` scaled ten-fold so
each run carries a couple of thousand samples. Self time, `sample`'s "Sort by top of stack" section:

| control, `fields` | samples | control, `methods` | samples |
|---|---|---|---|
| `run_frames` | 796 | `run_frames` | 1981 |
| **`key_here`** | **263** | **`field_from_site`** | **514** |
| **`read_field_site`** | **219** | **`key_here`** | **470** |
| **`field_from_site`** | **188** | **`read_field_site`** | **298** |
| **`write_named_at`** | **126** | `placed_call` | 233 |
| **`Buf.at<string>`** | **97** | **`Buf.at<string>`** | **112** |

**The lookup is 41% of `fields` and 32% of `methods`** — and `methods` is mostly field reads too,
`dot` and `scaled` making six own-field reads per turn against two method calls. So the thing to make
cheap was never the proto walk: it was the read that finds the field exactly where the site said it
would be.

**Three costs, and none of them is the search the cache exists to avoid:**

- **THE ENTRY IS READ TWICE.** `key_here(o, at, name)` read the entry to compare its key and answered
  a `bool`; `obj_value_at(o, at)` then read the same entry again for the value. An `Entry` is a key,
  a hash, a value and a flag, so that is two `Buf.at` calls, two bounds checks and two copies of some
  fifty bytes for one answer. A delegated method call did it three times over — own, hop, up.
- **A HIT AND A CERTAIN MISS COST THE SAME.** `key_here` compared the KEY, so the own-field check at
  the head of every method call — which cannot succeed, the method living on the class — paid a
  string comparison to find that out.
- **THE OWN-FIELD HIT WENT THROUGH TWO CALLS.** `read_field_site` read the name and called
  `field_from_site`, which is the same question asked of a whole proto chain: the receiver rule, the
  summary of the object's keys, the hop, the walk. A field the object holds itself needs none of it.

## What changed

`site_cache.sysl`, and nothing else but one precomputed hash on the `Unit`:

- **`field_here(o, at, name, h)` replaces `key_here` and answers `Option[Value]`** — one look at the
  entry answers both *is the position still right* and *what stands there*. The three sites that used
  to ask twice ask once.
- **The hash is compared before the key.** An entry carries the hash it was filed under and the
  caller already holds the name's, so the own-field check at a method call is refused by one integer
  comparison. **The key is still compared where the hashes agree**: two names that hash alike are a
  thing a program can construct, so this is a cheaper way to reach the same comparison and not a
  replacement for it.
- **`set_here` is the same move for a write**, which had the identical pair — ask, then store.
- **`read_field_site` answers an own-field hit without a call**, `field_here` inline in front of
  `field_from_site`. The absence is still tested, one comparison, rather than believed.
- **`Unit.proto_hash` is `"proto"` hashed once for the whole unit**, which is what lets the proto hop
  take the same hash-first path and what stops `walked_protos` hashing the word at every step.

**Nothing about the design changed**: a cell still remembers a POSITION and never a value, every
position is still checked before it is believed, and a stale guess still costs the search it was
trying to save. `bench/check.sh` answers *slate: answers unchanged* on all twenty-three.

## The sample after

| `fields` | before | after | | `methods` | before | after |
|---|---|---|---|---|---|---|
| `run_frames` | 796 | 772 | | `run_frames` | 1981 | 1616 |
| the key check | 263 | 242 | | the key check | 470 | 550 |
| `read_field_site` | 219 | 189 | | `read_field_site` | 298 | 265 |
| `field_from_site` | 188 | **gone** | | `field_from_site` | 514 | 199 |
| `write_named_at` | 126 | 184 | | `Buf.at<string>` | 112 | 136 |
| `Buf.at<string>` | 97 | 117 | | | | |
| **total listed** | **2,186** | **2,004** | | **`run_frames`** | **1981** | **1616** |

**`field_from_site` falls below the five-sample floor on `fields` entirely** — an own-field read never
calls it now — and `set_here` is absorbed into `write_named_at`, which is why that row grows while the
program gets faster. On `methods` the whole lookup group goes 1,394 samples to 1,150.

## The timing

**Alternating best-of-9 on `bench/timeit.pl`**, control and branch back to back on each program, nine
rounds, the lowest of each kept; then the whole thing again from the same two binaries. Under
`caffeinate -dimsu`, `pgrep -x java` empty. Milliseconds.

| program | control | branch | run 1 | run 2 |
|---|---|---|---|---|
| methods | 537.623 | 479.732 | **−10.76%** | **−12.12%** |
| fields | 257.749 | 232.821 | **−9.67%** | **−9.07%** |
| alloc | 596.049 | 582.723 | −2.23% | −0.24% |
| loops | 294.936 | 289.519 | −1.83% | +0.73% |
| sorting | 515.638 | 506.767 | −1.72% | +0.16% |
| fib | 518.690 | 513.467 | −1.00% | +0.16% |
| calls | 540.643 | 536.121 | −0.83% | +0.71% |
| csv | 359.461 | 362.301 | +0.79% | −0.66% |
| reals | 348.552 | 349.082 | +0.15% | −0.36% |
| funcs | 233.346 | 233.762 | +0.17% | +1.78% |
| branches | 324.996 | 325.647 | +0.20% | −0.07% |
| dispatch | 469.690 | 470.869 | +0.25% | +1.48% |
| globals | 1084.097 | 1088.098 | +0.36% | +1.73% |
| strings | 723.499 | 726.286 | +0.38% | −0.35% |
| mapset | 241.178 | 244.294 | +1.29% | −0.24% |
| closures | 230.434 | 233.827 | +1.47% | +1.31% |
| nested | 477.377 | 485.148 | +1.62% | −0.71% |
| arith | 268.510 | 272.900 | +1.63% | +1.33% |
| options | 570.984 | 587.456 | +2.88% | +2.27% |
| arrays | 424.447 | 437.575 | +3.09% | +1.47% |
| **geometric mean, the twenty** | | | **−0.75%** | **−0.60%** |

**The two programs the item is about agree to a percent across the runs and everything else changes
sign between them**, which is the reading to expect: `arrays` is +3.09% and +1.47%, `nested` +1.62%
and −0.71%, `loops` −1.83% and +0.73%. `options` is the one that stays positive in both at about
+2.5%, and it is a program of pattern matches over option objects — `match_pattern` reaches
`obj_get_name` and not this path at all, so there is nothing here for it to have paid.

**The instruction counts are unchanged and could not be otherwise**: the diff touches
`site_cache.sysl`, one field on `Unit` and two test files, and nothing that decides what is emitted.
`sysl test . --features profile` is green, and the two tests that assert exact per-instruction counts
are gated with the counting.

## What is left on this path, for whoever picks it up

- **`Buf.at<string>` is still 5% of `fields`** — `u.strings.at(k)`, the name read off the unit's table
  for the key comparison, which is a counted `string` copied by value on every field access. Removing
  it means the hit test comparing something other than the key, and the hash alone is not sound.
- **A site that always delegates still checks its own position first.** Nothing remembers that the
  answer came from a proto, so a method call reads the receiver's entry zero and rejects it by hash,
  every call. A biased cache slot (`0` meaning "nothing remembered") would skip the read; it was left
  out because it touches every reader and writer of a `SiteCache` position and the entry is in L1
  anyway.
- **The receiver rule is asked with a string comparison.** `name != "new"` runs on every delegated
  answer.
