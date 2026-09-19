---
title: Modules
weight: 110
---

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

## Importing a file that is not slate

**A quoted path naming anything but `.sl` or `.slx` is an asset, and one name takes the whole of it as
a string:**

```slate
import styles from "./button.css"
import template from "./welcome.html"

print(styles.length)
```

**The file is read while the program is compiled and travels inside it**, so nothing has to sit beside
the binary at run time and nothing is read twice — six files importing one stylesheet is one string.
It is the same on both back ends: under `slate js` the text is written into the emitted program, byte
for byte.

**The extension decides, never what the writer meant.** `"./util.sl"` is a module and `"./button.css"`
is an asset, and each is refused in the other's form:

```slate
import { helper } from "./styles.css"
```

```error
is not slate source, so there are no names in it to take
```

and a bare name asked of slate source says the same thing the other way round — **slate has no
default export**, and a file that does have names in it is imported by naming them.

**A package's assets are the package's own.** A `.css` shipped beside a `.slx` is imported by that
file, relatively, and handed on as an ordinary exported value — so nothing about the
[package](packages.md) system had to learn what an asset is.

**Two things are refused, both before the program runs.** A file that is not there is named beside the
file that asked for it. And a file that is **not UTF-8 text** is refused rather than mangled: slate has
one text type, so there is no value a PNG could arrive as, and a program that wants bytes wants
[`readBytes`](../library/fs.md) — which reads them while the program runs, where their size is not the
program's size.

## Imports are resolved before anything runs

**The machine never sees an import.** That is not a preference: slate's file surface is promise-shaped,
so an import resolved at run time would need either a blocking read carved out as a special case or an
`import` that answers a promise — and the second would make every program that imports anything at all
wait for it, which is a cost paid by every file rather than by the ones that wanted to wait.

What it costs is that **a path cannot be computed**, which is the same bargain sysl takes and is what
makes the set of files a program is made of knowable by reading it.

## A file's top level is declarations and effects

**A declaration says what a name is; an effect is the file doing something.** A definition, a `class`, a
`data`, a `type`, an `external` and an `import` are declarations. Everything else at the top level is an
effect: a `val` or a `var` binding, an expression, a `for`, an `if`, a `match`, a top-level `await`.

**A program runs exactly as it reads** — the split changes nothing about that. What it is for is the
**entry file**, and one machine in particular: an actor's VM, or a host embedding slate, runs every module
the program **imports** in full, exactly as an importer runs it, and runs only the *declarations* of the
entry file. So it has every definition and every class the program declares, and none of what the program
itself does — nothing of the entry file is printed, opened or armed there.

**A module is instantiated once per such machine.** Its constants are bound again, its tables are built
again and its own top-level effects happen again — in that machine and nowhere else. So module-level state
is **per actor**: a `Map` the main program filled is empty inside an actor until the actor fills its own,
and neither sees the other's. State that is meant to be shared belongs in one actor that owns it, never at
a module's top level.

A method may name a top-level `val` **of the entry file**, and that stays an ordinary program: the name is
looked up when the method is **called**, not when the class is declared. In such a machine nothing is bound
to it, so reaching it faults — and the fault says so, rather than only that the name is not defined:

```
`maxItems` is not defined -- the entry file's top level is not run inside an actor, and `maxItems`
is bound there. Put it in a module the actor imports, or in the actor's own fields.
```

The entry module's exports are all there in such a machine; the ones an effect would have bound are `null`.

What such a machine cannot load at all is a **declaration in the entry file whose value needs an effect's
binding** — a class field written `val defaults = Defaults`, where `Defaults` is a top-level `val`. The
initialiser is worked out where the class stands, so loading the declarations alone stops there, naming the
name. State a class depends on belongs in its own fields, which is also what lets it travel to an actor.

**A `spawn` at a module's top level is refused**, naming the module: the actor it started would run that
module, which would spawn again, without end.

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
