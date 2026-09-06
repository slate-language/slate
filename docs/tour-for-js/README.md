---
title: A tour for JavaScript and TypeScript people
weight: 20
summary: What slate does differently, and why — for somebody who already knows JavaScript and does not need to be told what a closure is.
---

# A tour for JavaScript and TypeScript people

**This page is only the differences.** Closures, first-class functions, objects, promises,
`async`/`await`, generators, modules and JSON are all here and all work the way you expect, so none
of them is explained again. What follows is what slate does *not* do the same way, and why.

Every program below is run by slate's own test suite and every refusal is quoted from the diagnostic
the compiler really prints. Nothing here is a sketch.

## One suite, two hosts

**slate is an interpreter and a JavaScript compiler reading the same tree**, so a program is written
once and can be run either way:

```
slate app.sl                    the interpreter, on libuv
slate js app.sl -o app.js       the same program, as one JavaScript file
```

and — this is the part that pays — a test suite is written once and run twice:

```
slate test .                    every @test, under the interpreter
slate test --js .               every @test, compiled to one program and run under node
```

**A test is a function with an attribute on it. There is no framework to install:**

```slate
add(a, b) = a + b

@test
addsTwoNumbers()
    assertEq(add(2, 3), 5)

@test
async readsAFileThatIsNotThere()
    assert(true)

print("this file has two tests in it")
```

```output
this file has two tests in it
```

`slate js` writes **one self-contained file** — the runtime and the program — so there is no bundler,
no `node_modules` and nothing to fetch. Where the two hosts genuinely differ, the difference is
written down in [JavaScript](../reference/javascript.md) and the name *refuses with a sentence saying
which host lacks what*, rather than being absent or, worse, quietly wrong: no browser has a brotli
encoder, so `slate:brotli` refuses there and points at `slate:gzip`.

## Foreign input is an answer, not an exception

**Two failure channels, and the rule that decides between them is one sentence: text or bytes from
outside the program is an ANSWER, and a value the program built itself is a FAULT.**

An answer is an ordinary object — `{ ok: true, value }` or `{ ok: false, error }` — and the caller has
to look at it. There is nothing to catch and nothing to forget to catch:

```slate
val bad = parseJSON("{ oops")
val good = parseJSON("{ \"a\": 1 }")

print(bad.ok, good.ok, good.value.a)
```

```output
false true 1
```

**The same call in the other direction faults**, because a value that will not serialise is a defect
in the program rather than a condition it was going to handle:

```slate
print(toJSON(1))
print(toJSON(x -> x))
```

```error
there is no JSON for a function
```

`readFile` answers and `readFile(42)` faults; `decompress` answers and `compress` faults; `parseDate`
answers and `date(y, m, d)` faults. It is the same rule every time, so it does not have to be looked
up per function.

## The diagnostics are sentences, with a caret under the mistake

**A message is judged by where it sends the reader.** slate is mostly a machine for producing
sentences a person reads, and every one is written to be acted on:

```slate
val ns = [1, 2, 3]

print(ns.upper())
```

```error
`upper` is not something an array can do
```

Not *"upper is not a function"* about a value nobody named. And when a type is involved the message
carries the shape, the field and the spelling you probably meant, with a caret under the exact
token:

```slate
type Note = { title: string, pinned?: boolean }

save(n: Note) = n.title

print(save({ title: "Milk", pinnned: true }))
```

```error
  |
5 | print(save({ title: "Milk", pinnned: true }))
  |                             ^^^^^^^
```

The whole of what that program prints is

```
error: `pinnned` is not a field of { title: string, pinned?: boolean }, and an object
literal written here may carry only the fields it names -- did you mean `pinned`?
```

**which is TypeScript's excess-property check, drawn in the same place and argued the same way**: a
literal written for this call serves nobody else, so an extra field in it is intentional and
therefore wrong.

## `type` is TypeScript's `type`, and it is not erased

The declaration is the one you already write:

```slate
type Note = { title: string, pinned?: boolean }
type Feed = { notes: array of Note, next?: string }

save(n: Note) -> string = n.title

print(save({ title: "Milk" }))
```

```output
Milk
```

**What differs is that nothing is thrown away.** The same declaration is a pattern, and it is a
validator at a boundary — so an API response is checked against the type you already wrote, instead
of against a schema written a second time in a different language:

```slate
type Note = { title: string, pinned?: boolean }

print({ title: "Milk" } is Note)
print(Note.test({ title: 7 }))
print(Note.mismatch({ title: 7, extra: 1 }))
print(Note.name())
```

