# slate

A small indentation-structured, garbage-collected language, written in [sysl](https://sysl.sh).

Dynamically typed with a gradual checker, `async`/`await` on a real event loop, generators, modules,
pattern matching, classes over prototypes, algebraic data types, and a package manager. It is aimed
first at what an API server needs — HTTP over node's own llhttp, TCP, TLS, a file system, processes,
regular expressions and JSON.

**It also compiles to JavaScript**, so the same program runs under the interpreter, under node or
quickjs, and — with `slate:dom` and [lath](https://github.com/slate-language/lath), the React-shaped
framework written in slate — in a browser.
`slate js app.slx -o app.js` writes one self-contained file: the runtime, the framework and the
program, with no bundler and nothing to install.

It began as a way of finding out what sysl is like to write a real front end in: a tree-walking
interpreter reaches for nearly everything a language has — recursive data through references,
payload-carrying enums, traits with associated types, generics over a container, closures that
outlive the frame that made them, and an error path carrying a position from the byte that caused it
to the sentence a person reads. It turned out to be a language worth having on its own, and that is
what it is built as now.

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
    show.sysl       the tree as `(+ 1 (* 2 3))`, for the tests
    stdlib.sysl     the modules slate brings with it, and what each one exports
    js.sysl         the same tree read a second time, as JavaScript
    js_rt.sysl      that program's runtime, carried as text
    js_rt_dom.sysl  `slate:dom` -- the one part that reaches outside the language
    tests_*.sysl    what all of it claims, run by `sysl test .`
    main.sysl       the driver: a path in, a report out
examples/tour.sl    the language in one file
examples/match.sl   the patterns, in another
examples/script.sl  a `#!` script: its arguments and its exit status
examples/api.sl     what an API server writes every time
```

The module is **`dev.slatelang.slate`**, reversed from the domain the way `sh.sysl.*` is reversed
from sysl.sh. A module in sysl *is* a directory, so the path on disk and the name in the source have
to agree — and since a hyphen cannot appear in a module path, the domain is `slatelang.dev` rather
than the `slate-lang.dev` that redirects to it.

`main.sysl` sits inside the module rather than importing it. That is only possible because of the
prefix: the executable is named for the package, so while the sources lived in a directory called
`slate/` the linker had a binary and a directory competing for `./slate`.

A slate program is a **`.sl`** file. A literate one — prose with the program in it, as sysl has for
`.lsysl` — will be **`.lsl`**, and is not built yet.

## Installing

```
brew tap slate-language/tap
brew install slate
```

macOS on Apple silicon is the only build there is so far: sysl does not cross-compile, so a Linux
binary has to be built on Linux and nothing does that yet. Everywhere else, build it from source —
which is a clone and one command, given [sysl](https://sysl.sh) installed.

## Running it

```
slate hello.sl                  run a program
slate hello.sl one two three    ... and give it arguments
slate test .                    run every `@test` in a file or a directory
slate js hello.sl -o hello.js   the same program, as JavaScript
```

From a clone, with no `slate` on the path yet:

```
sysl test .
sysl run . -- examples/tour.sl
```

## Writing a script

A `.sl` file with a `#!` line is a command. slate skips that line — it belongs to the kernel, not to
the language — and everything after the program's name on the command line belongs to the program.

```
#!/usr/bin/env slate

import { args, exit } from slate:process

if args.len() == 0
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

- **`args` is a value, not a call**, and it holds only what came after the program's name — so
  `args[0]` is the first thing a person typed and `args.len()` is how many they typed. That is where
  slate parts from C, node and Python, all three of which hand a program its whole command line and
  begin by skipping past themselves.
- **`exit(status)` stops the program and tells the shell what it came to.** Everything printed before
  it is still printed, a `try` between it and the top cannot swallow it, and a status outside 0–255 is
  refused rather than truncated — a shell keeps the low eight bits, so an unexamined `exit(256)` is a
  program that says it failed and is recorded as having succeeded.
- **slate reads no argument of its own after the program's name**, so a script's own options are safe
  to invent: there is no flag slate could add later that would take one away.
- Without an `exit`, a program that ran answers 0 and one that faulted answers 1. `slate` itself
  answers 2 when it could not work out what it was being asked to do, which a shell script can tell
  from your program failing.

`#!` is read at the very first byte of the file and nowhere else. `#` is not a comment in slate — a
comment is `//` — and this did not make it one.

## Writing a page

`slate js` reads the same tree a second time and writes JavaScript, so a slate program runs under
node, under quickjs, or in a browser. The last of those is what `slate:dom` and
[lath](https://github.com/slate-language/lath) are for — React's model *and* React's mechanism,
written in slate, over JSX-shaped elements the parser desugars into ordinary calls.

```
$ slate add github.com/slate-language/lath
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

Then a `<script src="counter.js">` beside a `<div id="app">`. **One self-contained file** — the
runtime, the framework and the program — so there is no bundler, no `node_modules`, and nothing to
install.

- **`class`, not `className`; `for`, not `htmlFor`.** React's spellings exist only because JSX
  compiles into a JavaScript object literal where those were reserved words. An attribute here is its
  own lexical context and can take the right name.
- **The host is behind an adapter, and there are two of them.** The same components render to markup
  beside `slate:http` — server-side rendering as a by-product rather than a project — and into the
  document in a browser. Nothing in the reconciler knows which.
- **A handler is given a record, not the event**: `{ type, value, checked, key, stop, prevent }`. A
  `MouseEvent` has no representation in slate, and inventing one would mean inventing a value that
  could not be printed, compared or stored.
- **`slate:dom` says so where there is no document.** Under the interpreter every one of its names
  faults with a sentence naming the command rather than the code, because the same program is correct
  in a browser and it is the command that is wrong.

**lath is a package rather than part of the language**, and deliberately so: a UI framework iterates
far faster than a compiler, and baking one in would tie every framework fix to a language release.
`slate-language/lath` has the counter, the framework and its own tests.

## The language

The syntax follows sysl's, which is itself Scala with some Python and Kotlin. `val` and `var`; no
keyword on a function, the shape being what identifies it; a block whose value is its trailing
expression, so `return` is for leaving early and nothing else; `if`/`elif`/`else` with an inline
`then` form; and `end` left as a soft word so a program may still use the name.

```
val name = "slate"
var n = 0

double(x) = x * 2

add(a, b)
    a + b

grade(mark)
    if mark >= 90
        "A"
    elif mark >= 80
        "B"
    else
        "C"

first_even(xs)
    for x in xs
        if x % 2 == 0
            return x
    null

counter()
    var count = 0
    bump()
        count = count + 1
        count
    bump

val c = counter()

print(c(), c(), c())            // 1 2 3

print([x -> x * 2, 21])
print({ name: "ada", born: 1815 }.name)
```

`match` is postfix, as in Scala and sysl — a transformation of the thing to its left. Patterns test
literals, shapes and alternatives, and a guard runs after the pattern has bound:

```
classify(v)
    v match
        { kind: "point", at: [0, 0] } -> "origin"
        { kind: "point", at: [x, y] } if x == y -> "diagonal"
        [first, ...rest] -> "a list starting " + string(first)
        "sat" | "sun" -> "a weekend"
        n @ num if n < 0 -> "a negative number"
        _ -> "something else"
```

**A bare name in a pattern tests for a kind where it names one, and binds otherwise** — `null`,
`boolean`, `integer`, `real`, `number`, `string`, `array`, `object`, `function`. That is sysl's own bare-name rule (a
bare identifier is a nullary-variant pattern when it names one of the scrutinee's variants), applied
to a scrutinee that is always a value: those words *are* the variants. So a type test needs no syntax
of its own, and `n @ pat` — again sysl's spelling — is how a program tests and names at once. None of
them is a keyword: `val int = 3` still works.

`number` is the one that is not a variant, being the union of `integer` and `real`. It earns its place
because the two are separate values, so a pattern guarding arithmetic would otherwise be written
twice. It is also what makes a broad guard safe: `n if n < 0` binds *anything*, so the guard
evaluates `[3, 4] < 0` and faults, where `n @ number if n < 0` cannot reach the guard with the wrong
kind.

An object pattern matches an object with *at least* those fields, because a record grows fields over
its life. `{ name }` is shorthand for `{ name: name }`, and `{ pinned? }` is a field the subject need
not have. No alternative of a `|` may bind a name, since it would be bound down one path and not the
other; `&` is its dual, binds tighter, and *may* bind, every part of an intersection running. A subject matching no arm is a runtime fault, as
Scala's `MatchError` is.

**Exhaustiveness is checked exactly where the value's shape was written down**, and nowhere else —
slate is dynamically typed, so for an unannotated subject the set of values a name may hold is not
known and nothing useful can be said. What `data` adds is a closed list of variants, so a `match` over
a subject annotated with one is checked against it and every variant left out is named. A class name
and a `data` variant may also be written with fields after them, taking the value apart in the same
breath as testing it — see **Classes** and **Data types** below.

It is dynamically typed. Values are `null`, booleans, integers, reals, strings, arrays, objects,
functions and promises. Arrays and objects are reference types and compare by their contents. Only `false` and
`null` are false — zero and the empty string are not, which is the rule Ruby and Lua take and the one
JavaScript and Python are most often criticised for.

`&&` and `||` short-circuit and answer the operand that decided, which is the one place slate's rule
is not sysl's: sysl's operands are `bool` and there is nothing else for it to give back.

### The shape of it

The syntax is sysl's, minus what a dynamically typed language with no pointers has no use for.

**A one-line body is a statement, not an expression**, which is the rule that makes the short forms
worth having: `if n > 2 then break`, `then return x`, `then continue`, and the same inside a `match`
arm. `do` introduces a one-line loop body — `while c do …`, `for x in xs do …`, `loop do …` — and
`end if` / `end while` / `end for` / `end loop` / `end <name>` close a block that has grown long
enough to want it. `end` stays a soft word, so a program may still call something `end`.

**Every loop is an expression, and `break` is what gives it a value.** A loop that finishes on its own
answers `null`, or whatever its `else` clause left:

```
find_first(xs, wanted)
    for i in 0..<len(xs) do
        if xs[i] == wanted then break i
    else
        -1
end find_first
```

That an `else`'s value *is* the loop's was checked against sysl rather than assumed. A label says
which loop a `break` leaves — `'search for a in …` then `break 'search [a, b]` — which is the only way
out of a nested one.

**Comparisons chain rather than associate**, so `0 <= n < 10` asks what it looks like it asks and `n`
is evaluated once. `is` puts a pattern where a condition is wanted — `v is number`, `v is not str`,
`v is 1 | 3 | 5` — using the same grammar a `match` arm does.

**Ranges are values**: `for i in 0..<n`, `xs[1..<3]`, `"hello"[..2]`, and an end left out is taken
from whatever the range is used on. `a..=b` is refused by name, since a reader arriving from Rust
writes it once.

Assignment has the compound forms `+= -= *= /= %=` and the bitwise `&= |= ^= <<= >>=`, and writes
several places at once with `a, b = b, a`. A compound form evaluates its place **once**, so
`xs[next()] += 1` calls `next` a single time. `++` and `--` step a name, a field or an element, prefix
or postfix. The bitwise operators are `| ^ & ~` and the shifts `<< >>`, which bind like a
multiplication rather than like C's.

`s"a ${b} c"` interpolates, `[v; n]` is an array of copies, `base with { f: v }` is a copy with a
field changed, and every comma list takes a trailing comma.

**A hole that is a single name needs no braces**, which is Scala's short form and covers most of
them: `s"$w by $h"` is `s"${w} by ${h}"`. It is identifier-only and stops at the end of the name, so
`$point.x` interpolates `point` and then reads `.x` as text — `${point.x}` says the other thing. `$$`
is a literal `$`, and a `$` that does not begin a name is just itself, so `s"costs 5$"` needs nothing
doing to it.

**A parameter may carry what it is when nobody gives one**, on a definition, a lambda, a method or a
class's `new`:

```
greet(name, greeting = "hello") = greeting + ", " + name

log(message, level = "info", at = now()) = ...
```

The default is worked out **at the call**, not where the function was written, so `f(xs = [])` gives
every call an array of its own — the mistake Python has spent thirty years explaining — and a default
may read the parameters to its left: `slice(xs, from, to = len(xs))`. A parameter that may be left out
has to come last, or leaving it out would slide every later argument one place left; the parser says
so where it is written. An arity complaint then names the range rather than only its upper end.

**A lambda's body may be a block, written where the lambda is passed.** A newline inside brackets
normally means nothing — that is what lets an argument list be split over lines — so a callback would
otherwise have to be lifted out and named before the call that wanted it:

```
each([1, 2, 3], x ->
    val doubled = x * 2
    print(x, doubled))
```

`->` and `match` are the two tokens that suspend that rule, and only where they end a line: an arrow
written mid-line would hand the block to whatever line came next. **A block lambda has to be the last
argument**, because its block runs to the end of its last line and a `,` arriving there has nothing
to mean. Every callback slate itself takes is last for that reason; `setTimeout(fn, ms)` keeps node's
order and so takes a one-line function.

### async and await

An `async` function answers a promise rather than a value, and `await` waits for one:

```
async work(name, ms, turns)
    var i = 0

    while i < turns
        await sleep(ms)
        print(name, "step", i)
        i = i + 1

    name + " finished"

async main()
    val a = work("a", 8, 3)
    val b = work("b", 20, 2)

    print("started both")
    print(await a)
    print(await b)
```

Everything above a function's first `await` runs before its caller sees the promise, and everything
below it runs after the caller has moved on — which is node's rule, and why `started both` prints
before either worker's first step. The two workers then interleave by their own clocks.

**`undefined` aside, `await` is the place slate departs from JavaScript least and on purpose.** A
settled promise still resumes through the queue rather than continuing in place, so what was
scheduled first runs first; `await` of a plain value answers it and still yields, so a program cannot
tell which of the two it was handed by watching what runs next.

**A failed promise raises where it was awaited.** A promise fails when the `async` function running
it faults; awaiting that promise raises the same fault in the awaiting function, so a chain of
`await`s carries a fault to whoever is waiting at the end of it — and a `catch` anywhere along that
chain stops it.

**And a failure nothing was waiting for is the program's failure**, reported against the line that
raised it. That is the one thing node gets wrong by default and warns about instead.

**A call whose promise was thrown away fails at once, and everything else is asked at the end.** The
question "was this handled?" usually cannot be answered when a promise fails — `val p = risky()` and
`await p` three lines later is ordinary, so a failed promise with nothing waiting on it may still be
awaited — and it is therefore asked once, after everything has settled. But a call written on a line
of its own, `main()`, was never given to anybody: there is no name for it and no line that could ever
await it, so its failure is final where it happens. That distinction is what makes the report reach a
*server*, which never settles and would otherwise hold the diagnostic for as long as the process
lived — a fault in a coroutine that looks, from outside, exactly like a hang.

`sleep(ms)` answers a promise for later; `resolve(v)` and `reject(message)` answer one that has
already settled. Top-level `await` is refused — the whole program would have to become a coroutine,
which is a real design and one to make on purpose.

### Handling a fault

Two forms of one thing. The postfix one is an expression, so it stands where a value is wanted:

```
val text = readFileSync(path) catch e -> ""

val port = toPort(argument) catch e ->
    print(s"${e.message}, so using the default")
    8080
```

and the block one is for a run of statements:

```
try
    setUp()
    run()
catch e
    print(s"${e.file}:${e.line} ${e.message}")
```

**A fault is an ordinary object** — `message`, `line` and `file` — for the same reason a module is
one: slate objects already sort, print, go in arrays and match against patterns, so there is nothing
here the rest of the language does not already do.

**`catch` works across an `await`.** A coroutine carries its handlers with it when it is set aside, so
a promise that fails minutes later still raises inside the `try` that was written around the `await`
rather than escaping to the scheduler.

**There is no `finally`, and no way to re-raise yet.** A `try` with nothing to handle the fault is
refused rather than allowed to swallow it silently.

**A fault in a callback is not caught by the call that scheduled it** — `try setTimeout(...)` guards
the scheduling and nothing else, because the callback runs from the loop long afterwards. That is
inherent rather than a gap: there is no statement of the program's left to attach it to.

### The file system

Ten builtins, on node's names, over the libuv binding's thread pool:

```
async main()
    await mkdir("scratch")
    await writeFile("scratch/notes.txt", "one line")

    val notes = await readFile("scratch/notes.txt")

    if notes.ok
        print(notes.value)
    else
        print("could not read it:", notes.error)

    // A result is an ordinary object, so a pattern takes one apart.
    await readDir("scratch") match
        { ok: true, value: names } -> print(names)
        { error: e } -> print(e)

    await rename("scratch/notes.txt", "scratch/kept.txt")
    await remove("scratch/kept.txt")
    await rmdir("scratch")

main()
```

**A call that can fail answers a result — `{ ok: true, value: v }` or `{ ok: false, error: text }` —
and the promise never rejects.** A file that is not there is not a defect in the program asking for
it, so the caller is handed something it has to look at rather than an unwind it has to be ready for.
That is the division `catch` exists for the other half of: results for the failures a caller was
always going to deal with, unwinding for the ones nothing could have anticipated.

It costs no new machinery. A result is an ordinary object, so `match` already destructures one and
the collector already traces one — the same argument that made a module an object.

`readFile` answers text and `readBytes` answers an array of numbers; a file that is not valid UTF-8
has no slate string to become, so `readFile` answers an error naming `readBytes`. `writeFile`
replaces whatever was there, and renders anything that is not a string the way `print` would.
`exists` is the one call with no failure case, so it answers a plain `true` or `false`. Every error
carries libuv's own sentence — `cannot read x: ENOENT: no such file or directory`.

**Giving a builtin the wrong kind of argument still raises**, because that is a defect in the program
rather than a condition it can handle: `readFile(42)` faults, `readFile("/gone")` answers.

**Every one of them has a blocking twin under a `Sync` suffix** — `readFileSync`, `writeFileSync`,
`statSync` and the rest — which is node's arrangement and node's spelling:

```
mkdirSync("scratch")
writeFileSync("scratch/notes.txt", "one line")

print(readFileSync("scratch/notes.txt").value)
```

The blocking half answers the same result shape as the promise-shaped half, so the two differ in the
waiting and in nothing else.

The plain names are asynchronous because a language whose entire event story is one loop has a lot to
lose from a call that stops it: a server that blocks on a read stops answering everybody. The `Sync`
forms are there because a great many programs are not servers — a script that reads a configuration
file before it does anything, or whose whole job is three file operations in order, gains nothing
from a promise and pays for it in an `async` function that exists only to hold an `await`.

**The naming is what keeps that from being a trap.** The blocking call is the one with the longer
name and the suffix, so reaching for it is a decision rather than an accident, and a reader can see
which was written without checking anything. The two halves agree on everything but the waiting: a
`Sync` call answers the same result its promise would have settled to, error and all.

### TCP

Nine builtins over the same loop:

```
val server = listen(0, conn ->
    onData(conn, chunk ->
        if chunk == null
            close(conn)
        else
            send(conn, "echo: " + chunk)))

async main()
    val client = (await connect("127.0.0.1", localPort(server))).value

    onData(client, chunk ->
        if chunk != null
            print(chunk)
            close(client)
            close(server))

    await send(client, "hello")

main()
```

**`connect` and `send` answer promises of a result; `listen`, `onData` and `onBytes` take
callbacks.** That split is not a matter of taste: a connect and a send are each one attempt with one
outcome, which is what a promise is, and a listener does not have one connection any more than a
connection has one chunk. A refused connection is the ordinary thing a client handles, so it comes
back as `{ ok: false, error: ... }` rather than stopping the program.
`onData` hands over each chunk as it arrives and `null` once the peer has finished sending — the end
of a stream is a value here rather than a failure, because a peer closing its half is how a request
ordinarily ends. `onBytes` is the same reader for a socket carrying something that is not text, and
calling either a second time replaces the function rather than adding one.

**A socket that fails ends its stream — it does not stop the program.** A connection reset is
something any peer can produce, deliberately or by being unplugged, and while it stopped the run
every slate server was killable from outside by a client that hung up rudely. It now arrives as the
same `null` a peer that finished sends, which is what the ordinary reader already copes with:
`if chunk == null then close(c)` is right either way.

`onError(sock, fn)` is how a program tells the two apart. `fn` is called with a sentence saying what
went wrong, *instead of* that `null`, and a program that never registers one never hears about it.
It is a registration of its own rather than a third argument to `onData` **because `onData` replaces
its callback** — that replacement is the point of it, and a handler passed alongside the reader would
be silently dropped by the next call.

A port of `0` asks the kernel to pick one and `localPort` says which, so nothing has to guess at a
number that is free. **`connect` takes a name or an address**, resolving through libuv's resolver on
its thread pool — the one `fetch` uses. A name that does not resolve settles the promise the way a
refused connection does, rather than raising.

**A socket keeps the program alive, exactly as a timer does**, so `close` is not optional; a program
that leaves one open never exits. Closing twice is fine, which is what lets a server close its
connections while a read callback closes its own.

**A closed socket is not whatever opens next.** A socket is a slot in the table the loop keeps and a
slot is reused, so the value a program holds carries the *generation* that claimed it — otherwise a
socket held across a `close` would come to mean its successor and compare equal to it. That was a
real defect, and the same one had been sitting in `setTimeout`'s ids since the loop was built.

### TLS, at both ends

A listener told a certificate hands out connections whose bytes are already decrypted, so `slate:http`
— and any other protocol written over these sockets — is an HTTPS server without learning that TLS
exists:

```
val server = listen({ port: 8443, cert: pem, key: keyPem }, conn -> ...)
```

**TLS is a transport and not an HTTP concern**, which is why it goes under `listen` rather than beside
`serve`. node splits it the other way, with an `https` module beside `http`; node's `https` is
literally `http` over a `tls.Server`, and putting the seam one layer down is that arrangement with the
duplication left out. `alpn` beside them offers a protocol list.

The other end is `startTls`, which upgrades a socket that is already open:

```
async main()
    val db = (await connect("db.example.com", 5432)).value

    onBytes(db, read)

    val up = await startTls(db, { host: "db.example.com", trust: authority })

    if !up.ok then print(up.error)
```

**An upgrade rather than a flag on `connect`, because that is what protocols actually do.** TLS from
byte zero is one case and not the general one: PostgreSQL sends eight bytes in the clear and reads one
back before any handshake, SMTP has `STARTTLS`, IMAP and FTP have their own, and a WebSocket over TLS
is HTTPS first. It is also the weaker primitive — TLS from the start is `connect` and then this — so
one builtin covers both where a flag would have covered neither.

`startTls` answers a promise that settles when the handshake has finished, and settles `ok: false`
with the reason when it does not. Everything after it is unchanged: `send` takes plaintext, the reader
is handed plaintext, and a program that writes before awaiting has its bytes queued rather than lost.

**A server upgrades its end the same way**, with the certificate and key `listen` would have taken:

```
startTls(conn, { cert: pem, key: keyPem })
```

Without it a slate server would be TLS from byte zero or not at all, and none of the protocols above
could be written — each of them has the *server* answer in the clear before either end speaks TLS.
There is no third argument saying which end this is: a client has a name to check and a server has a
certificate to present, and neither object could be mistaken for the other.

**The name is checked against the certificate and there is no way to say otherwise.** It goes out as
SNI, without which a shared host does not know which certificate to send, and it is what the
certificate's names are verified against, without which a valid certificate for any host at all would
do. An address works too and is checked against the certificate's addresses rather than its names —
which is why `connect` resolving matters here rather than being a convenience: verify against the
name the program was looking for, not the address the resolver happened to answer with.

A private authority or a self-signed certificate is named with `trust`, which is *added* to the
machine's own store rather than put in place of it — so naming one does not stop verifying everything
else the program talks to.

### Being asked to stop

A program that leaves a socket open never exits, so a server ends only from the inside — and every
way a deployment has of asking one to stop is a signal:

```
import { onSignal } from slate:process
import { serve, close } from slate:http

val server = serve(8080, req -> "hello")

onSignal("SIGTERM", () ->
    print("shutting down")
    close(server))
```

`SIGTERM` is what a container stopping and a `systemd` unit restarting both send, and `SIGINT` is
Ctrl-C at a terminal. A program that hears neither can only be killed, part way through whatever it
was answering.

**The handler is an ordinary function at an ordinary time.** It runs between one turn of the loop
and the next, so nothing about it is restricted the way a C signal handler is: it may print,
allocate, close a socket, start a timer, and take as long as the shutdown needs.

**It is handed nothing, and the registration is what names the signal.** slate checks the count of a
call's arguments, so a name passed to every handler would be a parameter almost none of them would
read; a program that wants one function for two signals registers it twice.

**A watcher does not keep the program alive.** node's rule: a script that installs a handler and does
nothing else still ends. What keeps a server running is the server.

`onSignal` answers an id and `offSignal(id)` stops that handler, after which the signal does whatever
it did before. Stopping one twice is not an error, and neither is an id from a program that has
finished. `SIGKILL` and `SIGSTOP` are refused by name — the kernel acts on those itself and nothing a
program says will run first.

### Digests and randomness

```
import { sha256, hmac, pbkdf2, randomBytes, timingSafeEqual } from slate:crypto

val nonce = randomBytes(18)
val key = pbkdf2("SHA-256", password, salt, 4096, 32)
val tag = hmac("SHA-256", key, "the message")

if timingSafeEqual(tag, sent) then print("that is the right tag")
```

`md5`, `sha1`, `sha256`, `sha384` and `sha512` take text or bytes and answer the digest as bytes.
`hmac` takes the digest by name — `"MD5"`, `"SHA-1"`, `"SHA-256"`, `"SHA-384"`, `"SHA-512"` — because
what a program is speaking to decides it, and a default here would be a decision taken by whoever
wrote the module rather than by the protocol. **`pbkdf2` takes the same names without `"MD5"`**:
every other name here reads a protocol somebody else chose, and deriving a key is the one thing a
program chooses for itself.

**The module is for a package, and that is why it exists.** `slate:jwt` and `slate:ws` are carried in
the binary and are compiled against the scope the natives live in; a package installed with
`slate add` is not, so one speaking a protocol with a challenge in it — SCRAM, SASL, a signed
webhook, a request signed for S3 — had no digest at all and no source of unpredictability at all.
**A nonce a program worked out from the clock is not a nonce**, and that half cannot be written in
slate at any price.

**What a program can write, it writes.** Hex, base64 and the message layout of whatever protocol is
being spoken are ordinary slate — `slate:jwt` writes its own base64url — so they are not here. What
is here is the compression functions and the kernel.

**`pbkdf2` is here for a reason that is not tidiness**: one SCRAM handshake is 4,096 HMACs, which is
some eight thousand SHA-256 compressions — a millisecond as a native and seconds in the interpreter.

**`timingSafeEqual` is what a program checks a tag it was sent with.** `==` on two byte arrays stops
at the first byte that differs, which tells an attacker how much of a forged tag was right, and a tag
can be guessed a byte at a time from that.

**`md5` and `sha1` are exported and neither is an endorsement.** Each is what an existing protocol
asks for — a WebSocket handshake, a Git object, an old server's SASL, PostgreSQL's `md5` login, HTTP
Digest, an S3 `ETag` — and a program speaking one has no say in the matter. Nothing new should be
signed with either, and no content address may be one. For a *password*, none of these is the answer:
`slate:password` is Argon2id and is deliberately slow, which is the whole difference.

### Modules

A file is a module. What another file can see is what it writes `export` in front of:

```
export val greeting = "hello"

export double(x) = x * 2

secret() = "no other file can reach this"
```

and a file takes what it needs by name, or takes the whole module under one:

```
import { double, greeting as hi } from "./util.sl"
import * as util from "./util.sl"

print(hi, double(21), util.shout("go"))
```

**Imports are resolved and compiled before anything runs, and the machine never sees one.** That is
not a preference. slate's file surface is promise-shaped, so an import resolved at run time would
need either a blocking read carved out as a special case or an `import` that answers a promise — and
the second forces top-level `await`, which slate refuses, on every program that imports anything at
all. Compiling imports away avoids both. What reaches the machine is one instruction carrying a
number.

What it costs is that a path cannot be computed, which is the same bargain sysl takes and is what
makes the set of files a program is made of knowable by reading it.

**A path is relative to the file the import is written in**, so a directory of files that import each
other works wherever the program is run from. A bare `util.sl` is refused rather than guessed at: an
unquoted specifier is how a **package** is named, and a language that resolved it as a file could not
tell the two apart.

```
import { helper } from "./util.sl"     // a quoted path  — a file
import { mount } from lath             // a bare word    — a package
import { domHost } from lath/dom       // and one of that package's other modules
import { date, now } from slate:time   // slate:name     — one of slate's own
```

**A package exposes its `main` and whatever its own manifest lists under `modules`**, which is what
the slash names. It is a list rather than a search: resolving `lath/dom` by trying `dom.slx` and then
`dom.sl` would make every private helper in every package importable by accident, and would turn a
renamed file into a broken consumer with no way for the author to have said otherwise.

```
{ name: "lath", version: "0.1.0", main: "lath.slx", modules: { dom: "dom.slx" } }
```

**A circle of imports is refused, with the chain named.** node allows one and initialises half a
module, which is a famous source of confusion; refusing can be relaxed later, and half-built modules
cannot be un-shipped.

**A module is an object**, so there is no new kind of value and nothing new for the collector to
trace — `util.double` is the field selection a program writes for itself. It follows that a module's
exports are a *snapshot* taken when its file finishes: an `export var` the module changes afterwards
is not seen changing from outside, which is where this parts company with TypeScript's live bindings.

**Asking for a name a file does not export is a complaint before the program runs**, and it says what
the file does export. Left to run time it would arrive as an absent field, and the message would be
about `undefined` being bound to a name — true, and about the wrong thing.

**Every complaint is drawn against the file it is about.** A fault carries the file its span belongs
to rather than looking one up when it is reported, because a signal outlives the statement that
raised it: an unhandled rejection is reported after the loop has drained, by which time the machine
is somewhere else entirely.

### Text and numbers

**A slate string is a sequence of characters and never of bytes**, so a program that has never
thought about UTF-8 cannot get it wrong:

```
len("日本語")           // 3
"日本語"[0..<1]         // 日
"héllo"[1]              // é
indexOf("héllo", "llo") // 2 -- by character; it is 3 by byte
```

There is still no character type, so a single character is a string of one. That is Python's answer,
and it is what lets indexing, `chars` and `split` all hand back the same kind of thing.

```
chars  split  join  contains  indexOf  lastIndexOf  startsWith  endsWith
trim  trimStart  trimEnd  upper  lower  replace  repeat
```

`indexOf` answers `null` rather than `-1`, because slate has a null and the operators that go with
it: `indexOf(s, x) ?? 0` says what a sentinel makes a reader work out. `split` on an empty separator
splits into characters.

**`upper` and `lower` are ASCII**, which is `sysl.text`'s own boundary — its case conversion says of
itself that a Unicode case table is above that layer. `é` comes back as it went in. That is a known
limit with a test on it rather than a surprise.

Numbers:

```
number  integer  real  boolean  string
abs  floor  ceil  round  trunc  sqrt  pow  min  max
```

**The type words are the conversions.** `string` tests in a pattern and converts in an expression,
and so do `number`, `integer`, `real` and `boolean` — the two positions never overlap, a word in
pattern position being read as a type and nowhere else. So `string(123)` is `"123"`, `number("42")`
is `42`, and `x is string` asks what it looks like it asks.

**There are no abbreviations.** It is `boolean` and `function`, not `bool` and `fn`; writing a short
form is refused with the long one named, since that is a mistake worth catching rather than a spelling
to learn.

`number` reads a number out of a string and answers `null` where there is not one, which is how a
program checks input without raising. `integer` and `real` move between the two kinds slate keeps apart;
the four roundings leave an integer alone, an integer already being whole. `min` and `max` take as
many arguments as they are given and answer an integer when every one of them was — a `min` that
answered a real for two integers would make every use of it in an index a conversion.

### Types

A type is a shape with a name:

```
type Point = { x: number, y: number }
type Circle = { centre: Point, radius: number }

print({ x: 3, y: 4 } is Point)          // true

describe(v) = v match
    Circle -> s"a circle of radius ${v.radius}"
    Point  -> s"the point ${v.x}, ${v.y}"
    _      -> "no idea"

distance(a: Point, b: Point) = ...
```

**It is TypeScript's `type`, and deliberately so** — the same declaration, the same structural
reading, asking for *at least* those fields. What differs is that slate's is not erased, and that is
the whole of its value: one declaration serves both the pattern and the check at a boundary. A
TypeScript app that reads an API response writes the shape twice, once as a `type` for the checker
and once as a zod schema for the run; slate needs one.

**Nothing of a type's STRUCTURE exists at run time.** A name standing in a pattern is replaced by the
pattern the type declared, while the program is compiled — so `p is Point` is the `is` slate always
had, and a type costs no instruction. What the name *binds* is a shape, below.

**A type is a shape and may not bind a name.** `type Tagged = { x: n }` is refused: a name written
inside a type would be introduced wherever the type is used, which is not what a declaration that
reads as a shape should do. It is the rule a union alternative already followed. An ordinary pattern
outside a declaration binds exactly as it always did.

**A bare name that names no type is still a binding.** That is sysl's rule for a nullary variant and
slate already had it; declaring a type is what makes the name name something.

**`export type` is how an interface leaves the file it was written in**, and it imports like anything
else — both halves cross, the shape the compiler resolves and the value the name binds.

**Annotating is per parameter**, so `f(a, b: Point, c)` is fine — nothing has to be annotated for
anything to be.

**A field the value need not have is marked `?`.** Present it must fit, absent the shape still holds
— which a nullable union cannot say, `tag: string | null` still requiring the key to be there. The
pair states the rule: **`=` is for a pattern that binds and `?` is for one that tests**, and each is
refused where the other belongs.

```
type Note = { title: string, pinned?: boolean }
```

**A type may be a union, and `null` may be one of the alternatives**, which is how a parameter says
it will take nothing:

```
type MaybePoint = Point | null
type Shape = { side: number } | { radius: number }
```

**A definition may say what it answers**, which is what anything downstream of a call needs:

```
double(x: number) -> number = x * 2
name(p: { id: number }) -> string = p.id     // faults: answers string, gave back 7
```

**`any` is a type**, and is what an unannotated thing is. slate is dynamically typed at the edges and
always will be, so `any` is a claim about a value rather than a refusal to make one.

**A parameter may say what it takes**, and then the complaint lands where the value was handed over:

```
error: `b` was declared Point, and was given {x: 0}
```

which is most of what a type buys a language with no checker. What is lost against TypeScript is
real and worth saying: TS catches a mistake on a path you never ran, and this only fires when that
path executes.

**`&` is `|`'s dual and binds tighter**, matching only where every part does. A value picks up fields
on its way down through a stack of functions, and this is how the one at the bottom says what it
receives without writing the sum out by hand:

```
type Authed = { user: { id: integer } }
type Bodied = { body: string }

serve(req: Authed & Bodied) = req.user.id
```

A part *may* bind, where an alternative may not: every part runs, so `{ a } & { b }` binding both is
sound where `{ a } | { b }` binding either is not.

**A TYPE IS A VALUE UNDER ITS OWN NAME**, which is what makes the declaration the validator — nothing
written twice, and no schema library to keep in step with it:

```
Note.test(v)       // true where it fits
Note.mismatch(v)   // [{ path: "title", wanted: "string", got: "nothing" }, ...]
Note.name()        // "Note"
```

`mismatch` collects every reason rather than stopping at the first, because a person filling in a form
wants to be told about all of it at once, and `path` says where in the value each one is. Those three
are the whole surface: **a shape's fields cannot be read back out**, so nothing can grow to depend on
the structure of a type. `is` is deliberately not extended to take one — a bare name in pattern
position binds, so `v is s` would match everything — and `shape` is a type word, so `s is shape` asks
whether `s` is one of these.

An interface, in the sense of a set of operations, needs nothing further — functions are values, so
`type Drawable = { draw: function }` is one. And a trait's other half, the default methods, is what a proto
already is. A class promises one with `is`, below.

### Objects that share their behaviour

`proto` is an ordinary field, and a lookup that misses carries on into it:

```
val Shape = {
    describe: self -> s"${self.kind} with area ${self.area()}",
    kind: "shape"
}

val Square = { proto: Shape, kind: "square", area: self -> self.side * self.side }

square(side) = { side: side, proto: Square }

print(square(4).describe())          // square with area 16
```

**No syntax and no new kind of value** — slate already looked `hash` and `equals` up by name, so a
well-known field is the mechanism the language had rather than a new one. A proto may have a proto,
so chains and overriding come free; `describe` lives on `Shape` and calls `area`, which only the
concrete shapes have, so the call goes back down to whichever object it started from. That is
dispatch, and it needed no keyword.

**A method reached through a proto is handed the object it was found on.** One `dist` serves every
point, so it cannot have captured a particular one — it has to be told, and `self` is an ordinary
first parameter. A method stored on the object itself has already captured what it needs and is given
nothing extra:

```
counter() =
    var n = 0
    var c = {}
    c.bump = () ->
        n += 1
        n
    c
```

That is not two rules but one: **captured methods take no receiver, shared ones must.** It is also
what let protos arrive without breaking anything — every hook written before them is a closure of
exactly that second kind.

Only `o.m(...)` passes a receiver. `o.m` on its own hands back the bare function, so taking a method
off an object and calling it later is allowed and gives you what you took.

**The proto is the identity**, and `class` below is what lets `is` ask about it. Written by hand,
`p.proto == Point` is the closest an object literal gets — and it is not quite `instanceof`: `==` on
objects is deep, so it answers true for anything holding the same fields, and it looks exactly one
link up the chain.

**And it is what makes objects affordable.** Three methods written as captured closures cost three
closures *per instance*; on a proto they cost three once. On slate's 4 MiB heap that is four thousand
objects against eight.

### Classes

A class is the object above with a word in front of it. `class` binds a name to an object literal and
`from` is that object's `proto`, so what runs is what the previous section described:

```
class Shape
    val sides = 0

    describe(self) = s"a ${self.name()} of area ${self.area()}"

class Square from Shape
    val sides = 4
    var side

    name(self) = "square"

    area(self) = self.side * self.side

print(Square.new(4).describe())      // a square of area 16
```

**A method is written in the ordinary definition syntax, and that is the point of the word.** A
field's value is an expression, so a method in a literal is a lambda and its body is whatever fits
after `->`. A definition's body may be an indented run of statements, take annotated or destructured
parameters, be `async`, or `yield`. A class of twenty methods reads like twenty functions rather than
like twenty fields.

**`val` is the class's and `var` is each object's**, and that distinction is the one that bites. A
`val` is one value however many objects there are; a `var` declares a field each object gets, and its
initialiser runs **once per object**:

```
class Bag
    var items = []       // a NEW array for every bag
    val kind = "bag"     // one string, shared
```

TypeScript spells the per-instance one `items = []`, so a reader coming from TS will write `val` and
get one array every instance pushes into — Python's oldest trap arriving through a door that looks
like TS's. So **a mutable literal under `val` is refused**, and the message names `var` as the fix.
Only a *literal* is refused: an object bound outside the class and named here is sharing somebody
asked for, and still compiles.

**A class that declares fields and writes no constructor is given one**, taking all of them — the
fields with no initialiser first, and then the initialised ones, each optional with its initialiser
as its default:

```
class Square
    var side
    var tags = []

Square.new(4)               // side = 4, tags = a fresh []
Square.new(4, ["red"])      // and tags said otherwise
```

A default is worked out at the call, so leaving `tags` out still gives every square its own array.
**An initialised field comes after an uninitialised one whatever order they were written in**, since
a default has to be trailing: `var kind = "plain"` above `var side` gives `new(side, kind =
"plain")`. **A class that declares nothing gets no `new` at all**, rather than one answering an
object with nothing in it; `{ side: 4, proto: Square }` still works and is how such a class is made.

**Write your own `new` when it has something to do.** `var` in its parameter list declares the field
and assigns it — TypeScript's parameter property — and `self` is the object being made. The body runs
for its effect and the object is what comes back:

```
class Rect
    var area = 0

    new(var w, var h)
        if w < 0 || h < 0 then throw "a side cannot be negative"

        self.area = w * h
```

A class with no declared fields keeps the plain form, where the body's value *is* the object:
`new(v) = { v: v }`. It is given the class as its proto on the way out, by writing rather than
copying.

**`is` asks which class a value was made from**, and walks the whole chain:

```
val sq = Square.new(1)

print(sq is Square, sq is Shape)                    // true true
print({ side: 1, proto: Square } is Square)         // true
print({ side: 1 } is Square)                        // false
print(Square is Square)                             // false
```

This is the one thing `class` adds that a hand-written proto could not have. A bare name in pattern
position is a binding unless something has declared it, and a class declaration is what declares it —
so the name works everywhere a type does: in `is`, in a `match` arm, and in a parameter's annotation.
A class crosses a file under `export` as both halves at once, the value and the type.

**A class name written with fields after it tests and takes apart at once**, which is what a Scala
case class does. By position, or by name:

```
tell(v) = v match
    Square(n) -> s"a square of side ${n}"       // the order `new` takes them in
    Circle { radius: r } -> s"a circle of ${r}"  // order-independent
    Rect { w, h } -> s"${w} by ${h}"             // `{ w }` is short for `{ w: w }`
    _ -> "something else"
```

**The positional order is the constructor's, and that holds by construction rather than by
convention** — the field list a pattern is checked against *is* the parameter list of the `new` the
class was given, so `Square(n)` binds what `Square.new(4)` sets and the two cannot drift apart. It
follows that an initialised field is positioned where the constructor puts it, not where it was
written: `var kind = "plain"` above `var side` gives `Tagged(side, kind)`. A class that builds its own
object in a hand-written `new` has no such list and is refused the positional form by name, with the
named one offered instead; the same goes for a `new` that takes anything that is not a field.

**Naming the class is also what lets a misspelled field be caught.** A bare `{ raduis: r }` is a legal
pattern that never matches — any object may lack any field — so the arm is silently dead. Written
after a class name there is a declaration to check it against, and it is refused where it stands.

Both forms nest and both take an `@` binding, patterns being patterns wherever they stand. The test
is the proto *walk*, so a pattern written for a base class takes an object of a class descended from
it apart — the same question `is` answers.

**`is` in a class header is TypeScript's `implements`** — a promise, checked where the class is
written:

```
type Drawable = { draw: function }

class Pen is Drawable
    draw(self) = "pen"
```

It inherits nothing; `from` does that. What it buys is *when* you find out: leave `draw` out and the
fault names the class rather than arriving wherever something first wanted to draw one. A class may
promise several types (`is Drawable, Named`) and descend from one.

A promise is kept by a method a base supplies, because **an object pattern counts a field a proto
supplies** — a pattern asks whether the value *has* the field, which is the question `.` answers.
(JavaScript splits the same seam and puts `in` on this side of it.)

**There is no `super`, and none is needed.** A base class is an ordinary value in scope, and a method
stored on it directly is handed no receiver — so passing one is how you call it:

```
class Loud from Square
    new(side) = { side: side }

    describe(self) = upper(Shape.describe(self)) + "!"
```

`Shape.describe(self)` names the class the call was written in, which is what a super call means.
Counting links from whatever object turned up — `self.proto.proto` — is a different and wrong thing.

A class belongs to the top level of a file, as a `type` does and for the same reason: its name is
resolved while compiling. `class` is a soft word, so a program already using it as a variable name is
untouched.

### Data types

`data` declares a closed set of variants — an algebraic data type — and that closed set is what makes
a `match` over one worth checking:

```
data Shape
    Circle(r)
    Rect(w, h)
    Empty

    area(self) = self match
        Circle(r) -> 3 * r * r
        Rect(w, h) -> w * h
        Empty -> 0

print(Circle(3), Circle(3).area())        // Circle(3) 27
```

**A variant is a class from the data type**, which is the whole of the implementation: `is Shape`, an
annotation, `export`, a cross-file import and a method on the shared body are all the machinery
`class` already had. `Circle(3)` is the generated constructor, reached by the rule that calling an
object calls its `new`. A variant that declares no fields — `Empty` — is a *value* rather than a
maker, so the test for it is identity.

**A data value does not change.** A write to one of its fields is refused, and `v with { r: 4 }`
answers a new one that differs there. Two equal ones are equal and hash alike, so a data value is an
ordinary key.

**A `match` over an annotated subject must cover every variant**, and the complaint names each one
left out. It is checked exactly where the shape was written down — an unannotated subject is said
nothing about — and a `_` arm is how a program says it has finished listing:

```
sides(s: Shape) = s match
    Circle(_) -> 0
    Rect(_, _) -> 4
    Empty -> 0
```

Variants take the same two pattern forms a class does — `Circle(r)` by position, `Circle { r }` by
name — and a field name the variant does not carry is refused where it is written.

### Tests

`@test` marks a function of no arguments, and `slate test` is the only thing that calls one:

```
val floor = 2

export clamp(x) = if x < floor then floor else x

@test
clamp_lifts_a_small_number_to_the_floor() =
    assertEq(clamp(-3), floor)

@test
async a_missing_file_answers_rather_than_raising() =
    val r = await readFile("nothing-here.txt")

    assert(!r.ok, "a file that is not there answers a result")
```

```
$ slate test .
  ok    examples/testing.sl :: clamp_lifts_a_small_number_to_the_floor   0ms
  FAIL  examples/testing.sl :: widen_clamps_every_element   0ms
        error: got [2, 5], wanted [2, 5, 2]
          --> examples/testing.sl:41:5
           |
        41 |     assertEq(widen([1, 5, -2]), [2, 5, 2])
           |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

5 passed, 1 failed
```

`slate test` takes a file or a directory, and walks a directory for every `.sl` file under it.

**Tests may live beside the code or in a file of their own**, and the difference is what they can
reach. slate's module is a *file*, so a test beside the code sees what that file kept private, and a
test file that imports the module sees exactly what a reader of it sees. Both are ordinary `@test`
functions; nothing distinguishes the two arrangements but where you put them.

**Only the file being tested contributes its tests.** A test file that imports the module it tests
does not run that module's tests a second time, so walking a directory runs each file's tests exactly
once.

**A failed assertion raises**, and the runner catches it exactly as a `catch` would — which is why
this could not have been built before `try`/`catch`: without a place to stop an unwind, the first
failing assertion took the whole run with it. `assert(condition)` and `assert(condition, message)`;
`assertEq(got, wanted)` renders both sides, quoting a string so that `"6"` and `6` do not look alike.
A test that faults without asserting anything fails the same way, and whatever it printed is shown
above the failure.

**An `async` test is waited for.** Calling one hands back a promise that has not settled, so a runner
that read the answer straight away would call every asynchronous test a pass whatever it did.

**Running a file plainly calls none of its tests**, so `@test` costs a program that is not being
tested one closure and nothing else.

## What it leans on

`sh.sysl.parsing` does the scanner tier — spans, the byte cursor, literal reading, the diagnostic
renderer, the binding-power loop, and the layout pass. Slate is that package's first consumer of
**`layout`**: `json` has no line structure and `ogol` has no indentation, so the column stack had
been written and never run by anything.

**slate is also where `layout`'s 0.3.0 came from.** A bracket used to suspend the off-side rule
outright, so `push(xs, n match ...)` had its arms inside a bracket pair where a newline means nothing
and the block never opened. The package now lets a grammar nominate the tokens that open a block —
slate's is `match`, and it has exactly one where sysl has two.

Two of its own notes turn out to matter here and are worth repeating:

- **The `TokenStream` the Pratt loop runs on is the parser, not the token cursor.** A `led` callback
  is handed the `*S` it was called with, so making `S` the parser is what lets a callback complain
  about what it just read.
- **A parse error is a node, not a `Result`.** It keeps the tree shaped and lets one pass report
  every mistake in a file.

## How it runs

A program is compiled to instructions and run on a stack machine. It was a tree-walker until it
needed to be something else, and the reason is worth stating because it is the only one:
**`await` has to suspend in the middle of an expression, and a tree-walker's state is the host
language's own call stack, which cannot be captured.** A callback does not need this — a callback
runs *from* an event loop, never from inside an expression — so callbacks and promises would have
been fine as they were. `await` is not.

A slate call pushes a frame onto an array rather than recursing in sysl, so a call chain of any depth
is one sysl frame, and a suspended call is a frame nobody is currently running. Calling an `async`
function starts a **machine of its own** — operand stack, frames, scope and the promise it will
settle — and `await` sets that whole machine aside into a table the collector roots, which is the
whole of what makes a coroutine here. A parked line of execution is not running and is not therefore
any less alive.

There are two queues and the order between them is fixed. libuv answers *something happened outside
the program*; a second, drained to empty between every turn of it, answers *a value a suspended call
is owed is now known*. That is JavaScript's microtask/macrotask split, and it is not a refinement — a
program that resolved a promise from a timer callback and then ran the next timer before the awaiting
function had moved would interleave in an order nothing could predict.

**The collector got simpler on the way.** A tree-walker's working values live in host locals, which a
precise mark phase cannot see, so every one of them has to be pushed onto a shadow stack by hand —
and a forgotten push is a crash that only appears under memory pressure. A machine keeps its values
in an operand stack that is an ordinary array, so the tracer walks it and the whole class of mistake
goes away. That claim was tested the hard way: keeping the running frame's scope in a host local for
speed reintroduced exactly that bug, and it swept the live scope chain out from under the machine.

## Memory

**Values are traced, not reference counted, because slate makes a cycle on every named function** —
`define` binds a closure into the very scope that closure captured. Nothing declared that back-edge,
so `weak` cannot help: it is a cycle in somebody else's program, which is what `sysl-lang/gc` is for.

The collector manages exactly what refcounting cannot. Strings, arrays, objects, closures and scopes
are collected; the syntax tree is not, being immutable and acyclic. A slate string is a GC object
holding a sysl `string` and is that string's only owner, so finalising takes its count to zero — the
same bargain gives an array its `Buf` and an object its `Map`. A `Value` therefore holds no
reference-counted member at all: scalars and raw pointers, which is what lets one be copied with no
ARC traffic on the hot path.

Two consequences worth knowing:

- **`alloc` never collects, so a value held only in a sysl local is invisible to the mark phase.** A
  tree-walker has those everywhere — a match subject, a half-built literal, a call's arguments — so
  the interpreter keeps a shadow stack and collects only at a statement boundary. That is the real
  cost of tracing over refcounting, and it is why `obj.sysl` has `hold` and `release`.
- **Collection is scheduled on what is live, and the threshold moves.** The heap collects when the
  live bytes pass a threshold, and that threshold is then raised to twice what survived — so the cost
  of collecting tracks the garbage a program makes rather than the statements it executes. Reading
  the high-water mark instead, against a fixed number, meant a full mark-sweep at every statement
  once a program had ever grown past it: 6,000 live objects and 200,000 statements of ordinary work
  took 1 minute 31 seconds and 205,631 collections, and now takes 0.22 seconds and 27.
- **A program that outgrows the heap is told so, against the line that asked.** The heap does not
  grow, and a full one used to answer `null` — which every constructor then wrote through, so the
  program died of a segmentation fault with none of the output it had already produced. There is now
  a reserve object of each kind for a full heap to answer with, which is somewhere real to write
  while the statement finishes.
- **The interpreter's state is module storage**, because a root function must be a top-level function
  to have an address and must reach that state. One interpreter to a process; `run` empties the heap
  on the way in, which is what lets two programs run one after another.

## What is not here yet

A literate `.lsl` form, a name resolver for `connect`, Unicode case conversion, and a standard
library beyond the builtins. On the object side: `super`, and a check that a proto satisfies a `type`
when it is attached to an object literal by hand.

In the JavaScript back end: `slate:net`, `slate:time`, `slate:regex`, `fetch`, `run`,
`slate:password`, `slate:crypto`, `slate:brotli`, `slate:llhttp`, and the modules written over them. Each one is a
name that says *"not in the JavaScript back end yet"* rather than a name that is not there.

**`defer` is on sysl's list and is deliberately not here.** It earns its place in Go and in sysl
because neither collects: a function that acquires something has to release it on every exit path,
and `defer` is what stops that being a maintenance problem. slate has a tracing collector, so memory
needs no cleanup at all. Its external resources are a timer, which `clearTimeout` closes; a file,
which no program ever holds open, since `readFile` and `writeFile` open and close within one promise;
and a socket, which a program does hold and does close. **That last one is the case worth watching**
— it is the first resource here with a lifetime a program manages — but `defer` would not be the
answer to it either, since a socket is closed from a callback far away from where it was opened, and
that is precisely where a scope-based release does not reach.

If that changes, the answer will not be `defer`. slate's object model already carries `hash` and
`equals` as ordinary fields, so a `dispose` read the same way — scope-based, as JavaScript's `using`
is — would be the third of a pattern rather than a new mechanism.

The examples are the current surface, and it is meant to grow in whatever direction puts the most
pressure on sysl. Every one of them is run by the suite, so a change to the language cannot leave one
of them saying something that no longer compiles.

## Licence

ISC. See [LICENSE](LICENSE).
