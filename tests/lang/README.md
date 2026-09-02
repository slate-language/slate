# The language suite

**These tests are about slate, and every back end has to pass them.** They are ordinary slate `@test`
functions, so nothing in them knows which implementation is running — which is the whole point: the
compiler's own tests are written in sysl and drive the interpreter *in this process*, so however many
of them are green they say nothing whatever about `slate js`. That is how `indexOf` answering `-1`
where the interpreter answers `null`, a `toString` hook running inside a diagnostic, and an object
model that could not use an object as a key each reached a shipped release.

Run them the two ways:

    slate test tests/lang
    slate test --js tests/lang

`sysl test .` runs both and compares them, in `dev/slatelang/slate/tests_backends.sysl`.

## What belongs here

Anything about what a **running program** does: arithmetic, strings, arrays, objects, classes,
patterns, the object model, JSON, generators, `async`. Anything about **compiling** — the lexer, the
parser, the layout, what the checker refuses, the text the emitter writes, the driver, packages and
manifests — stays in sysl, where it can reach the compiler's own structures.

## What may not be used here

The suite runs inside an embedded JavaScript engine as well as in the interpreter, and an embedded
realm has **no file system, no environment, no command line and no way to stop the program**. So a
test here may not read a file, ask for the time, or reach the network.

**Timers work**, because `slate test --js` supplies them: the harness installs `setTimeout` and its
three companions into the realm before the program loads, and drives them from a **virtual clock**.
So `await sleep(50)` costs nothing, a suite of them costs nothing, and which timer runs first is
decided by its delay and its age rather than by how loaded the machine was. A promise from `resolve`
is fine too — the job queue drives it, and a continuation still runs before the next timer.

That bound is real and worth keeping: it is what makes the suite a statement about the language
rather than about a host.
