# 2026-09-21 — cheaper frames: the chunk is read once per call and never on a return (`chunk-per-call`)

Shortlist item 5, and the profile's fourth-largest name: `Buf.at<Chunk>` was **4.0% of all samples**
and **13.0% of `fib`**, because the ordinary call read the callee's `Chunk` out of the table **four
times** — once in `placed_call` to decide the path, once in `lay_standing` for the parameter and slot
counts, once for the code buffer and once for the file the loop stamps a fault with — and a `Ret` read
it **twice more** to put those last two back. Six copies of a whole `Chunk`, each with a retain and a
release per counted member, per call and return.

**What changed is who carries the answer, and nothing else.** `placed_call`'s `InPlace` plan grew from
two fields to six, `Called.Enter` from three to five, and `Frame` gained `code` and `source` — so a
call is decided from the one read the decision already made, and a return restores the loop out of the
frame it is popping. `lay_standing` takes the two counts rather than looking the chunk up for them.
`run_frames` reads `u.chunks.at` exactly **once**, on entry. Nothing about the value representation,
`Buf`, the instruction set or any answer a program can see changed; `run_frames.sysl` went 993 to 999
lines.

**A FRAME IS NOW SELF-DESCRIBING, AND THAT IS THE INVARIANT THE TESTS ARE ABOUT.** `Frame.code` is its
chunk's instructions and `Frame.source` the file its spans are offsets into, so every site that makes a
frame — six call arms, `Yield`, `Await`, and `start_generator` — has to write both, and `Ret` and
`resume_failed` read them back. A stale one fails in two different ways: a stale **code** buffer is
caught by the ANSWER, and a stale **file** by a DIAGNOSTIC raised after the call has come back, which
quotes the other file at this file's offsets and says nothing about being lost.

### Wall time

Alternating best-of-9 on `bench/timeit.pl`, control and branch back to back, nine times, lowest of each
kept. Control is a detached build of dev `d5326dd`, the commit this branched from. Under `caffeinate`,
`pgrep -x java` empty, box at ~84% idle with a steady neighbour — which is what the alternating method
is for, and the reason `bench/run.sh -n 5` in two passes is not used here.

| program | dev `d5326dd` | `chunk-per-call` | change |
|---|---|---|---|
| alloc | 1111.172 | 1120.790 | +0.9% |
| arith | 1107.118 | 1107.318 | +0.0% |
| arrays | 1142.820 | 1149.689 | +0.6% |
| branches | 1214.691 | 1233.250 | +1.5% |
| calls | 1126.268 | 1062.118 | **-5.7%** |
| closures | 792.081 | 725.193 | **-8.4%** |
| csv | 506.392 | 506.393 | +0.0% |
| dispatch | 1410.461 | 1294.269 | **-8.2%** |
| fib | 1564.375 | 1300.165 | **-16.9%** |
| fields | 1166.226 | 1172.932 | +0.6% |
| funcs | 883.872 | 766.638 | **-13.3%** |
| globals | 1830.382 | 1818.192 | -0.7% |
| loops | 876.307 | 888.048 | +1.3% |
| mapset | 554.158 | 569.004 | +2.7% |
| methods | 1816.508 | 1729.455 | **-4.8%** |
| nested | 1350.351 | 1237.844 | **-8.3%** |
| options | 1344.248 | 1258.538 | **-6.4%** |
| reals | 1209.626 | 1204.966 | -0.4% |
| sorting | 814.631 | 838.102 | +2.9% |
| startup | 5.037 | 4.839 | -3.9% |
| strindex | 11.495 | 11.630 | +1.2% |
| strings | 789.009 | 787.947 | -0.1% |
| strwalk | 12.929 | 12.848 | -0.6% |
| **geometric mean** | | | **-3.02%** |

**THE PROFILE'S RANKING WAS RIGHT AND ITS CEILING WAS LOW.** The estimate on the shortlist was 2-3% of
the mean; the measurement is **3.0%**, and the per-program column predicted the winners in order —
`fib` 13.0% of its samples and **-16.9%** of its wall, `closures` 10.5% and -8.4%, `nested` 8.2% and
-8.3%, `calls` 7.3% and -5.7%. `funcs` at **-13.3%** is the one the sampled table did not name, its
`Buf.at<Chunk>` line having fallen below the five-sample cut; a loop of small calls pays this per call
whether or not the sampler could see it. **The eight programs that moved are the eight that call**, and
the ones that do not — `arith`, `csv`, `strings`, `arrays` — sit within a percent of the control either
way, which is the shape of the answer rather than an accident. `mapset` +2.7% and `sorting` +2.9% are
the neighbour: both are builtin-bound, neither enters a slate chunk in its inner loop, and nothing in
this change reaches them.

### The tests, and the control that says they bite

`tests_frames.sysl` and four fixtures under `tests/mods/`. **The fixtures are several files on purpose**
— while a program is one file the source is always zero and the file half of the invariant cannot be
observed at all — and each one ends in a **run-time** fault (`1 \ 0`), never an unbound name, which is
refused before the program runs and would never reach the call under test.

Six tests: a hundred returns alternating between two files; a fault raised fifty frames down in the
other file, caught here, with execution carrying on; a constructor, a `map` callback the other file
wrote, and a generator stepped from here; an `await` resumed with a value and an `await` resumed with a
**rejection**, which is `resume_failed`'s own path; two thousand frames of direct recursion and a
mutually recursive pair, so consecutive returns land in different code buffers; and a method call and a
named call, the in-place and buffered paths writing the frame back at two different instructions.

**A CONTROL BUILD PROVED THE FILE HALF DISCRIMINATES, AND CORRECTED TWO FIXTURES THAT DID NOT.** With
`Ret`'s `here.current_source = back.source` deliberately removed, `after_catch` and `after_shapes`
report the fault against `frames_lib.sl` at this file's offsets — a line that exists and is a comment.
The first draft of `after_across` and `after_catch` passed that build anyway: their outermost call was
their **own** file's, so the value left standing on a return that never restored was the right file by
coincidence. Both now make the last call before the fault one that crosses. That is the general rule
for a test of this kind and it is not visible by reading: **a stale value is only observable where the
correct value and the stale one differ.**

