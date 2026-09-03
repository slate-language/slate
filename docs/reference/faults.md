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

**A caught fault re-thrown keeps its own words.** `throw e` reads an object's `message` field rather than
rendering it — rendering would replace the fault with a *description* of one. A string is its own
message; anything else is rendered as `print` would.

**The location becomes the `throw`'s own and does not travel.** By the time a program holds a fault it is
a line number and a file name, which no span can be rebuilt from — so a re-thrown fault says the words of
the original and points at the line that put it back.

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

## The fault object

**A fault is an ordinary object** — `message`, `line` and `file` — for the same reason a module is one:
slate objects already sort, print, go in arrays and match against patterns, so there is nothing here the
rest of the language does not already do.

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
