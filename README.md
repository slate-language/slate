<p align="center">
  <img src="https://slatelang.dev/slate-wordmark.svg" alt="slate" width="300">
</p>

<p align="center">
  <a href="https://github.com/slate-language/slate/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/slate-language/slate?label=release&color=4a5568"></a>
  <a href="https://github.com/slate-language/homebrew-tap"><img alt="Homebrew" src="https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fslate-language%2Fhomebrew-tap%2Fmain%2FFormula%2Fslate.rb&search=version%20%22(%5B%5E%22%5D%2B)%22&replace=%241&label=homebrew&color=fbb040"></a>
  <a href="https://github.com/slate-language/slate/actions/workflows/docs.yml"><img alt="Docs" src="https://github.com/slate-language/slate/actions/workflows/docs.yml/badge.svg?branch=stable"></a>
  <a href="https://github.com/slate-language/slate/commits/dev"><img alt="Last Commit" src="https://img.shields.io/github/last-commit/slate-language/slate/dev"></a>
  <img alt="License" src="https://img.shields.io/github/license/slate-language/slate">
  <a href="https://sysl.sh"><img alt="sysl Version" src="https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fslate-language%2Fslate%2Fstable%2Fpackage.hocon&search=sysl%20%3D%20%22(%5B%5E%22%5D%2B)%22&replace=%241&label=sysl&color=blue"></a>
</p>

