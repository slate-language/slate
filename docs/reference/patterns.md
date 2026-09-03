# Patterns

One grammar, used in four places: a `match` arm, an `is` test, a binding (`val { a } = o`), and a
[parameter](functions.md) that takes its argument apart.

## `match`

`match` is postfix — a transformation of the thing to its left. A guard runs after the pattern has
bound:

```slate
classify(v) = v match
    { kind: "point", at: [0, 0] } -> "origin"
    { kind: "point", at: [x, y] } if x == y -> "diagonal"
    [first, ...rest] -> "a list starting " + string(first)
    "sat" | "sun" -> "a weekend"
    n @ number if n < 0 -> "a negative number"
    _ -> "something else"

print(classify({ kind: "point", at: [0, 0] }))
print(classify({ kind: "point", at: [2, 2] }))
print(classify([9, 1]))
print(classify("sun"))
print(classify(-4))
print(classify(true))
```

```output
origin
diagonal
a list starting 9
a weekend
a negative number
something else
```

Arms are tried in order. **A subject matching no arm is a fault**, as Scala's `MatchError` is.

An arm's body may be an expression or an indented block, and the inline `then` forms work inside one.

## What binds and what tests

**A bare name in a pattern tests for a kind where it names one, and binds otherwise.** The kind words
are:

```
null  boolean  integer  real  number  string  array  object  function
```

plus `promise`, `generator`, `regex`, `shape`, and the eight [temporal](../library/time.md) words —
`instant`, `duration`, `date`, `time`, `dateTime`, `zone`, `zoned`, `period`. That is the whole list:
twenty-one words. Every [type](types.md), [class](classes.md) and [data variant](data-types.md)
declared in the file adds its own name to it.

**None of them is a keyword.** `val int = 3` and `val date = readIt()` are ordinary bindings; the words
are read this way in pattern position and nowhere else. What it costs is real: a `match` arm may no
longer bind a name spelled `date` or `time`.

`number` is the one word that is not a kind, being the union of `integer` and `real`.

**`_` matches anything and binds nothing.**

## `@`

`n @ pat` tests and names at once:

```slate
tell(v) = v match
    n @ number if n < 0 -> s"the negative number ${n}"
    p @ { x: 0, y } -> s"${p} is on the y axis at ${y}"
    _ -> "something else"

print(tell(-4))
print(tell({ x: 0, y: 3 }))
```

```output
the negative number -4
{x: 0, y: 3} is on the y axis at 3
```

**A broad guard is why this matters.** `n if n < 0` binds *anything*, so the guard evaluates
`[3, 4] < 0` and faults; `n @ number if n < 0` cannot reach the guard with the wrong kind.

## `|` and `&`

`|` is alternation. **No alternative may bind a name**, since it would be bound down one path and not
the other:

```slate
print("sun" match
    "sat" | "sun" -> "a weekend"
    _ -> "a working day")
```

```output
a weekend
```

An alternative that binds is refused where it is written:

```slate
print(1 match
    a | b -> 1
    _ -> 2)
```

```error
an alternative of a pattern may not bind a name
```

`&` is its dual, binds tighter, and **may** bind — every part of an intersection runs, so both names
are bound down the one path that matched:

```slate
both(v) = v match
    { a } & { b } -> s"$a $b"
    _ -> "no"

print(both({ a: 1, b: 2 }), both({ a: 1 }))
```

```output
1 2 no
```

## Object patterns

An object pattern matches an object with **at least** those fields, because a record grows fields over
its life.

```slate
type Note = { title: string, pinned?: boolean }

print({ title: "a" } is Note)
print({ title: "a", pinned: true } is Note)
print({ title: "a", pinned: 1 } is Note)        // present, and does not fit
```

```output
true
true
false
```

`{ name: n }` binds `n`, `{ name }` is shorthand for `{ name: name }`, and `{ pinned? }` is a field
the subject need not have.

**A field a proto supplies counts**, a pattern asking whether the value *has* the field — which is the
question `.` answers.

**`=` is for a pattern that binds and `?` is for one that tests**, and each is refused where the other
belongs.

## Array patterns

An array pattern tests the elements it writes and lets the rest through:

```slate
print(["a", 2] is [string, ...])

val [first, ...rest] = [1, 2, 3]

print(first, rest)
```

```output
true
1 [2, 3]
```

## Bindings

A `val` or a `var` may take its value apart:

```slate
val { title } = { title: "t", extra: 1 }
val [first, second] = [10, 20]

print(title, first, second)
```

```output
t 10 20
```

## `is`

`is` puts a pattern where a condition is wanted:

```slate
type Point = { x: number, y: number }

val v = 3

print(v is number, v is not string, v is 1 | 3 | 5)
print({ x: 1, y: 2 } is Point)
```

```output
true true true
true
```

## Exhaustiveness

**Exhaustiveness is checked exactly where the value's shape was written down, and nowhere else.** slate
is dynamically typed, so for an unannotated subject the set of values a name may hold is not known and
nothing useful can be said.

What [`data`](data-types.md) adds is a closed list of variants, so a `match` over a subject annotated
with one is checked against it and **every variant left out is named**:

```slate
data Shape
    Circle(r)
    Rect(w, h)
    Empty

sides(s: Shape) = s match
    Circle(_) -> 0
    Rect(_, _) -> 4
    Empty -> 0

print(sides(Circle(1)), sides(Rect(1, 2)), sides(Empty))
```

```output
0 4 0
```

A variant left out is named where the `match` is written:

```slate
data Shape
    Circle(r)
    Rect(w, h)
    Empty

sides(s: Shape) = s match
    Circle(_) -> 0
```

```error
this match does not cover
```

A `_` arm is how a program says it has finished listing.

## Class and variant patterns

A [class](classes.md) name or a [data variant](data-types.md) written with fields after it tests and
takes apart in one breath — by position, or by name:

```slate
class Square
    var side

class Circle
    var radius

class Rect
    var w
    var h

tell(v) = v match
    Square(n) -> s"a square of side ${n}"
    Circle { radius: r } -> s"a circle of ${r}"
    Rect { w, h } -> s"${w} by ${h}"
    _ -> "something else"

print(tell(Square(3)))
print(tell(Circle(7)))
print(tell(Rect(2, 5)))
print(tell(42))
```

```output
a square of side 3
a circle of 7
2 by 5
something else
```

**The positional order is the constructor's**, and holds by construction: the field list a pattern is
checked against *is* the parameter list of the `new` the class was given.

**Naming the class is also what lets a misspelled field be caught.** A bare `{ raduis: r }` is a legal
pattern that never matches — any object may lack any field — so the arm is silently dead. Written
after a class name there is a declaration to check it against, and it is refused where it stands.

Both forms nest, both take an `@` binding, and the test is the **proto walk** — so a pattern written
for a base class takes an object of a class descended from it apart.

## Types in patterns

A [`type`](types.md) name in pattern position is replaced by the pattern the type declared, while the
program is compiled:

```slate
type Point = { x: number, y: number }

print({ x: 3, y: 4 } is Point)
print({ x: 3 } is Point)
```

```output
true
false
```

**Nothing of a type's structure exists at run time**, so a type costs no instruction. A type may not
bind a name — `type Tagged = { x: n }` is refused — for the reason `|` may not.
