---
title: Statements
weight: 40
---

# Statements

## Declarations

```slate
val name = "slate"
var n = 0
```

**`val` cannot be assigned to again; `var` can.** A `val` bound to an array or an object still allows
that container to be changed — the binding is what is fixed, not the value.

Either may say what it holds, and an annotated `var` is TypeScript's `let`: the declared type is what
the name holds for its whole life, so every assignment is checked against it.

```slate
val name: string = "slate"
var n: integer = 0

n += 1

print(name, n)
```

```output
slate 1
```

A [definition](functions.md) is a statement too, and so are `type`, `class` and `data`, each of which
belongs to the top level of a file.

### `using` — a binding that releases what it held

**`using` is a `val` whose value is released when the block around it is left.** It is what slate has
instead of a `finally`: the release is written at the line that acquired the thing, where it cannot be
forgotten in a branch added later.

```slate
made(name) = { dispose: () -> print("released " + name) }

read() =
    using file = made("file")

    print("working")

read()
```

```output
working
released file
```

**The release runs on every way out of the block, and there are five**: falling off the end, a
`return`, a `break`, a `continue`, and a fault travelling past. An `await` and a `yield` are not ways
out — the block has not been left, and the resource is still the running program's.

```slate
made(name) = { dispose: () -> print("released " + name) }

first(xs) =
    for x in xs
        using turn = made("turn " + string(x))

        if x > 1 then return x

    null

print(first([1, 2, 3]))
```

```output
released turn 1
released turn 2
2
```

**Several in one block are released in reverse**, which is the acquisition order run backwards: a
later resource may have been made out of an earlier one.

```slate
made(name) = { dispose: () -> print("released " + name) }

run() =
    using a = made("a")
    using b = made("b")

    print("body")

run()
```

```output
body
released b
released a
```

**The protocol is a method named `dispose`** — the way a source is anything with a `next`. An object
with the field has one, a class that writes the method has one for every instance, and every built-in
resource answers to it: a socket, a listening server, a database, a Redis client, a WebSocket
connection. There is no interface to implement.

**`null` is skipped**, so an optional resource needs no branch around the block:

```slate
wanted(yes) = if yes then { dispose: () -> print("released") } else null

run(yes) =
    using maybe = wanted(yes)

    print("body")

run(false)
run(true)
```

```output
body
body
released
```

**A value that is neither `null` nor disposable is refused at the DECLARATION**, before the block has
run — the mistake is in the line that acquired the thing, and the reader is told before any work is
done rather than after it.

```slate
anything(v) = v

run() =
    using a = anything(42)

    print("never reached")

run()
```

```error
`using` needs a value with a `dispose` method to call when the block is left, and this is an integer
```

**A `using` is a `val`, and the three shapes a `val` has are the three it has.** An annotation is
checked where the value arrives, a pattern takes the value apart — and a pattern releases the *whole*
value, the names being a way of reading it rather than a list of separate resources.

```slate
run() =
    using { port } = { port: 8080, dispose: () -> print("released") }

    print(port)

run()
```

```output
8080
released
```

**A release that fails while a fault is travelling does not replace it.** The original fault is what
the program is told about, and the release's own complaint rides along as its `suppressed` field. A
release that fails with nothing travelling propagates on its own.

```slate
fails(why) =
    throw why

run() =
    using a = { dispose: () -> fails("could not release") }

    fails("the original")

val e = run() catch caught -> caught

print(e.message)
print(e.suppressed.message)
```

```output
the original
could not release
```

**`await using` is not in slate.** A release has to be able to run while a fault is unwinding, and
nothing can wait there, so a `dispose` that answers a promise is called and its answer is not awaited.

**A `using` written at a file's own top level is released when the file's statements end**, the top
level being a block like any other. That is before the event loop drains, so a resource a later turn
still needs belongs in a function rather than at the top of a file.

### What is in scope where

**A definition is HOISTED to the top of the block it is written in**, which is JavaScript's rule, so
a name may be used above the line that defines it:

```slate
val sink = written

written(r) = "wrote " + string(r)

print(sink(1))
```

```output
wrote 1
```

**A `val` or `var` initialiser stays sequential** — it may read what is above it and not what is
below — and that is the half that matters: nothing about hoisting makes a program's data flow depend
on where a function happens to sit.

```slate
val a = b
val b = 1

print(a)
```

```error
`b` is not defined
```

**The definitions run where they are hoisted**, so a statement standing between two of them is not
reordered around anything: only the binding moves, and what it binds is a function that has not been
called yet.

**A definition may not take a name its own block has already declared**, whether by another
definition or by a `val` or a `var`. The hoisting is the reason: the two would not run in the order
they are written, so what the second one means depends on a rule the reader cannot see.

```slate
f() = 1

print(f())

f() = 2
```

```error
`f` is declared twice in this block
```

A **nested** block is its own, so shadowing an outer name is untouched — and a `val` written *below*
a definition is not a collision but the ordinary way to name a generator and then run it:

```slate
counting()
    yield 1
    yield 2

val counting = counting()

print(counting.next().value, counting.next().value)
```

```output
1 2
```

## Assignment

Assignment is a **statement**, never an expression, so `=` cannot appear inside an expression and
there is nothing for it to be confused with.

