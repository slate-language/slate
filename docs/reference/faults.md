---
title: Faults
weight: 130
---

# Faults

slate has **two failure channels**, and which one a thing uses says what kind of failure it is.

- **A result** — `{ ok: true, value: v }` or `{ ok: false, error: text }` — is for a condition the
  caller was always going to deal with: a file that is not there, a connection refused, text that will
  not parse, a password that does not match. The caller is handed something it has to look at.
- **A fault** unwinds until something catches it, and is for a defect in the program: the wrong kind of
  argument, a division by zero, a value with no JSON form, an index past the end.

Neither is used for the other's job anywhere in slate. `readFile(42)` **faults**; `readFile("/gone")`
**answers**.

A result costs no new machinery — it is an ordinary object, so [`match`](patterns.md) already
destructures one and the collector already traces one.

## `throw`

`throw v` is a **statement**, like `return` and `break`: nothing after it runs, and the value is not
optional — a fault with nothing in it says nothing to whoever catches it.

```slate
side(w)
    if w < 0 then throw "a side cannot be negative"

    w

print(side(3))
print(side(-1))
```

```error
a side cannot be negative
```

**`throw` takes any value at all, and what it carries is what the handler is given.** A **string** is a
sentence and nothing else, so it arrives at a `catch` as the [fault object](#the-fault-object) below —
which is what it has always done. **Anything else travels whole**: a [data](data-types.md) variant, a
[class](classes.md) instance, a number, an object, so a handler can sort faults by what went wrong
rather than by reading a sentence. That is [the next section](#throwing-a-value-and-catching-what-it-is).

**A caught fault re-thrown keeps its own words.** `throw e` reads an object's `message` field rather than
rendering it — rendering would replace the fault with a *description* of one. A string is its own
message; anything else is written the way `print` writes it, so a class that wrote a `toString` says
what its own fault says:

```slate
class NotFound
    var id

    toString(self) = s"no row with id ${self.id}"

throw NotFound(3)
```

```error
no row with id 3
```

**That sentence is the one place in slate a diagnostic runs the program's own code**, and a `toString`
that faults in turn is not allowed to replace the fault the program actually threw: where it does, the
ordinary rendering is what the report falls back to.

**Where a re-thrown fault is REPORTED from becomes the `throw`'s own and does not travel.** By the time a
program holds a fault it is a line number and a file name, which no span can be rebuilt from — so a
re-thrown fault says the words of the original and is reported against the line that put it back.

**What it CARRIES is untouched**, which is the other half of the same rule: `throw e` puts back the very
value that was caught, so a fault object's own `line` and `file` still say where it was raised, and a
thrown value's fields are the program's own. A re-throw may not change what was caught.

## `catch`

Two forms of one thing. **The postfix one is an expression**, so it stands where a value is wanted:

```slate
toPort(text)
    val n = number(text)

    if n == null then throw "that is not a port"

    n

val port = toPort("nonsense") catch e ->
    print(s"${e.message}, so using the default")
    8080

print(port)
```

```output
that is not a port, so using the default
8080
```

and the block one is for a run of statements:

```slate
setUp() = print("set up")

go()
    throw "it went wrong"

try
    setUp()
    go()
catch e
    print(e.message, e.line, e.file is string)
```

```output
set up
it went wrong 4 true
```

`catch` binds looser than every arithmetic operator, so `a + b catch …` guards the sum, and tighter than
the lambda arrow, so `x -> risky() catch e -> 0` gives the lambda a body that guards.

## Sorting faults out: a `catch` takes a pattern

**What follows `catch` is a pattern** — any pattern a [`match`](patterns.md) arm may carry, with the
same optional `if` guard. A bare name is a pattern that matches everything, which is why every
`catch` written before this still means what it did.

**The block form takes as many clauses as you like and tries them in order:**

```slate
risky(n)
    if n == 0 then throw "empty"
    if n > 99 then throw "too big"

    n

look(n)
    try
        print(risky(n))
    catch { message: "empty" }
        print("nothing there")
    catch e if e.message == "too big"
        print("out of range")
    catch e
        print(s"other: ${e.message}")

look(0)
look(500)
look(7)
```

```output
nothing there
out of range
7
```

**A fault no clause wanted is thrown again**, so a run of clauses is a filter rather than a `try`
that swallows — the enclosing handler, or the program's own end, gets it:

```slate
go()
    throw "not one of them"

try
    go()
catch { message: "expected" }
    print("handled")
```

```error
not one of them
```

It keeps the fault's own words, and is **reported against the `catch`** that let it past — which is what
[`throw`](#throw) says everywhere else. What the clauses were offered is handed on unchanged.

**A clause matches WHAT WAS THROWN.** For a string, and for a fault the language itself raised, that is
the [fault object](#the-fault-object) — `message`, `line` and `file` — which is what the clauses above
take apart. For a `throw` of anything else it is that value itself, which is what lets a clause name a
type.

**The postfix form takes one clause**, there being nowhere to write a second — the arrow's body runs
to the end of the expression. A fault worth sorting into several clauses is what the block form is
for.

```slate
risky()
    throw "gone"

val n = risky() catch { message: "gone" } -> 0

print(n)
```

```output
0
```

## Throwing a value, and catching what it is

**A fault that carries a value is one a handler can sort by what went wrong**, rather than by reading a
sentence somebody wrote for a person. The value is often a [`data`](data-types.md) type — the closed set
of the things this code can fail at — and a clause is a pattern over it, exactly as a `match` arm is:

```slate
data Failure
    NotFound(id)
    Denied(who)

read(id)
    if id == 0 then throw NotFound(id)
    if id == 1 then throw Denied("guest")

    s"row ${id}"

look(id)
    try
        print(read(id))
    catch NotFound(which)
        print(s"no row ${which}")
    catch Denied(who)
        print(s"${who} may not read that")

look(0)
look(1)
look(2)
```

```output
no row 0
guest may not read that
row 2
```

**The clause binds the value itself**, so `which` above is the number the fault was made with and not a
field of some wrapper around it. Nothing is built on the way out and nothing is unwrapped on the way in.

**A value no clause wanted is thrown again**, which is the rule a run of clauses already had — so an
enclosing handler gets it:

```slate
data Failure
    NotFound(id)
    Denied(who)

go()
    throw Denied("guest")

try
    try
        go()
    catch NotFound(which)
        print("not found")
catch Denied(who)
    print("outer saw", who)
```

```output
outer saw guest
```

and with nothing around it, the program's own end reports the value:

```slate
data Failure
    NotFound(id)

throw NotFound(3)
```

```error
NotFound(3)
```

## The fault object

**A `throw` of a string, and every fault the language itself raises, is handed over as an ordinary
object** — `message`, `line` and `file` — for the same reason a module is one: slate objects already
sort, print, go in arrays and match against patterns, so there is nothing here the rest of the language
does not already do. A thrown string has nothing in it a handler could sort on, which is why it is the
one kind of value that arrives as a description of itself rather than as itself.

```slate
risky()
    throw "gone"

recover() = "recovered"

try
    print(risky())
catch e
    print(e match
        { message: "gone" } -> recover()
        _ -> "something else")
```

```output
recovered
```

**A fourth field, `suppressed`, is there only where a resource failed to release while this fault was
already travelling.** The fault the program was told about is the one it was going to be told about
either way; the release's own complaint is a field of it rather than a replacement for it. See
[`using`](statements.md).

**A fault carrying a VALUE has no such field**, and cannot: the thing a handler is given is the
program's own value, so writing a field into it would change something the program is still holding.

## What `catch` does and does not reach

- **It works across an `await`.** A coroutine carries its handlers with it when it is set aside, so a
  promise that fails minutes later still raises inside the `try` that was written around the `await`.
  See [Asynchrony](asynchrony.md).
- **It does not reach a callback.** `try setTimeout(...)` guards the scheduling and nothing else, the
  callback running from the loop long afterwards. That is inherent: there is no statement of the
  program's left to attach it to.

## What is not here

**There is no `finally`.** A `try` with nothing to handle the fault is refused rather than allowed to
swallow it silently.

**What a `finally` is usually reached for is a resource, and that is [`using`](statements.md)** — a
binding whose value is released when the block around it is left, by every route out including a
fault travelling past. It says the release at the line that acquired the thing, which is the half a
`finally` never had: the two stand together and a branch added later cannot separate them.