```output
true
false
[{path: "title", wanted: "string", got: "integer"}]
Note
```

`mismatch` collects **every** reason rather than stopping at the first, and `path` says where in the
value each one is — which is what a form or an API error response actually needs.

**A type name in a `match` arm is the same declaration again:**

```slate
type Point = { x: number, y: number }
type Circle = { centre: Point, radius: number }

describe(v) = v match
    Circle -> s"a circle of radius ${v.radius}"
    Point  -> s"the point ${v.x}, ${v.y}"
    _      -> "no idea"

print(describe({ centre: { x: 0, y: 0 }, radius: 2 }))
print(describe({ x: 3, y: 4 }))
print(describe("nothing"))
```

```output
a circle of radius 2
the point 3, 4
no idea
```

**Nothing of a type's structure exists at run time**, though: a name in pattern position is replaced
by the pattern the type declared *while the program is compiled*, so `p is Point` costs no
instruction. What the name buys at run time is the `Shape` value above, and its three questions are
all a program can ask — a type's fields cannot be read back out, so nothing can grow to depend on the
structure of one.

## The checker never refuses a program that runs

**That single rule is the whole design of slate's static pass**, and it is the opposite trade from
TypeScript's:

> The pass may only report what the machine would also refuse. A program that runs is never refused
> before it runs.

What it costs is worth saying plainly: **TypeScript catches a mistake on a path you never ran, and
this only fires where the pass can prove the value is wrong or where that path executes.** What it
buys is that there is never a program you have to argue with the checker about — no `any`, no
`as unknown as`, no `@ts-expect-error`, because a pass that cannot be certain says nothing and the
machine still checks.

So an unannotated program is checked at run time, exactly as JavaScript is:

```slate
first(xs) = xs[0]

print(first([1, 2, 3]), first("abc"))
```

```output
1 a
```

and an annotated one is checked before it runs, because the annotation is a promise the program made
in writing:

```slate
var count: integer = 0

count = "many"
```

```error
`count` was declared integer, and this is string
```

**Three deliberate exceptions, each an annotation the machine cannot check for you**: an annotated
`var` is held to its declared type at every assignment; every argument must fit the type a type
parameter was solved to; and an object literal written where a shape is expected may carry only the
fields that shape names. [Types](../reference/types.md) has all three, with the reasoning.

## `_` is a lambda with its parameter left out

`x => x * 2` is a lot of ceremony for doubling. **A `_` where a value goes is the parameter of a
function nobody wrote**, and the body is the smallest thing around it — a call's argument, a
bracketed group, or the value of a binding:

```slate
val ns = [1, 2, 5, 9]

print(map(ns, _ * 2))
print(filter(ns, _ > 3))
print(map(["ada", "grace"], upper(_)))
```

```output
[2, 4, 10, 18]
[5, 9]
["ADA", "GRACE"]
```

**Every `_` is a parameter of its own, left to right**, which is exactly what a comparator wants:

```slate
val people = [{ name: "grace", age: 45 }, { name: "ada", age: 36 }]

print(map(sorted(people, _.age < _.age), _.name))
```

```output
["ada", "grace"]
```

**A lone `_` is handed outward to the thing around it**, so `add(_, 1)` is the partial application it
reads as:

```slate
add(a, b) = a + b

print(map([1, 2, 3], add(_, 1)))
```

```output
[2, 3, 4]
```

That rule has one surprise and it is worth knowing: `_ > 3 && _ < 9` is a function of *two*
parameters, not one test of one number. Write the parameter out when you mean to mention it twice.

## Pattern matching is in the language

**`match` is postfix** — a transformation of the thing to its left, so it reads as one step in a
pipeline rather than as a statement wrapped around one. Patterns test literals, shapes, arrays and
alternatives; a name binds; `@` does both; and a guard runs after the pattern has bound:

```slate
classify(v) = v match
    { kind: "point", at: [0, 0] } -> "origin"
    { kind: "point", at: [x, y] } if x == y -> "diagonal"
    [first, ...rest] -> s"a list of ${rest.length + 1} starting ${first}"
    "sat" | "sun" -> "a weekend"
    n @ number if n < 0 -> s"the negative number ${n}"
    _ -> "something else"

print(classify({ kind: "point", at: [4, 4] }))
print(classify([9, 8, 7]))
print(classify(-4))
```

```output
diagonal
a list of 3 starting 9
the negative number -4
```

**A subject that matches no arm is a fault**, as Scala's `MatchError` is — not a silent `undefined`.

**And a `data` declaration gives you the exhaustive case**, which is the thing a discriminated union
in TypeScript is imitating:

