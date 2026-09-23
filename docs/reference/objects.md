---
title: Objects
weight: 80
---

# Objects

An object is a collection of fields.

```slate
print({ name: "ada", born: 1815 })
print({ "two words": 1 })
print({})
```

```output
{name: "ada", born: 1815}
{"two words": 1}
{}
```

**A field is written `key: value`, and `{ name }` is shorthand for `{ name: name }`.** It is the same
spelling an [object pattern](patterns.md) has, read the other way round: on the left of an `=` it takes
a field apart, and on the right it puts one together.

```slate
val name = "ada"
val born = 1815

print({ name, born })
print({ name, born, alive: false })
```

```output
{name: "ada", born: 1815}
{name: "ada", born: 1815, alive: false}
```

**A shorthand needs a name a program could bind**, so a [keyword](lexical.md) and a quoted key each have
to say what their value is; and `{ name? }`, which marks a field a *pattern* need not find, is a pattern's
spelling and means nothing in a literal.

```slate
print({ if })
```

```error
is a word the grammar has taken
```

**A key in a literal is a name or a string**, and nothing else — a number there is a parse error. A key
written through an index may be **any value**, and stays that value:

```slate
var q = {}

q[42] = "answer"

print(q, q[42])
```

```output
{42: "answer"} answer
```

That is why [`toJSON`](../library/globals.md) refuses a non-string key rather than rendering it: `{ 1: "a" }`
and `{ "1": "a" }` are two objects and would be one document.

Objects are reference types and [compare by their contents](values.md).

`keys(o)`, `values(o)`, `entries(o)` and `has(o, k)` are how a program walks one; `entries` is what
makes a destructuring `for` head worth having:

```slate
val o = { a: 1, b: 2 }

print(keys(o), values(o), has(o, "a"))

for [k, v] in entries(o)
    print(k, v)
```

```output
["a", "b"] [1, 2] true
a 1
b 2
```

**`has` is the presence test, and it is the only one.** A field holding `null` and a field that is not
there both answer true to `== null` — [the one special case in `==`](values.md) — so where the
difference matters, `has` is what draws it.

`o with { f: v }` answers a **copy** with `f` changed. There is no spread in a literal — `with` is it.

**The braces after `with` are read exactly as a literal's are, shorthand and all**, so `o with { x }` is
`o with { x: x }` and a keyword, a quoted key and a `name?` each say what to write instead there too:

```slate
val x = 1
val y = 2
val base = { a: 9, x: 0 }

print(base with { x })
print(base with { x, y })
print(base with { x, y: 7 })
print(base)
```

```output
{a: 9, x: 1}
{a: 9, x: 1, y: 2}
{a: 9, x: 1, y: 7}
{a: 9, x: 0}
```

```slate
val o = { a: 1 }

print(o with { if })
```

```error
is a word the grammar has taken
```

## `freeze` and `isFrozen`

**`freeze(v)` closes a value to writing and answers the very value it was given.** Reads are
untouched; every write is refused with a sentence naming what was refused and where the copy is:

```slate
val settings = freeze({ port: 8080, host: "localhost" })

print(settings.port, isFrozen(settings))

settings.port = 9090
```

```error
`port` belongs to a frozen value
```

It closes an object, an array, a set, a map, a buffer and a weak map. **A value with nothing to write
through answers itself** — a number, a string, a function — and `isFrozen` says `true` of one, so
`isFrozen(freeze(x))` holds for every `x`. Freezing twice is a no-op, which is what lets a constructor
freeze what it was handed without asking whether somebody else did.

**It is shallow, which is JavaScript's rule**, and the rule worth stating: freezing an object says
nothing about the objects its fields hold. A program that wants the whole graph walks it itself.

**A copy is free to change**, which is what every refusal points at — `with` and a spread for an
object, `[...xs]` for an array, `Set(s)` and `Map(m)` for the two collections:

```slate
val base = freeze({ port: 8080 })
val mine = base with { port: 9090 }

mine.port = 3000

val xs = freeze([1, 2])
val ys = [...xs]

push(ys, 3)

print(mine.port, isFrozen(mine), ys, isFrozen(xs))
```

```output
3000 false [1, 2, 3] true
```

A [data variant](data-types.md) is frozen without anybody having called `freeze`, and says so
differently — its refusal names `with` as the line to write *instead*, where a frozen value's names it
as the way back to something writable.

## `proto`

**`proto` is an ordinary field, and a lookup that misses carries on into it:**

```slate
val Shape = {
    describe: self -> s"${self.kind} with area ${self.area()}",
    kind: "shape"
}

val Square = { proto: Shape, kind: "square", area: self -> self.side * self.side }

square(side) = { side: side, proto: Square }

print(square(4).describe())
```

```output
square with area 16
```

**No syntax and no new kind of value.** A proto may have a proto, so chains and overriding come free;
`describe` lives on `Shape` and calls `area`, which only the concrete shapes have, so the call goes back
down to whichever object it started from. That is dispatch, and it needed no keyword.

