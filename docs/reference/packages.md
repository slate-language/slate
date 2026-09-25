---
title: Packages
weight: 160
---

# Packages

A package is named by an **unquoted** specifier:

```slate
import { mount } from lath              // the package's own `main`
import { domHost } from lath/dom        // one of its other modules
```

```
$ slate install github.com/slate-language/lath
```

## The manifest

A project or a package is a directory holding a **`package.sl`**, which is a slate object literal:

```slate
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

    // What this package's own tests and examples need. A consumer never resolves these.
    devDependencies: {
        logger: { git: "github.com/slate-language/logger", version: "0.1.0" },
    },
}
```

The keys are `name`, `version`, `main`, `description`, `homepage`, `license`, `modules`, `dependencies`,
`devDependencies` and `scripts`, and nothing else — an unknown one is named. `name` and `version` are
required; a dependency takes `git` and `version`, both required. `description`, `homepage` and `license`
are what `slate brew` writes into a formula (see [A Homebrew formula](#a-homebrew-formula)), and nothing
else reads them. Comments are `//`, as everywhere else, which is most of why the format is slate's rather than
JSON's.

**`devDependencies` differs from `dependencies` in who resolves it and in nothing else.** It is fetched,
hashed and pinned in `slate.sum` exactly as any other dependency when it is *your* project being built —
and a package you depend on has its own second section skipped, however deep it sits. So a package's suite
may reach for whatever it likes without every consumer paying for it.

**A package is in one section or the other**, and both `slate install` and the manifest reader refuse a name
in both: two packages cannot share an import name, and one package cannot be in two places. A file
written by hand that names one twice is a file saying two contradictory things, and it is answered with a
caret rather than resolved twice.

`slate deps` marks the ones a consumer would not get:

```
  parsing 0.4.0 (github.com/sysl-lang/parsing)
  logger 0.1.0 (github.com/slate-language/logger) -- dev
```

```
slate install --dev github.com/slate-language/logger
```

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

**A manifest may open with any number of `import` lines before its one object**, and the reader skips
every one of them without reading a word out of it — resolution, `slate install` and a dependency's own
manifest all still touch nothing of the machine; only `slate run` evaluates the imports for real, which
is what lets a script reach `slate:process` or one of the project's own dependencies.

## Scripts

A project may write a `scripts` block, and `slate run <name>` runs one of them:

```slate
{
    name: "board",
    version: "0.1.0",

    scripts: {
        // A function, called with the arguments that followed the script's name.
        greet: (args) -> print("hello " + (args[0] ?? "world")),

        // A first word ending in `.sl` names a slate program, run with the rest as its arguments.
        migrate: "scripts/migrate.sl --up",

        // Anything else is a command line, handed to a shell.
        up: "docker compose up -d",
    },
}
```

```
slate run              # every script, one per line
slate run up           # the command line
slate run greet ed     # the function, with ["ed"]
```

**The first whitespace-separated word decides which of the two string forms it is**, and nothing else
does. A path is taken relative to the manifest's own directory rather than to wherever `slate` was run,
so a script means the same thing from any subdirectory of the project.

**A file script is split on whitespace and no shell is involved** — there is no quoting and no
expansion, and anything typed after `slate run <name>` is appended as further arguments. A shell line
is given to `/bin/sh -c` as written, with those extra arguments appended singly quoted. There is no
`cmd /c` branch: slate has no Windows build today, and sysl offers no way to ask which operating
system this is.

**What a script leaves behind is what the shell hears**: a function answering an integer gives that
status and anything else gives 0, a fault or a rejected promise gives 1 with the ordinary
caret-drawing report, and a file or a command line gives whatever it exited with. An `async` script is
awaited, and the event loop then drains exactly as it does for a program.

**Nothing runs a script by itself.** `slate install`, `slate fetch`, `slate deps` and resolution read
every manifest they touch as *data* — the restriction pass above skips the `scripts` block rather than
reading it, so a function written there is recorded as nothing at all. **Only `slate run` evaluates a
manifest, and only ever the project's own**: a dependency's scripts are never read and never run, however
deep it sits.

**The `import` lines at the top of the file are what let a function script reach past `args`**, so a
script may run another program and answer what it left behind:

```slate
import { run } from slate:process

{
    name: "board",
    version: "0.1.0",

    scripts: {
        deploy: async (args) -> (await run("./deploy.sh", args)).status,
    },
}
```

`slate deps` and `slate install` still see only `dependencies` here, an import above the object being a
statement the restriction pass skips rather than a second kind of dependency.

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

## Shipping a program

**`slate bundle` writes a program and everything it imports as one file that runs as itself**, so what
is installed on another machine is that file and `slate`. It is loaded and checked first — a program the
check refuses is not bundled — and the bundle holds every file the program is made of: its own, the
assets it imports, and the files of every package it uses, at the versions the project resolved them
to. Nothing in it is fetched, looked up in a cache or read from a `package.sl` when it runs.

```
$ slate bundle src/main.sl -o greet
$ ./greet world
Hello, world!
```

The file opens with `#!/usr/bin/env slate` and is made executable, so it is a command; with no `-o` it
goes to standard output. It is text, and its head is readable:

```
#!/usr/bin/env slate
#slate bundle 1
file 100 src/main.sl
file 52 github.com/example/greet/@v2.0.0/greet.sl
import 0 1 ./util.sl
package 1 greet
end
```

**A diagnostic from a bundled program names the file it was written in** — `src/main.sl:12`, not the
bundle and a line into the middle of it — because the files keep their own text and their own names.
A project's files are named under the project and a package's under the cache, so nothing about the
machine that made the bundle is in it.

A bundle is what a Homebrew formula installs: it depends on `slate` and puts the one file in `bin/`.

## A Homebrew formula

**`slate brew` writes a project's bundle and the formula that installs it, together.** It bundles the
manifest's `main` exactly as `slate bundle` does, takes the SHA-256 of those bytes, and writes both files
beside the manifest — or under `-o <directory>`:

```
$ slate brew
wrote greet (sha256 3b2a…)
wrote greet.rb
```

The formula is short, because a bundle needs nothing from the machine but `slate`:

```ruby
class Greet < Formula
  desc "Says hello"
  homepage "https://github.com/example/greet"
  url "https://github.com/example/greet/releases/download/v2.0.0/greet"
  version "2.0.0"
  sha256 "3b2a…"
  license "ISC"

  depends_on "slate-language/tap/slate"

  def install
    bin.install "greet"
  end

  test do
    assert_predicate bin/"greet", :executable?
  end
end
```

The manifest supplies every field: `name`, `version`, `description`, `homepage` and `license`. The URL is
the GitHub release asset, `<homepage>/releases/download/v<version>/<name>`, so **`homepage` is the
repository and is required** — a formula cannot be written without somewhere to fetch from — as is `main`.
`description` and `license` are optional and left out of the formula where absent.

**The hash is taken from the bytes that were written and not from a file read back later**, which is
why the two are one command: a formula made afterwards by hand can name the wrong file, and this one
cannot. What remains is the release itself — attach the bundle to a `v<version>` release of the repository,
put the formula in a tap, and `brew install <tap>/<name>` fetches the one file and links it.

## `slate.sum`

`slate.sum` records what was fetched. **The hash is over the extracted tree, not over the download**, so
it is a statement about the code a build actually compiled rather than about one particular archive of it.

**It records the WHOLE graph and not the packages the project happens to name.** A package reached
through another one is compiled exactly as one the manifest wrote, so it is pinned exactly as one.
That takes saying because a package's own dependencies are written in its own manifest, which arrives
*with* the package: `slate install` and `slate fetch` resolve, fetch, and then resolve again — until a
round arrives with nothing new — because the first pass over an empty cache can only see what the
project itself declared.
