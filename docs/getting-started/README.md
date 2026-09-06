---
title: Getting started
weight: 10
summary: Install slate, write a program, run its tests, and compile it to JavaScript — in about ten minutes.
---

# Getting started

Install it, write a program, run its tests, and compile the same program to JavaScript.

## Installing

**Homebrew, and the tap is a step of its own:**

```
brew tap slate-language/tap
brew install slate
slate --version
```

`slate-language/tap` is the repository the formula lives in, and tapping it is what tells Homebrew
where to look; after that slate is an ordinary formula, so **`brew upgrade slate` is how a new
version arrives**.

**Homebrew asks you to trust a tap the first time it loads a formula from one.** If the install is
refused with *"Refusing to load formula … from untrusted tap"*, the answer is one command:

```
brew trust slate-language/tap
```

**macOS on Apple silicon is the only build there is today, and that is worth saying plainly rather
than finding out.** sysl — the language slate is written in — does not cross-compile, so a Linux
binary has to be built on Linux and nothing does that yet; the formula names the one platform it has
rather than offering an install that cannot run.

The tarball attached to each [GitHub release](https://github.com/slate-language/slate/releases) is
the fallback where brew is not wanted — it is `bin/slate` and nothing beside it, the standard modules
being compiled into the executable. Anywhere else, build it from source, which is a clone and one
command given [sysl](https://sysl.sh) installed:

```
git clone https://github.com/slate-language/slate
cd slate
sysl build .
```

## A first program

A slate program is a `.sl` file. Put this in `hello.sl`:

```slate
val name = "world"

print("Hello, " + name + "!")
```

```output
Hello, world!
```

and run it:

```
slate hello.sl
```

**There is no main function and no ceremony.** The file is the program, its statements run top to
bottom, and `print` is in scope with nothing imported.

**A file with a `#!` line on its first byte is a command.** slate skips that line — it belongs to the
kernel, not to the language — and everything after the program's name on the command line belongs to
the program:

```slate
import { args, exit } from slate:process

if args.length == 0
    print("usage: greet <name>...")
    exit(2)

for name in args
    print("Hello, " + name + "!")
```

```output
usage: greet <name>...
```

With a `#!/usr/bin/env slate` on the first line and the execute bit set, that file *is* `greet`:

```
$ chmod +x greet.sl
$ ./greet.sl world slate
Hello, world!
Hello, slate!
```

## Enough of the language to read the rest

**Indentation is structure**, as it is in Python. A block is opened by indenting under the line that
introduces it and closed by returning to the outer column.

**A definition is a name, a parameter list and a body**, and the body may be an expression after `=`
or an indented block:

```slate
double(x) = x * 2

grade(mark)
    if mark >= 90
        "A"
    elif mark >= 80
        "B"
    else
        "C"

print(double(21), grade(95), grade(83))
```

```output
42 A B
```

**A block's value is its last expression**, so `grade` needs no `return` — though `return` exists for
leaving early.

**`val` binds and `var` re-binds.** A closure captures the variable rather than a copy of it, which is
what makes a counter a counter:

```slate
counter()
    var count = 0

    bump()
        count = count + 1
        count

    bump

val c = counter()

print(c(), c(), c())
```

```output
1 2 3
```

**`match` is postfix** — a transformation of the thing to its left. Patterns test literals, shapes and
alternatives, and a guard runs after the pattern has bound:

```slate
classify(v) = v match
    { kind: "point", at: [0, 0] } -> "origin"
    { kind: "point", at: [x, y] } if x == y -> "diagonal"
    [first, ...rest] -> "a list starting " + string(first)
    "sat" | "sun" -> "a weekend"
    n @ number if n < 0 -> "a negative number"
    _ -> "something else"

print(classify({ kind: "point", at: [0, 0] }))
print(classify([9, 8, 7]))
print(classify("sun"))
print(classify(-4))
```

```output
origin
a list starting 9
a weekend
a negative number
```

**A type is a shape with a name, and it is not erased.** One declaration serves both the pattern and
the check at a boundary:

```slate
type Note = { title: string, pinned?: boolean }

print({ title: "Milk" } is Note)
print(Note.test({ title: 7 }))
print(Note.mismatch({ title: 7 }))
```

```output
true
false
[{path: "title", wanted: "string", got: "integer"}]
```

**An `async` function answers a promise, and `await` waits for one.** There is a real event loop
underneath — libuv, the one node uses:

```slate
import { readFile } from slate:fs

async main()
    val r = await readFile("/no/such/file")

    print(if r.ok then "read it" else "no such file")

main()
```

```output
no such file
```

**That last program is worth reading twice.** A file that is not there is not a fault — it is an
answer, `{ ok: false, error: … }`, which the caller has to look at. See
[Faults](../reference/faults.md) for the rule that decides which failures work this way.

## Tests

**A test is a function marked `@test`, and it lives beside what it tests.** There is no test framework
to install and no file naming convention to follow:

```slate
add(a, b) = a + b

@test
addsTwoNumbers()
    assertEq(add(2, 3), 5)

print("compiled")
```

```output
compiled
```

Run every test in a file or a directory:

```
slate test .
```

`assert`, `assertEq`, `assertNe` and `assertFails` are the assertions, and
[Tests](../reference/tests.md) has the whole list. A test that is `async` is awaited.

## The JavaScript back end

**`slate js` reads the same tree a second time and writes JavaScript**, so the program you just wrote
runs under node, under quickjs, or in a browser:

```
slate js hello.sl -o hello.js
node hello.js
```

**One self-contained file** — the runtime and the program — so there is no bundler, no
`node_modules`, and nothing to install beside it.

The same suite runs on the other host with one flag:

```
slate test --js .
```

**That is one suite and two engines, not two suites.** Where the two back ends genuinely differ — a
browser has no server socket, no host has a brotli encoder — the difference is written down in
[JavaScript](../reference/javascript.md) and the name refuses with a sentence saying which host lacks
what.

## Packages

```
slate add github.com/slate-language/lath
```

writes the dependency into `package.sl`, fetches it, and records the hash of the extracted tree in
`slate.sum`. **A package is imported by a bare word**, where a file is imported by a quoted path and
one of slate's own modules by `slate:name` — three syntaxes rather than two readings of one string,
so nothing already written changes meaning:

```slate
import { createElement, mount, useState } from lath
```

[The packages](../packages/) lists what is written in slate today —
a UI framework, an API server, a PostgreSQL client, a component library and a logger. [Packages](../reference/packages.md)
is the reference: the manifest, the cache, and what `slate.sum` guarantees.

## Where to go next

- **[A tour for JavaScript and TypeScript people](../tour-for-js/)** — what is different here, and why.
- **[The language reference](../reference/)** — every construct, written down once, in its own place.
- **[The library](../library/)** — what a program has without writing it.

**Every program on these pages is run by slate's own test suite**, and every refusal is quoted from
the diagnostic the compiler really prints. A page that drifts from the compiler fails the build.
