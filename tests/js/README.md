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

**THEY ARE RUN BY `sysl test .` NOW, THROUGH NODE**, which is what `tests_js_run.sysl` does: the
interpreter side runs in the test process the way every other driver here does, the emitted program
is started as a subprocess, and the two outputs are diffed. `Runnable` in that file is the list, and
a walk beside it fails when a program is added here and not to the list.

`p9.sl` is the one left out: its exit status is half of what it is about and it calls `exit`, which
in the test process would take the suite with it. It is still run by hand, as below.

**That does not settle the `quickjs-ng` question, which is about a different thing.** Making the
emitted code run under an engine *linked into the compiler* would let a test assert on it without
starting a process, and would make `qjs` — an engine with no file system and no `os` on the global —
part of the routine check rather than an occasional one. It moves the compiler floor to 0.0.93 and
puts `--include-path quickjs=…` on every `sysl test .`, so it remains the user's call.

Each program covers, in order: `wide.sl` is the fixture for a driver
test and the numbered ones cover arithmetic and printing; patterns, `match`,
labelled loops, closures and `try`/`catch`; classes, generators, `with`, defaults and spread
arguments; the `...` literals; the annotations, which are checked while a program runs; defaults
inside a pattern; the event loop; the file system and the environment; and a script's own arguments
and exit status.

**`p10.sl` is about the BUILTINS rather than about a construct**, which makes it the odd one here.
Every other program reaches a few builtins on the way to demonstrating something else; that one is
for the cases where JavaScript has an answer of its own and it is the wrong answer — a miss that is
`-1` rather than `null`, a `Number()` that trims and reads `""` as zero. It exists because `indexOf`
answered `-1` here for as long as this back end had one, and the golden tests in `tests_js.sysl`,
which pin the emitted TEXT, could not have seen it: the runtime those texts call into is a `raw"""`
block no expectation ever quotes.

**`p11.sl` is about a `type` being a VALUE**, and it earns its place because the two back ends hold
one entirely differently: the interpreter keeps a slot with the resolved pattern and a pointer to the
scope the declaration ran in, and the emitted program keeps the same pattern data `is` is emitted
against, captured lexically. Nothing about those two arrangements makes them agree — what a
`mismatch` report says is the only thing that does, so the program prints one for every shape a
pattern can be.

**`dom/` is a run of its own and needs jsdom** — see `dom/README.md`.

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
