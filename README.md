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
    nil

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

**A bare name in a pattern tests for a kind where it names one, and binds otherwise** — `nil`,
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

It is dynamically typed. Values are `nil`, booleans, integers, reals, strings, arrays, objects and
functions. Arrays and objects are reference types and compare by their contents. Only `false` and
`nil` are false — zero and the empty string are not, which is the rule Ruby and Lua take and the one
JavaScript and Python are most often criticised for.

`&&` and `||` short-circuit and answer the operand that decided, which is the one place slate's rule
is not sysl's: sysl's operands are `bool` and there is nothing else for it to give back.

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
is one sysl frame, and a suspended call is a frame nobody is currently running.

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
- **The interpreter's state is module storage**, because a root function must be a top-level function
  to have an address and must reach that state. One interpreter to a process; `run` empties the heap
  on the way in, which is what lets two programs run one after another.

## What is not here yet

String interpolation, a module system, a literate `.lsl` form, and anything resembling a standard
library beyond five builtins.

The two examples are the current surface, and it is meant to grow in whatever direction puts the most
pressure on sysl.

## Licence

ISC.