```slate
data Shape
    Circle(radius)
    Rect(w, h)

area(s) = s match
    Circle(r) -> 3.14159 * r * r
    Rect(w, h) -> w * h

print(area(Circle(2)))
print(area(Rect(3, 4)))
```

```output
12.5664
12
```

## `with` is the spread you meant

`{ ...o, a: 1 }` is doing two jobs at once, and the one you nearly always want is *this object,
changed here*. That is `with`:

```slate
val user = { name: "ada", role: "admin", active: true }

print(user with { role: "reader" })
print(user)
```

```output
{name: "ada", role: "reader", active: true}
{name: "ada", role: "admin", active: true}
```

**The original is untouched** and the field order is kept, so a record read from a database and
written back does not come out reordered. `with` binds as tightly as a field selection, which is why
`a + b with c` changes `b` rather than the sum.

## An asset is an import, not a fetch

**A quoted path naming anything but `.sl` or `.slx` is an asset, and one name takes the whole of it
as a string:**

```slate
import panel from "./panel.css"

print(panel is string, panel.length > 0)
```

```output
true true
```

**The file is read while the program is compiled and travels inside it.** Nothing sits beside the
binary at run time, nothing is fetched, and six files importing one stylesheet is one string — and it
is byte for byte the same under `slate js`, where the text is written into the emitted program.

That is what [lath](https://github.com/slate-language/lath)'s `style(css)` is built on: a component
imports its own stylesheet and registers it, and the page ends up with a `<style>` for exactly the
components it rendered — on a server and in a browser alike, with no preprocessor and no build step:

```slate
import { createElement, Fragment, style } from lath
import card from "./card.css"

Card(props) =
    style(card)

    <div class="card"><h2>{props.title}</h2>{props.children}</div>
```

**Elements are in the language too** — `<div>` in the source, desugared by the parser into ordinary
calls, in **every** file rather than in a separate mode. slate has no `<T>` generics, which is the
entire reason `.tsx` had to be a different parse from `.ts` and `.slx` does not.

## Batteries, and they are in the binary

There is no `npm install` for the things a server needs. **Twenty `slate:` modules ship inside the
executable** — the file system, TCP, TLS, an HTTP server and router, HTTP/2 over nghttp2, WebSockets,
Redis, SQLite, LMDB, PCRE2 regular expressions, digests and Argon2id, JWT, gzip, brotli, Zstandard,
images, a temporal library, processes and signals:

```slate
import { encodeComponent, parseQuery } from slate:url
import { date, days } from slate:time

print(encodeComponent("a b&c"))
print(parseQuery("page=2&q=slate").q)
print((date(2026, 9, 5) + days(30)).format("YYYY-MM-DD"))
```

```output
a%20b%26c
slate
2026-10-05
```

**A module rather than a global is decided by whether the word is one a program wants for its own.**
`stat`, `send`, `close`, `connect`, `run`, `query` and `time` all are — while they were global,
writing `val stat = …` shadowed a builtin without meaning to. What is left global is roughly node's
own list.

## Smaller things that will bite you first

**`==` compares by value, all the way down, and there is no `===`:**

```slate
print([1, 2] == [1, 2], { a: 1 } == { a: 1 })
print("1" == 1)
```

```output
true true
false
```

**An integer is a 64-bit integer**, not a double pretending. It wraps, it does not promote, and `/`
between two integers divides towards zero:

```slate
print(7 / 2, 7.0 / 2, 1 << 40)
print(9223372036854775807 + 1)
```

```output
3 3.5 1099511627776
-9223372036854775808
```

**There is no `undefined` to store anywhere.** `null` is a value like any other and is the only one;
`undefined` exists solely as the immediate answer to a read that found nothing, and has to be
resolved with `??` or `has` where it appears:

```slate
val o = { a: 1 }
val xs = [o.b]
```

```error
cannot be put in an array
```

**What that buys is that an `undefined` can never surface far from the read that produced it**, which
is JavaScript's characteristic failure. Every position a value can travel to refuses it, each with
its own sentence.

**`//` is the only comment** — there is no block comment, and `#` is not a comment at all, being the
shebang and nothing else.

**A trailing operator does not continue a line.** `a +` followed by `b` on the next line is two
statements. Where an expression has to span lines, brackets say so, and inside them the off-side rule
is suspended.

## Where to go next

- **[Getting started](../getting-started/)** — install it and write something.
- **[The language reference](../reference/)** — every construct, written down once, in its own place.
- **[The library](../library/)** — what a program has without writing it.
- **[The packages](../packages/)** — an API server, a PostgreSQL client, a UI framework.