```slate
var n = 0
var xs = [1, 2]
var o = { f: 0 }
var a = 1
var b = 2

n = 3
xs[0] = 9
o.f = 9
a, b = b, a                 // several places at once

print(n, xs, o, a, b)
```

```output
3 [9, 2] {f: 9} 2 1
```

**Assignment binds nothing.** `g = 1` where `g` was never declared is refused before the program runs,
naming the nearest name it does know; `val` and `var` are the only things that introduce a name.

The compound forms are `+= -= *= /= %=` and the bitwise `&= |= ^= <<= >>=`. **A compound form
evaluates its place once**, so `xs[next()] += 1` calls `next` a single time.

Three more write the place only under a condition, and they ask the question the operator they are
named after asks:

| form | writes when the place is | so it leaves |
|---|---|---|
| `x ??= v` | absent — `null`, or a read that found nothing | `0`, `""` and `false` alone |
| `x \|\|= v` | false by [truthiness](expressions.md) | everything truthy alone |
| `x &&= v` | true | everything falsy alone |

**The value is not worked out at all where the place is left alone**, which is what these are for
and what `x = x ?? build()` could not promise:

```slate
var cache = { one: null, two: 2 }
var built = 0

build()
    built += 1
    "made"

cache.one ??= build()
cache.two ??= build()

var count = 0
count ||= 10                    // zero is there, so `??=` would have left it

print(cache, built, count)
```

```output
{one: "made", two: 2} 1 10
```

The place is still worked out exactly once whichever way the test goes, so `xs[next()] ??= 1` calls
`next` a single time. They write **one** place: `a, b ??= 1, 2` is refused, a multi-assignment
working out every value before it writes any of them.

`++` and `--` step a name, a field or an element, prefix or postfix.

## `if`

```slate
grade(mark)
    if mark >= 90
        "A"
    elif mark >= 80
        "B"
    else
        "C"

print(grade(95), grade(85), grade(20))
```

```output
A B C
```

The inline form takes `then`, and **its body is a statement, not an expression** — which is the rule
that makes the short forms worth having:

```slate
first_big(xs)
    for x in xs
        if x <= 2 then continue
        if x > 2 then return x

    null

print(first_big([1, 2, 7, 9]), first_big([1, 2]))
```

```output
7 null
```

An `if` is an expression when every branch answers one: `val g = if c then 1 else 2`.

## Loops

Three of them, and **every one is an expression**:

```slate
var c = 3

while c > 0
    c -= 1

for x in [1, 2]
    print(x)

var n = 0

loop
    n += 1

    if n == 2 then break

print(c, n)
```

```output
1
2
0 2
```

`do` introduces a one-line body — `while c do …`, `for x in xs do …`, `loop do …`.

A `for` over a range walks every number it covers, and [`by`](expressions.md#by-gives-a-range-a-step)
is how that range takes a step: `for i in 0..<10 by 2` counts the evens, and `for i in 10..0 by -1`
counts down.

**What a `for` walks is an array, bytes, a string, a range, a generator, a set or a map**, and
anything else is refused naming all seven. A **string** walks its characters, which is what every
other name on a string counts in and what JavaScript's `for...of` yields; a **map** walks its pairs;
a **buffer** walks the number at each position.

```slate
for c in "a👋"
    print(c)
```

```output
a
👋
```

**`for await x in source`** is the fourth, and it walks something that answers `next()` a value at a
time — see [Asynchrony](asynchrony.md).

A `for` head may take its element apart with a [pattern](patterns.md):

```slate
for [k, v] in entries({ a: 1, b: 2 })
    print(k, v)
```

```output
a 1
b 2
```

**An array answers `entries()` too, with the position for a key**, which is how the indexed walk is
written — there is no `for i, x in xs`, a head binding one element:

```slate
for [i, x] in ["a", "b"].entries()
    print(i, x)
```

```output
0 a
1 b
```

### What a loop answers

**`break` is what gives a loop a value.** A loop that finishes on its own answers `null`, or whatever
its `else` clause left:

```slate
find_first(xs, wanted)
    for i in 0..<xs.length do
        if xs[i] == wanted then break i
    else
        -1
end find_first

print(find_first([4, 5, 6], 5), find_first([4, 5, 6], 9))
```

```output
1 -1
```

The `else` clause runs when the loop ended without a `break`, and its value **is** the loop's.

### Labels

A label says which loop a `break` leaves, which is the only way out of a nested one:

```slate
val found = 'search for a in [1, 2, 3]
    for b in [4, 5]
        if a * b == 8 then break 'search [a, b]

print(found)
```

```output
[2, 4]
```

`continue` starts the next turn, and takes a label the same way.

## Blocks

A block's value is its trailing expression. `return` is for leaving a function early and nothing else,
so a function whose last statement is its answer does not write one.

```slate
counter()
    var count = 0

    bump()
        count = count + 1
        count

    bump

val c = counter()

print(c(), c(), c())
```

```output
1 2 3
```

## `throw`

`throw v` is a statement, like `return` and `break` — nothing after it runs, and the value is not
optional. See [Faults](faults.md).

## Closing words

`end if`, `end while`, `end for`, `end loop`, and `end <name>` for a definition, a class or a data
type. All are optional and all are for a block long enough to want one.
