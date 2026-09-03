# The slate documentation

Two sections, and the split is between what the compiler enforces and what ships beside it.

- **[reference/](reference/)** — the language. Every construct written down once, in its own place,
  with the rules complete.
- **[library/](library/)** — what a program has without writing it: the globals, and the fourteen
  `slate:` modules.

The [README](../README.md) at the root is the shorter thing: what slate is, how to install it, and
enough of a taste to decide whether to read further.

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
