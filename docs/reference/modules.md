# Modules

**A file is a module.** What another file can see is what it writes `export` in front of:

```slate
export val greeting = "hello"

export double(x) = x * 2

secret() = "no other file can reach this"

print(greeting, double(21), secret())
```

```output
hello 42 no other file can reach this
```

and a file takes what it needs by name, or takes the whole module under one:

```slate
import { double, greeting as hi } from "./util.sl"
import * as util from "./util.sl"

print(hi, double(21), util.shout("go"))
```

`export` goes in front of a `val`, a `var`, a definition, a `type`, a `class` or a `data`. A `type`,
`class` or `data` crosses as **both halves at once** — the value the name binds and the declaration the
compiler resolves.

## The three kinds of specifier

```slate
import { helper } from "./util.sl"      // a quoted path  -- a file
import { mount } from lath              // a bare word    -- a package
import { domHost } from lath/dom        // ... and one of that package's other modules
import { date, now } from slate:time    // slate:name     -- one of slate's own
```

**A path is relative to the file the import is written in**, so a directory of files that import each
other works wherever the program is run from.

**A bare `util.sl` is refused rather than guessed at**: an unquoted specifier is how a package is named,
and a language that resolved it as a file could not tell the two apart. The two are different syntax
rather than two readings of one string, which is further from node's rule than a `./` prefix would have
been and is the point — nothing already written changes meaning, and no reader has to work out whether a
leading `./` was optional.

See [Packages](packages.md) for what a bare name resolves to, and [the library](../library/README.md)
for the `slate:` modules.

## Imports are resolved before anything runs

**The machine never sees an import.** That is not a preference: slate's file surface is promise-shaped,
so an import resolved at run time would need either a blocking read carved out as a special case or an
`import` that answers a promise — and the second forces top-level `await`, which slate refuses, on every
program that imports anything at all.

What it costs is that **a path cannot be computed**, which is the same bargain sysl takes and is what
makes the set of files a program is made of knowable by reading it.

## A module is an object

So there is no new kind of value and nothing new for the collector to trace — `util.double` is the field
selection a program writes for itself.

It follows that **a module's exports are a snapshot** taken when its file finishes: an `export var` the
module changes afterwards is not seen changing from outside, which is where this parts company with
TypeScript's live bindings.

## What is refused, and when

- **A circle of imports**, with the chain named. node allows one and initialises half a module, which is
  a famous source of confusion; refusing can be relaxed later, and half-built modules cannot be
  un-shipped.
- **Asking for a name a file does not export** — before the program runs, and the message says what the
  file *does* export. Left to run time it would arrive as an absent field, and the message would be about
  a name bound to nothing: true, and about the wrong thing.
- **A name nothing has bound**, likewise before it runs.

**Every complaint is drawn against the file it is about.** A fault carries the file its span belongs to
rather than looking one up when it is reported, because a signal outlives the statement that raised it.
