# Packages

A package is named by an **unquoted** specifier:

```
import { mount } from lath              // the package's own `main`
import { domHost } from lath/dom        // one of its other modules
```

```
$ slate add github.com/slate-language/lath
```

## The manifest

A project or a package is a directory holding a **`package.sl`**, which is a slate object literal:

```
{
    name: "lath",
    version: "0.2.0",

    // What a bare `import ... from lath` reaches.
    main: "lath.slx",

    // The other modules a consumer may name, `lath/<key>`.
    modules: {
        dom: "dom.slx",
    },

    dependencies: {
        pg: { git: "github.com/slate-language/pg", version: "0.2.0" },
    },
}
```

The keys are `name`, `version`, `main`, `modules` and `dependencies`, and nothing else — an unknown one is
named. `name` and `version` are required; a dependency takes `git` and `version`, both required. Comments
are `//`, as everywhere else, which is most of why the format is slate's rather than JSON's.

**The format is slate's own syntax because slate's value model already is the config model** — null,
booleans, two kinds of number, strings, arrays and records, and nothing else. What decided it is not the
grammar: a manifest gets a **span and a report**, so a file that is wrong is answered with the same
source-quoting, caret-drawing diagnostic a program that is wrong gets.

**The file is parsed and never run**, and that is the whole design. A resolver working out what to fetch
is reading a file that arrived *with* the thing it is deciding whether to fetch; a manifest that ran would
make that a code-execution step. So the reader is a restriction pass over an ordinary slate expression:

- **A lambda, a call, a name and an operator are each refused by what they are** — "the name `b`", "a
  call", "a `+` between two things" — rather than as "not a literal", which is true of all of them and
  names none.
- **`-` in front of a numeric literal is allowed**, the lexer having no signed literal.
- **A key is a name or a string**, so the manifest syntax is a superset of JSON's.
- **A repeated key is refused** rather than resolved. First-wins and last-wins both silently discard
  something a person wrote.
- **The walk carries on after a refusal**, so a manifest with three mistakes reports three.

## What a package exposes

**Its `main`, and whatever its own manifest lists under `modules`** — which is what the slash names.

It is a list rather than a search. Resolving `lath/dom` by trying `dom.slx` and then `dom.sl` would make
every private helper in every package importable by accident, and would turn a renamed file into a broken
consumer with no way for the author to have said otherwise.

**A package's entry file is its own manifest's `main`.** That is optional for a project, which may simply
be run by naming a file, and **required for anything imported** — there being nothing else that says which
of a package's files is the package.

## Where things are

**The project is found by walking up from the entry file**, so a program works wherever it sits and
wherever it is run from. **A file under no project is not an error**: a single file that imports nothing is
a perfectly good slate program.

**The cache is `$HOME/.slate/pkg`**, overridable by `SLATE_CACHE`.

## `slate.sum`

`slate.sum` records what was fetched. **The hash is over the extracted tree, not over the download**, so
it is a statement about the code a build actually compiled rather than about one particular archive of it.
