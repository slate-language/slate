---
title: slate
weight: 0
summary: A small indentation-structured, garbage-collected language with a gradual checker, `async`/`await` on a real event loop, and a JavaScript back end. One program, two hosts.
---

# The slate documentation

Four sections, and the split is between what the compiler enforces, what ships beside it, and what
somebody else has written.

| | |
|---|---|
| [Getting started](getting-started/) | install it, write a program, run its tests, compile it to JavaScript |
| [A tour for JavaScript and TypeScript people](tour-for-js/) | only the differences, and the reason for each |
| [Language reference](reference/) | every construct written down once, in its own place, with the rules complete |
| [The library](library/) | what a program has without writing it: the globals, and the `slate:` modules |
| [The packages](packages/) | what is written in slate today — a server, a client, a framework |

The [README](https://github.com/slate-language/slate) on the repository is the shorter thing: what
slate is, how to install it, and enough of a taste to decide whether to read further.

## What these pages are for

A reference answers the question you actually have. What may follow `for`? Which of `sort` and
`sorted` changes the array? What exactly does `?.` guard? Where does a default parameter's expression
run? Those are lookups, and prose that reads well start to finish answers them only by accident.

**Where a rule exists for a reason, the reason is here too.** A page that lists behaviour and stops
tells you what to type and leaves you unable to predict anything you have not looked up yet. slate's
rules lean on one another — the refusal to store absence decides what a default parameter is, which
decides what an arity complaint can say — so the connections are written down where they matter.

**Every program on these pages is meant to run.** Where a page shows a refusal, the sentence is the
one the compiler really prints.

## And they are run, which is why they can be trusted

**A fenced block on these pages is not a picture of a program — it is the program.** slate's own test
suite walks every page here and runs what it finds:

- a `slate` block with an **`output`** block under it is run, and what it prints is compared;
- a `slate` block with an **`error`** block under it is run, required to fail, and the diagnostic
  required to contain that text;
- a `slate` block with neither is a fragment, quoted for its shape.

So a page cannot drift from the compiler without failing the build, and the counts are written down
per page so a block that quietly loses its claim shows up as a page whose runnable count fell.
Writing these pages that way found five claims that were not true, none of which would have been
caught by reading.
