# The differential corpus

Each `p*.sl` here is a program whose output is **the same from the interpreter and from the
JavaScript back end**, and that is the whole of what they are for:

    slate p1.sl                  > want.txt
    slate js p1.sl -o p1.js
    qjs p1.js                    > got.txt
    diff want.txt got.txt

**node runs them too, and that is the point of the exercise rather than a side effect** — the same
file, no flags, and a one-liner where the file is not wanted:

    slate js p1.sl | node -

`p7.sl` needs an event loop, so under quickjs it needs `qjs --std p7.js`: quickjs keeps its timers
on `os` rather than on the global and `--std` is what puts `os` there. node has all four timers as
globals and needs nothing. Every other program in this directory runs under a bare `qjs`.

They are not run by `sysl test .`, because the suite has no JavaScript engine in it: running the
emitted code needs `sysl-lang/quickjs-ng` as a dependency of this repo, which moves the compiler
floor to 0.0.93 and puts `--include-path quickjs=…` on every test run. When that lands, these become
the differential suite and the diff above becomes an assertion.

Until then they are run by hand, and every one of them was: `wide.sl` is the fixture for a driver
test and the six numbered ones cover, in order, arithmetic and printing; patterns, `match`,
labelled loops, closures and `try`/`catch`; classes, generators, `with`, defaults and spread
arguments; the `...` literals; the annotations, which are checked while a program runs; defaults
inside a pattern; the event loop; the file system and the environment; and a script's own arguments
and exit status.

**`p8.sl` writes into `tests/js/scratch/` and takes it away again**, so that running it twice says
the same thing and running it leaves nothing behind — the directory is git-ignored for the run that
does not reach the end. It needs node: a file system is the one thing quickjs has none of that node
brings, and under `qjs` every call in it answers *"`existsSync` needs a file system, and this
JavaScript host has none"*.

**`p9.sl` is the one whose EXIT STATUS is part of the comparison, and it is the only one.** It is
slate as a scripting language — a `#!` line the lexer skips, `args`, and `exit(3)` — so a diff of the
output alone would miss half of what it is about:

    slate p9.sl one two three                    > want.txt ; echo $?
    slate js p9.sl -o p9.js && node p9.js one two three > got.txt ; echo $?

Both print eight identical lines and both leave with **3**; `qjs --std p9.js one two three` agrees
with them, taking its arguments off `scriptArgs` rather than off `process.argv`. It is also the one
program here that begins with a shebang, which is the point: the same bytes are a file the kernel can
start and a file both back ends read.

**`p7.sl` runs its phases one after another, and that is the test's own correctness rather than
slate's.** Two timers due at the same instant fire in an order neither loop promises, and a repeating
timer drifts by however long its callback took — an earlier draft asked both questions and the two
loops disagreed about both, which says nothing about either.

`mods/` holds the programs of **more than one file**, which are the same corpus with the same
command — `slate js mods/two.sl -o two.js` writes every module of the program into one file, so
nothing about running them differs.

- `lib.sl` is what the other three import: a value, a function, a type and one name it does not
  export.
- `two.sl` imports names from it, one of them under another name, and one of them a type.
- `star.sl` imports the module itself.
- `blames.sl` is the one worth keeping in mind, because it is why a marker in a program of several
  files carries the file as well as the line: it catches a fault raised in `faulty.sl` and prints
  the file and line the fault says it came from, then does the same for a fault of its own. Both
  answers have to be the file the code was written in rather than the file that called it.

**A fault that is not caught is the one thing these cannot compare**, which is why `p5.sl` catches
the ones it is about: the interpreter draws a caret diagram against the source and a JavaScript
engine throws, so the two disagree about the presentation of every fault while agreeing about its
sentence. What a program here compares is what a program *prints*.

`tests/mods/` is the interpreter's own module corpus and every program in it that runs without the
event loop agrees too, which is worth running after a change to the emitter — `main.sl`, `star.sl`,
`diamond.sl`, `uses_deep.sl`, `uses_types.sl`, `uses_menagerie.sl`, `uses_twice_exported.sl`,
`uses_reexport.sl`, `uses_counter.sl`, `uses_snapshot.sl` and `examples/modules.sl`.
