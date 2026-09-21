# 2026-09-20 — A BUILTIN STOPPED COPYING ITS ARGUMENTS — the other half of shortlist item 11

Every call of a builtin popped its arguments off the operand stack into a freshly `malloc`'ed
`Buf[Value]`, held each one on the shadow stack for the length of the call, ran the native and freed
the buffer. Builtins are most of what a real program calls, so that was a malloc, a free, a copy of
every argument and a `hold`/`release` each on nearly every call slate makes.

**They stay on the stack now.** A native is handed an `Args` — a base INDEX into the running
machine's operand stack and a count — and the dispatch cuts the arguments and the callee off once it
has answered, pushing the result where they stood. **An index and not a pointer, which is the whole
of its safety**: a builtin that runs a slate callback runs it on that same stack, pushing above the
standing arguments, and a stack deep enough to grow replaces its storage. The stack is already a
root the tracer walks, so the per-argument hold at the dispatch went with the buffer.

`in_place_call` became `placed_call`, answering which of three things a call is: entered in place, a
builtin read where it stands, or the buffer — for a named call, a spread, a variadic callee, an
`async` or a generator, which all have to look at the arguments before there is anywhere to put them.

Both binaries built in this session from the two ends of one branch, so the control is dev
**`275b2d8`** and the branch is that tree with this change and nothing else. `bench/run.sh -n 5`
under both locks, box 98.6% idle at the start and 94.2% at the end, no other build, gate or timing
run going. **Every figure is the MEAN OF BOTH ORDERINGS** (control→branch and branch→control),
because whichever binary is timed second reads slower on this box. Milliseconds of process wall time.

| | dev `275b2d8` | native-args | change | dev/lua | native-args/lua |
|---|---|---|---|---|---|
| mapset | 806.2 | **600.0** | **-25.6%** | 47.4x | 34.1x |
| csv | 587.3 | **507.8** | **-13.5%** | 1.9x | 1.7x |
| strings | 791.4 | 770.6 | -2.6% | 2.2x | 2.1x |
| nested | 1437.4 | 1406.0 | -2.2% | 11.0x | 10.7x |
| dispatch | 1588.8 | 1557.9 | -1.9% | 17.9x | 17.0x |
| closures | 862.3 | 850.6 | -1.4% | 18.6x | 18.1x |
| methods | 1853.9 | 1846.9 | -0.4% | 13.1x | 13.1x |
| arrays | 1227.8 | 1224.8 | -0.2% | 13.2x | 13.1x |
| options | 1488.6 | 1485.4 | -0.2% | 17.8x | 17.9x |
| branches | 1360.3 | 1357.3 | -0.2% | 13.2x | 13.3x |
| calls | 1142.3 | 1144.8 | +0.2% | 7.5x | 7.5x |
| alloc | 1244.1 | 1252.0 | +0.6% | 7.9x | 7.7x |
| fields | 1201.2 | 1209.1 | +0.7% | 19.9x | 18.7x |
| loops | 923.0 | 929.7 | +0.7% | 7.7x | 7.9x |
| fib | 1853.0 | 1871.7 | +1.0% | 23.5x | 23.7x |
| sorting | 763.4 | 771.7 | +1.1% | 1.3x | 1.3x |
| reals | 1255.7 | 1270.9 | +1.2% | 22.1x | 21.6x |
| arith | 1234.7 | 1253.0 | +1.5% | 26.4x | 26.3x |
| funcs | 1014.6 | 1032.4 | +1.8% | 22.1x | 21.2x |
| globals | 1871.2 | 1936.6 | +3.5% | 18.4x | 19.5x |
| strindex | 11.5 | 11.9 | +3.5% | 4.7x | 4.7x |
| strwalk | 12.8 | 13.4 | +4.7% | 0.1x | 0.1x |
| **geometric mean vs lua** | **8.9x** | **8.65x** | | | |
| geometric mean vs node --jitless | 6.8x | 6.65x | | | |
| geometric mean vs python3 | 4.7x | 4.55x | | | |

**Two of these are the measurement and twenty are the box.** `mapset` and `csv` are the benchmarks
that call builtins in their inner loop — a `Map.set`/`Map.get` a turn, a string method a field — and
they moved 26% and 14%. Everything from `strings` down to `funcs` sits inside this machine's
run-to-run spread, which the four readings show directly: `globals` read 1857, 1885, 1916 and 1957
across control and branch with the Lua column moving the other way, and `strindex` and `strwalk` are
11- and 13-millisecond programs where half a millisecond is 4%. **A change that touches the call path
and does not call builtins should read zero, and twenty of these do.**

### THE MATCH ARM ORDER WAS WORTH 3% AND IS THE ONE THING HERE WORTH REMEMBERING

The first cut wrote the builtin arm FIRST in both call instructions, ahead of the ordinary
in-place call. `funcs` read **+3.3%** and `dispatch` **+3.1%** against the control, over two
orderings, with Lua drifting the other way — a real regression on two benchmarks that call almost no
builtins at all. Moving the arm BEHIND `InPlace` and changing nothing else brought both back:
`funcs` 1030.6 → 1029.7 (**-0.1%**) and `dispatch` 1583.9 → 1578.7 (**-0.3%**), same day, same
binaries, both orderings. **The hottest `match` in the interpreter pays for the order of its arms**,
and the common case has to be written first.

### Per builtin, and why the per-call figure barely moves

`SLATE_PROFILE=1` times the INSIDE of `run_native` only. The malloc, the free, the copies and the
holds were all in the dispatch AROUND it, so what the per-call figure can see is one thing: a native
reading `args.at(i)` used to go through `Buf.at<Value>`, which retains and releases the buffer on
every read, and now reads the stack. Two million calls each, one program, a profiled run being
slower than a plain one:

| builtin | calls | dev `275b2d8` | native-args | per call |
|---|---|---|---|---|
| `Map.set` | 2,000,000 | 187,687 us | 184,327 us | **93.8 -> 92.2 ns** |
| `indexOf` | 2,000,000 | 152,142 us | 141,446 us | **76.1 -> 70.7 ns** |
| `push` | 2,000,000 | 113,265 us | 109,946 us | **56.6 -> 55.0 ns** |
| `abs` | 2,000,000 | 90,559 us | 87,466 us | **45.3 -> 43.7 ns** |

**The same program's WALL time went 6239 ms to 5789 ms, -7.2%**, with the collector unchanged at
2712 and 2716 ms — so 450 of those milliseconds came off the 3527 ms that is not the collector, which
is **-12.9%**, against 1.6 to 5.4 ns per call inside `run_native`. **The rest of it is the malloc and
the free the profiler cannot see**, which is the whole of this change.

### The witness a benchmark cannot give

`Vm.args_buffered` counts calls that copied their arguments into a buffer, and `tests_slots.sysl`
reads it. A plain builtin call, a builtin reached as a method, `push`, `Map.set` and a
callback-taking builtin now charge ten thousand calls fewer than two hundred between them, where the
builtin control used to assert the opposite. **A spread call of a builtin is the control that still
buffers** — its arguments arrive in an array rather than on the stack, so they have to be put there
before a window can point at them — and a named argument to a builtin is still refused in the
sentence it always was.

