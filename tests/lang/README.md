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

`slate test --js` compiles the whole directory into **one** JavaScript program and runs it under
**node**, which is the host slate programs actually run on. Timers, promises, the file system and the
clock are node's own there, so a test here may use them.

What a test here may **not** rely on is anything the JavaScript back end has not built yet —
`slate:net`, `slate:crypto` and `slate:time` among them. A program reaching one of those is told so
rather than failing as an undefined name, and `js_rt_host.sysl`'s `OWED` list is the inventory.
