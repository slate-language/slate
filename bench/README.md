# The benchmarks the slot work is measured by

Three programs, each a loop that does one thing, run with the binary built from the commit under
test. **They exist to be run before a change and again after it**, so what matters is that the
program and the machine are the same both times -- an absolute number here means nothing on its own.

| file | what it exercises |
|---|---|
| `arith.sl` | a tight arithmetic loop: two locals read and written per iteration, nothing else |
| `calls.sl` | a method call per iteration, which is a name lookup, a receiver rule and a frame |
| `strings.sl` | building a string a piece at a time, where the loop's own names are the overhead |
| `loops.sl` | a `for` over an array with a destructuring head, which is what ordinary slate looks like |
| `globals.sl` | the CONTROL: `arith.sl`'s loop at module level, where the names are not locals |

**THE FIRST FOUR PUT THEIR LOOP INSIDE A FUNCTION AND THAT IS DELIBERATE.** A name written at the
top of a module is a module-level binding that an importer reads by name -- an import is a load per
export -- so it cannot become a numbered slot in a frame however locals are resolved. A benchmark
written at the margin would measure the half this work does not change, and read the result as
nothing. `globals.sl` is that margin on purpose, so the two can be read side by side: the gap
between it and `arith.sl` is what slots are worth over whatever the lookup itself costs.

**`loops.sl` is the one that measures a BINDING FORM rather than a `val`.** A `for` head, a `match`
arm, a `catch` and a destructuring `val` each put a name into the running scope from code of their
own, so a chunk holding any of them gave up its slots entirely -- which is most real code, since a
`for` over something is how most loops are written. The other four are all `val` and `var` and cannot
see that at all.

Each prints its answer and the milliseconds it took, so a run that computed the wrong thing cannot
be read as a fast one. **The answer is printed first and is asserted by `bench/expected.txt`** --
an optimisation that changes it has broken something.

Run them with `bench/run.sh <path-to-slate>`; it prints one line per benchmark.
