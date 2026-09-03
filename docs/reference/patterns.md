# Patterns

One grammar, used in four places: a `match` arm, an `is` test, a binding (`val { a } = o`), and a
[parameter](functions.md) that takes its argument apart.

## `match`

`match` is postfix — a transformation of the thing to its left. A guard runs after the pattern has
bound:

```
classify(v) = v match
    { kind: "point", at: [0, 0] } -> "origin"
    { kind: "point", at: [x, y] } if x == y -> "diagonal"
    [first, ...rest] -> "a list starting " + string(first)
    "sat" | "sun" -> "a weekend"
    n @ number if n < 0 -> "a negative number"
    _ -> "something else"
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

```
n @ number if n < 0
p @ { x: 0, y }
```

**A broad guard is why this matters.** `n if n < 0` binds *anything*, so the guard evaluates
`[3, 4] < 0` and faults; `n @ number if n < 0` cannot reach the guard with the wrong kind.

## `|` and `&`

`|` is alternation. **No alternative may bind a name**, since it would be bound down one path and not
the other:

```
"sat" | "sun"               // fine
a | b                       // refused: an alternative of a pattern may not bind a name
```

`&` is its dual, binds tighter, and **may** bind — every part of an intersection runs, so both names
are bound down the one path that matched:

```
{ a } & { b } -> s"$a $b"
```

## Object patterns

An object pattern matches an object with **at least** those fields, because a record grows fields over
its life.

```
{ name: n }
{ name }                    // shorthand for `{ name: name }`
{ pinned? }                 // a field the subject need not have
```

**A field a proto supplies counts**, a pattern asking whether the value *has* the field — which is the
question `.` answers.

**`=` is for a pattern that binds and `?` is for one that tests**, and each is refused where the other
belongs.

## Array patterns

An array pattern tests the elements it writes and lets the rest through:

```
[first, ...rest]
[a, b]
["a", 2] is [string, ...]   // true
```

## Bindings

A `val` or a `var` may take its value apart:

```
val { title } = note
val [first, second] = pair
```

## `is`

`is` puts a pattern where a condition is wanted:

```
v is number
v is not string
v is 1 | 3 | 5
v is Point
sq is Square
```

## Exhaustiveness

**Exhaustiveness is checked exactly where the value's shape was written down, and nowhere else.** slate
is dynamically typed, so for an unannotated subject the set of values a name may hold is not known and
nothing useful can be said.

What [`data`](data-types.md) adds is a closed list of variants, so a `match` over a subject annotated
with one is checked against it and **every variant left out is named**:

```
sides(s: Shape) = s match
    Circle(_) -> 0
    Rect(_, _) -> 4
    Empty -> 0
```

A `_` arm is how a program says it has finished listing.

## Class and variant patterns

A [class](classes.md) name or a [data variant](data-types.md) written with fields after it tests and
takes apart in one breath — by position, or by name:

```
tell(v) = v match
    Square(n) -> s"a square of side ${n}"
    Circle { radius: r } -> s"a circle of ${r}"
    Rect { w, h } -> s"${w} by ${h}"
    _ -> "something else"
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

```
type Point = { x: number, y: number }

{ x: 3, y: 4 } is Point     // true
```

**Nothing of a type's structure exists at run time**, so a type costs no instruction. A type may not
bind a name — `type Tagged = { x: n }` is refused — for the reason `|` may not.
