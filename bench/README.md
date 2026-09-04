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
| `options.sl` | a function taking an options object apart WITH DEFAULTS, called in a loop |
| `closures.sl` | a loop calling a small closure that captures ONE of the function's names |
| `nested.sl` | the same loop as `loops.sl` in a chunk that keeps a scope for one captured name |
| `globals.sl` | the CONTROL: `arith.sl`'s loop at module level, where the names are not locals |

**THE FIRST FOUR PUT THEIR LOOP INSIDE A FUNCTION AND THAT IS DELIBERATE.** A name written at the
top of a module is a module-level binding that an importer reads by name -- an import is a load per
export -- so it cannot become a numbered slot in a frame however locals are resolved. A benchmark
written at the margin would measure the half this work does not change, and read the result as
nothing. `globals.sl` is that margin on purpose, so the two can be read side by side: the gap
between it and `arith.sl` is what slots are worth over whatever the lookup itself costs.

**`options.sl` is the one that measures a pattern with DEFAULTS in it**, which is a separate question
from `loops.sl`'s and was a separate step: the matcher leaves a defaulted name unbound and still
matches, so a binding site carrying one needs a per-name record of what arrived before its names can
be cells at all. It is `sluice`'s shape -- `val { title = "Untitled" } = props` -- and **half its
calls leave a name out and half supply it, interleaved**, so what it measures is the guarded
assignment rather than a branch the processor has learned.

**`loops.sl` is the one that measures a BINDING FORM rather than a `val`.** A `for` head, a `match`
arm, a `catch` and a destructuring `val` each put a name into the running scope from code of their
own, so a chunk holding any of them gave up its slots entirely -- which is most real code, since a
`for` over something is how most loops are written. The other four are all `val` and `var` and cannot
see that at all.

Each prints its answer and the milliseconds it took, so a run that computed the wrong thing cannot
be read as a fast one. **The answer is printed first and is asserted by `bench/expected.txt`** --
an optimisation that changes it has broken something.

Run them with `bench/run.sh <path-to-slate>`; it prints one line per benchmark.

## BUILD BOTH BINARIES AND ALTERNATE THEM. DO NOT COMPARE AGAINST A NUMBER WRITTEN DOWN EARLIER

**The control divides out drift WITHIN a run, not across hours.** A figure recorded in a memo last
night was taken on a machine in a state nobody can reconstruct -- another session's build, a browser,
a virtual machine -- so comparing today's run against it is not a controlled measurement, and
`globals.sl` cannot rescue it. What the control is actually for is the *pair*: run the old binary and
the new one back to back, and the control moving a percent or two is what says the machine held still
between them.

**So the method is: build the binary of the commit you are measuring against, and alternate.**
`./slate` is gitignored and the main worktree sits clean at dev, so `sysl build .` there costs
nothing but time, and `bench/run.sh` takes a path for exactly this reason. Run the pair twice; a
change worth reporting shows up in both.

B2 is the worked example. `loops` fell 68% in both pairs with the control moving 0.9% and 3.2%, and
`arith` -- which no part of the design predicted would move -- fell 10-17% in both, which is how a
real effect looks next to `strings` sitting 4% up in both and meaning nothing.
