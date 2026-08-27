# slate

A small indentation-structured language, written in [sysl](https://sysl.sh) to find out what sysl is
like to write a real front end in.

**The language is a means rather than an end.** What is being tested is sysl. A tree-walking
interpreter is one of the few programs that reaches for nearly everything a language has — recursive
data through references, payload-carrying enums, traits with associated types, generics over a
container, closures that outlive the frame that made them, and an error path that has to carry a
position from the byte that caused it all the way to the sentence a person reads. Where sysl makes
one of those awkward, that is the finding, and the finding is the point.

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
    builtin.sysl    the functions a program has without writing them
    show.sysl       the tree as `(+ 1 (* 2 3))`, for the tests
    tests.sysl      what all of it claims, run by `sysl test .`
    main.sysl       the driver: a path in, a report out
examples/tour.sl    the language in one file
examples/match.sl   the patterns, in another
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

## Running it

```
sysl test .
sysl run . -- examples/tour.sl
```

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
        [first, ...rest] -> "a list starting " + str(first)
        "sat" | "sun" -> "a weekend"
        n @ num if n < 0 -> "a negative number"
        _ -> "something else"
```

**A bare name in a pattern tests for a kind where it names one, and binds otherwise** — `null`,
`bool`, `int`, `real`, `num`, `str`, `array`, `object`, `fn`. That is sysl's own bare-name rule (a
bare identifier is a nullary-variant pattern when it names one of the scrutinee's variants), applied
to a scrutinee that is always a value: those words *are* the variants. So a type test needs no syntax
of its own, and `n @ pat` — again sysl's spelling — is how a program tests and names at once. None of
them is a keyword: `val int = 3` still works.

`num` is the one that is not a variant, being the union of `int` and `real`. It earns its place
because the two are separate values, so a pattern guarding arithmetic would otherwise be written
twice. It is also what makes a broad guard safe: `n if n < 0` binds *anything*, so the guard
evaluates `[3, 4] < 0` and faults, where `n @ num if n < 0` cannot reach the guard with the wrong
kind.

An object pattern matches an object with *at least* those fields, because a record grows fields over
its life. `{ name }` is shorthand for `{ name: name }`. No alternative of a `|` may bind a name, since
it would be bound down one path and not the other. **There is no exhaustiveness check and there
cannot be one** — slate is dynamically typed, so the set of values a name may hold is not known; a
subject matching no arm is a runtime fault, as Scala's `MatchError` is.

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
is evaluated once. `is` puts a pattern where a condition is wanted — `v is num`, `v is not str`,
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

Seven builtins over the same loop:

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

A port of `0` asks the kernel to pick one and `localPort` says which, so nothing has to guess at a
number that is free. `connect` takes an address rather than a name — there is no resolver yet.

**A socket keeps the program alive, exactly as a timer does**, so `close` is not optional; a program
that leaves one open never exits. Closing twice is fine, which is what lets a server close its
connections while a read callback closes its own.

**A closed socket is not whatever opens next.** A socket is a slot in the table the loop keeps and a
slot is reused, so the value a program holds carries the *generation* that claimed it — otherwise a
socket held across a `close` would come to mean its successor and compare equal to it. That was a
real defect, and the same one had been sitting in `setTimeout`'s ids since the loop was built.

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
other works wherever the program is run from. A bare `util.sl` is refused rather than guessed at: a
specifier with no `./` is what a package will be called when slate has packages, and a language that
resolved it as a file today could not tell the two apart tomorrow.

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

A literate `.lsl` form, a name resolver for `connect`, a way to turn a real into a whole number, and
anything resembling a standard library beyond the builtins. Modules have no packages behind them yet
either — every path is a file on disk.

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

ISC.