**It is also what makes objects affordable.** Three methods written as captured closures cost three
closures *per instance*; on a proto they cost three once.

An [object pattern](patterns.md) counts a field a proto supplies, a pattern asking whether the value
*has* the field — which is the question `.` answers. (JavaScript splits the same seam and puts `in` on
this side of it.)

## The receiver rule

**A method reached through a proto is handed the object it was found on.** One `describe` serves every
shape, so it cannot have captured a particular one — it has to be told, and `self` is an ordinary first
parameter.

**A method stored on the object itself has already captured what it needs and is given nothing extra:**

```slate
counter()
    var n = 0
    var c = {}

    c.bump = () ->
        n += 1
        n

    c

val c = counter()

print(c.bump(), c.bump())
```

```output
1 2
```

That is not two rules but one: **captured methods take no receiver, shared ones must.**

**Only `o.m(...)` passes a receiver.** `o.m` on its own hands back the bare function, so taking a method
off an object and calling it later is allowed and gives you what you took.

## Operator methods

An object may answer for an operator, and **the operator is the method's name**. A
[class](classes.md) body writes one with the definition syntax it already has, so the definition and
every call that reaches it read alike:

```slate
class Money
    var cents

    +(self, o)   = Money(self.cents + o.cents)
    *(self, n)   = Money(self.cents * n)
    unary_-(self) = Money(-self.cents)
    <=>(self, o) = self.cents - o.cents      // `<`, `<=`, `>` and `>=` read its sign

    toString(self) = "$" + string(self.cents \ 100)

val a = Money(150)
val b = Money(50)

print(a + b, a * 2, -a)
print(a < b, a > b)
```

```output
$2 $3 $-1
false true
```

| method | operator |
|---|---|
| `+` | `+` |
| `-` | `-` |
| `*` | `*` |
| `/` | `/` |
| `\` | `\` |
| `%` | `%` |
| `unary_-` | prefix `-` |
| `<`, `<=`, `>`, `>=` | those four, each on its own |
| `<=>` | all four of them, from one method |
| `==` | `==`, and `!=` as its opposite |
| `hash` | a table key |

**`unary_-` is spelled apart from `-`** because it takes no other side: a class whose `-` has two
operands has said nothing about what `-v` should be.

**Nothing else may be named.** The bitwise operators, `&&` and `!` are all questions about bits or
about truth, which is not a thing a value object has an opinion on, and a class body naming one is
refused where it is written.

**A class orders itself in one of two ways and never both.** Either it writes the four comparisons,
each saying exactly what that operator means for it, or it writes `<=>` and lets all four read the
sign of one number:

```slate
class Version
    var n

    <(self, o)  = self.n < o.n
    <=(self, o) = self.n <= o.n
    >(self, o)  = self.n > o.n
    >=(self, o) = self.n >= o.n

print(Version(1) < Version(2), Version(2) <= Version(2))
```

```output
true true
```

Writing both is refused, the two being two chances for a type to order inconsistently with itself:

```slate
class Version
    var n

    <(self, o)   = self.n < o.n
    <=>(self, o) = self.n - o.n
```

```error
writes one or the other
```

**`==` is a method of its own and is not routed through `<=>`**, because a type whose ordering is
coarser than its equality — a case-insensitive name, a version with build metadata — is an ordinary
thing to want. **`!=` is always the opposite of `==` and a class may not write one:**

```slate
class Tag
    var t

    !=(self, o) = true
```

```error
is always the opposite of
```

**The left operand decides and the right is never asked** — `a.equals(b)`'s rule already — so there
is no reflected form and `2 * money` is a fault.

**A method is the last thing tried**, so none can shadow what an operator already means.

**An operator method is an ordinary member**, so `a.+(b)` calls what `a + b` calls and a word-named
method has no operator meaning at all: a class writing `plus` has written a method called `plus`.

A type that writes `==` should write `hash` beside it, or two equal values will not find each other
in a table.

## `toString` and `toJSON`

A class may say how it **prints** and how it **encodes**, which is what a value object needs to stop
leaking the fields it is made of:

```slate
class Money
    var cents

    toString(self) = "$" + string(self.cents \ 100)
    toJSON(self)   = string(self.cents \ 100)

print(Money(150))
print(toJSON({ paid: Money(150) }))
```

```output
$1
{"paid":"1"}
```

**Both replace everything below them at every depth**, so a value inside an array or a response body
renders the way its class says rather than only when printed on its own.

Without `toJSON`, a class instance and a [data variant](data-types.md) encode as their own fields —
`Circle(3)` is `{"r":3}` — and never as the chain they hang from.

## Identity

**The proto is the identity**, and [`class`](classes.md) is what lets `is` ask about it. Written by
hand, `p.proto == Point` is the closest an object literal gets — and it is not quite `instanceof`: `==`
on objects is deep, so it answers true for anything holding the same fields, and it looks exactly one
link up the chain.