A small indentation-structured, garbage-collected language, written in [sysl](https://sysl.sh).

Dynamically typed with a gradual checker, `async`/`await` on a real event loop, generators, modules,
pattern matching, classes over prototypes, algebraic data types, and a package manager. It is aimed first
at what an API server needs — HTTP over node's own llhttp, HTTP/2 over nghttp2, TCP, TLS, a file system,
processes, regular expressions and JSON.

**It also compiles to JavaScript**, so the same program runs under the interpreter, under node or quickjs,
and — with [dom](https://github.com/slate-language/dom) and
[lath](https://github.com/slate-language/lath), the React-shaped framework written in slate — in a
browser. `slate js app.slx -o app.js` writes one self-contained file: the runtime,
the framework and the program, with no bundler and nothing to install.

**The documentation is at [slatelang.dev](https://slatelang.dev)**, built from
[`docs/`](docs/) in this repository: [getting started](docs/getting-started/), a
[tour for JavaScript and TypeScript people](docs/tour-for-js/), a
[language reference](docs/reference/) and a [library reference](docs/library/).

## Installing

On macOS, Apple silicon:

```
brew tap slate-language/tap
brew install slate
```

On Linux, x86_64 or arm64, from the tarball on the [latest release](https://github.com/slate-language/slate/releases/latest):

```
curl -LO https://github.com/slate-language/slate/releases/latest/download/slate-linux-x86_64.tar.gz
sudo tar -xzf slate-linux-x86_64.tar.gz -C /usr/local
sudo apt-get install libssl3t64 libsqlite3-0 libbrotli1 libwebp7
slate --version
```

The asset is named for the release — `slate-<version>-linux-x86_64.tar.gz`, or `-linux-arm64` — and it
unpacks into a prefix, so `bin/slate` lands wherever you point `-C`.

Those four packages are the whole of what the binary needs at run time. Redis, libuv, LMDB, HTTP/2,
Zstandard and PCRE2 are **linked in**, so nothing has to be installed for them and no version of them has
to match. On Ubuntu 22.04 the OpenSSL package is spelled `libssl3` rather than `libssl3t64`, that rename
having come with 24.04's `time_t` transition; everything else is named the same everywhere.

The build is made on Ubuntu 22.04, so it wants **glibc 2.35 or newer** — Ubuntu 22.04, Debian 12 and
everything after them. Each release says the floor it actually achieved, and every release is unpacked and
run on Ubuntu 24.04, 26.04 and Debian 12 before it is published.

Anywhere else, build it from source — a clone and one command, given [sysl](https://sysl.sh) installed.

## Running it

```
slate hello.sl                       run a program
slate hello.sl one two three         ... and give it arguments
slate test .                         run every `@test` in a file or a directory
slate test --js .                    ... in the JavaScript engine instead
slate js hello.sl -o hello.js        the same program, as JavaScript
slate install github.com/owner/pkg   install a package (`add` is an alias)
slate --version                      which slate this is
slate --help                         the whole list
```

From a clone, with no `slate` on the path yet:

```
sysl test .
sysl run . -- examples/tour.sl
```

## A taste

```
val name = "slate"

double(x) = x * 2

grade(mark)
    if mark >= 90
        "A"
    elif mark >= 80
        "B"
    else
        "C"

counter()
    var count = 0

    bump()
        count = count + 1
        count

    bump

val c = counter()

print(c(), c(), c())            // 1 2 3
```

`match` is postfix — a transformation of the thing to its left. Patterns test literals, shapes and
alternatives, and a guard runs after the pattern has bound:

```
classify(v)
    v match
        { kind: "point", at: [0, 0] } -> "origin"
        { kind: "point", at: [x, y] } if x == y -> "diagonal"
        [first, ...rest] -> "a list starting " + string(first)
        "sat" | "sun" -> "a weekend"
        n @ number if n < 0 -> "a negative number"
        _ -> "something else"
```

A type is a shape with a name, and it is not erased — one declaration serves both the pattern and the check
at a boundary:

```
type Note = { title: string, pinned?: boolean }

Note.test(v)
Note.mismatch(v)                // every reason, with a path to each

save(n: Note) -> string = n.title
```

Anything may be annotated and nothing has to be. A type is written inline wherever one is wanted — a
function type is spelled the way the lambda is, and a definition may be generic over one:

```
val tags: array of string = ["reading"]
var count: integer = 0

apply(f: integer -> integer) -> integer = f(1)
handle(req: Authed & Bodied, done: (string, integer) -> boolean) = done(req.body, req.user.id)

first[T](xs: array of T) -> T = xs[0]
type Pair[A, B] = { first: A, second: B }
```

An annotated `var` is TypeScript's `let`: the declared type is what the name holds, and every assignment
is checked against it.

An `async` function answers a promise, and a `catch` reaches across an `await`:

```
async main()
    val a = work("a", 8, 3)
    val b = work("b", 20, 2)

    print("started both")
    print(await a, await b)

main()
```

An API server is a handler and a router:

```
import { serve, router, files } from slate:http

val app = router()

app.get("/notes/:id", req -> find(req.params.id))
app.post("/notes", req -> create(req.body))
app.any("/*rest", files("public"))

serve(3000, app)
```

## Writing a script

A `.sl` file with a `#!` line is a command. slate skips that line — it belongs to the kernel, not to the
language — and everything after the program's name on the command line belongs to the program:

```
#!/usr/bin/env slate

import { args, exit } from slate:process

if args.length == 0
    print("usage: greet <name>...")
    exit(2)

for name in args
    print("Hello, " + name + "!")
```

```
$ chmod +x greet.sl
$ ./greet.sl world slate
Hello, world!
Hello, slate!
```

## Writing a page

`slate js` reads the same tree a second time and writes JavaScript, so a slate program runs under node,
under quickjs, or in a browser. The last of those is what [dom](https://github.com/slate-language/dom)
and [lath](https://github.com/slate-language/lath) are for — React's model *and* React's mechanism, written in
slate, over JSX-shaped elements the parser desugars into ordinary calls.

```
$ slate install github.com/slate-language/lath
```

```
import { createElement, Fragment, mount, useState } from lath
import { domHost } from lath/dom

Counter({ start = 0 }) =
    val [count, setCount] = useState(start)

    <div class="counter">
        <p>{count}</p>
        <button onClick={() -> setCount(count + 1)}>+1</button>
    </div>

mount(<Counter/>, domHost("#app"))
```

```
$ slate js counter.slx -o counter.js
```

Then a `<script src="counter.js">` beside a `<div id="app">`. **One self-contained file** — the runtime,
the framework and the program — so there is no bundler, no `node_modules`, and nothing to install.

## The tree

```
dev/slatelang/slate/
    tok.sysl        what the lexer answers with
    lex.sysl        bytes to tokens, with indentation as structure
    ast.sysl        the tree
    parse.sysl      statements, by recursive descent
    expr.sysl       expressions, by binding power
    pattern.sysl    patterns, and the arms of a `match`
    obj.sysl        the collected heap: the objects, their tracers, and the roots
    value.sysl      what a program computes with, and the scope chain
    table.sysl      the hash table an object is, and how a value is hashed
    code.sysl       the instruction set, and the unit a program compiles to
    compile.sysl    the tree to instructions
    vm.sysl         the machine
    event.sysl      the event loop, over libuv: timers, and what roots a callback
    async.sysl      promises, and the queue that resumes a suspended call
    runtime.sysl    equality, arithmetic, indexing, matching and calling
    shape.sysl      a declared type, as a value: `test`, `mismatch` and `name`
    builtin.sysl    the functions a program has without writing them
    stdlib.sysl     the modules slate brings with it, and what each one exports
    js.sysl         the same tree read a second time, as JavaScript
    tests_*.sysl    what all of it claims, run by `sysl test .`
examples/tour.sl    the language in one file
examples/match.sl   the patterns, in another
examples/script.sl  a `#!` script: its arguments and its exit status
examples/api.sl     what an API server writes every time
docs/               the language and library reference
```

The module is **`dev.slatelang.slate`**, reversed from the domain the way `sh.sysl.*` is reversed from
sysl.sh. A module in sysl *is* a directory, so the path on disk and the name in the source have to agree —
and since a hyphen cannot appear in a module path, the domain is `slatelang.dev` rather than the
`slate-lang.dev` that redirects to it.

## How it runs

A program is compiled to instructions and run on a stack machine, and the reason is worth stating because
it is the only one: **`await` has to suspend in the middle of an expression, and a tree-walker's state is
the host language's own call stack, which cannot be captured.**

A slate call pushes a frame onto an array rather than recursing in sysl, so a call chain of any depth is
one sysl frame, and a suspended call is a frame nobody is currently running. Calling an `async` function
starts a machine of its own — operand stack, frames, scope and the promise it will settle — and `await`
sets that whole machine aside into a table the collector roots.

**Values are traced, not reference counted, because slate makes a cycle on every named function**: binding
a closure into the very scope that closure captured is a back-edge nothing declared, so `weak` cannot help.

`sh.sysl.parsing` does the scanner tier — spans, the byte cursor, literal reading, the diagnostic renderer,
the binding-power loop, and the layout pass.

## What is not here yet

A literate `.lsl` form, a raw string literal, a name resolver for `connect`, Unicode case conversion, and a
standard library beyond the builtins. On the object side: `super`, and a check that a proto satisfies a
`type` when it is attached to an object literal by hand.

In the JavaScript back end: `run`, `slate:redis`, `slate:nghttp2`, and the
servers written over them — `slate:ws` has its **client** there, over the host's own `WebSocket`, and
cannot have its server, a browser being unable to listen. Each one is a name that
says *"not in the JavaScript back end yet"* rather than a name that is not there. `slate:time` is whole
there now, except for `abbrev` and `isDST`; so is `slate:crypto` — Argon2id included, over node's own
`crypto.argon2` — except for the RSA and ECDSA half of JWS, and except that a browser has no Argon2 at all; so is `slate:regex`, whose patterns are translated into `RegExp` and which refuses the handful
of PCRE2 constructs a browser has nothing to mean; so is `slate:gzip`, over the host's own
`CompressionStream`; and so is `fetch`, over the host's own, except that `trust` refuses and the
redirect rule is the host's — all of them things a JavaScript host genuinely does or does not have, and
`docs/reference/javascript.md` measures why. **`slate:brotli` is the clearest of the second kind**: no
browser has a brotli encoder, so it refuses there naming brotli and pointing at `slate:gzip`.
**`slate:image` is that case reached by two different roads**: node has no image support in its standard
library at all, and a browser's is asynchronous where these six names answer on the spot — so images are
a server's job and the refusal says so.
**`slate:sqlite` is the other way round**: node has carried `node:sqlite` since 22.5, so the module is
whole there over node's own copy of SQLite, and it is a browser alone that has nothing for it to be.

**`defer` is deliberately not here.** It earns its place in Go and in sysl because neither collects: a
function that acquires something has to release it on every exit path. slate has a tracing collector, so
memory needs no cleanup at all, and its external resources are a timer, which `clearTimeout` closes; a
file, which no program ever holds open; and a socket, which a program does hold and does close. That last
one is the case worth watching — but `defer` would not be the answer to it either, since a socket is closed
from a callback far away from where it was opened, and that is precisely where a scope-based release does
not reach.

## Licence

ISC. See [LICENSE](LICENSE).
