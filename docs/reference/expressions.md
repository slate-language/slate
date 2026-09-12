---
title: Expressions
weight: 30
---

# Expressions

## The precedence table

Loosest at the top. Everything is left-associative except the lambda arrow.

| power | operators | |
|---|---|---|
| 5 | `->` | **right**-associative, so `x -> y -> x + y` is a function answering a function |
| 6 | `match`, `catch` | a transformation of the thing to the left |
| 9 | `??` | |
| 10 | `\|\|` | |
| 20 | `&&` | |
| 25 | `is` | |
| 30 | `==` `!=` `<` `<=` `>` `>=` | one level, because a chain of them is one comparison |
| 35 | `..` `..<` | non-associative |
| 35 | `by` | the step of the range on its left |
| 40 | `\|` | |
| 42 | `^` | |
| 44 | `&` | |
| 50 | `+` `-` | |
| 60 | `*` `/` `%` `<<` `>>` | **a shift binds like a multiplication** |
| 80 | `++` `--` (postfix), call, `[…]`, `.`, `?.`, `with` | |

Three placements are worth knowing because they decide what a line means:

- **`match` and `catch` sit below every arithmetic operator**, so `a + b match …` transforms the sum
  rather than just `b`, and `a + b catch …` guards the sum. They sit **above** the arrow, so
  `x -> y match …` gives the lambda a body that matches rather than matching on the lambda.
- **`??` is looser than `||`**, so `a ?? b || c` reads as `a ?? (b || c)`. A program that writes both
  usually means the defaulting to happen last. (JavaScript refuses to mix them without parentheses.)
- **A shift binds like a multiplication**, not like C's, so `1 << 2 + 3` groups the way it reads.
  `&`, `^` and `|` sit above the comparisons, so `a & b == c` is not C's surprise either.

Prefix operators are `-`, `!`, `~`, `++` and `--`, all binding tighter than any infix operator and
looser than a call — `-f(x)` negates the result.

**`_` where a value goes is not an operator and is not in the table**, because what it reaches is
decided by the nearest enclosing argument, bracketed group or right-hand side rather than by a
binding power: `map(xs, _ * 2)` is `map(xs, n -> n * 2)`. See
[Functions](functions.md).

## Arithmetic and bitwise

`+ - * / %` over integers and reals; see [Values](values.md) for what `/` does between two integers.
`+` on two strings concatenates.

`| ^ & ~` and the shifts `<< >>` work on 64-bit integers.

## Comparison

**Comparisons chain rather than associate**, which is mathematics' reading and sysl's:

```slate
val n = 5

print(0 <= n < 10)          // `n` is evaluated once
```

```output
true
```

`==` and `!=` compare by value; see [Values](values.md).

## Logic

`&&` and `||` short-circuit and **answer the operand that decided**, not a boolean:

```slate
print(1 && 2, null || "x")
```

```output
2 x
```

`??` answers its left operand unless that is `null`:

```slate
print(false ?? "d")         // `false` is a value
print(null ?? "d")
```

```output
false
d
```

## `is`

`is` puts a [pattern](patterns.md) where a condition is wanted, using the same grammar a `match` arm
does:

```slate
print(3 is number, 3 is not string, 3 is 1 | 3 | 5)
```

```output
true true true
```

It sits between `&&` and the comparisons, so `a is P && b > 0` is two terms.

## Ranges

A range is a **value**:

```slate
val xs = [1, 2, 3, 4]

print(xs[1..<3])            // exclusive
print(xs[1..2])             // inclusive
print("hello"[..2])         // an end left out is taken from what it is used on
print(xs[2..])
```

```output
[2, 3]
[2, 3]
hel
[3, 4]
```

An end left out is taken from whatever the range is used on. Ranges do not associate, so `a..b..c` is
refused. **`a..=b` is refused by name**, since a reader arriving from Rust writes it once.

### `by` gives a range a step

`by` takes the numbers the range covers down to every *k*th of them. It binds to the range on its
left — looser than `..` and `..<`, tighter than a comparison — so `0..<10 by 1 + 1` steps by two and
`0..<10 by 2 == r` compares the stepped range:

```slate
for x in 0..<10 by 2
    print(x)

print(1..9 by 3, (1..9 by 3).length)
print([10, 20, 30, 40, 50, 60][0..<6 by 2])
```

```output
0
2
4
6
8
1..9 by 3 3
[10, 30, 50]
```

**A negative step runs the range downwards**, and `10..0 by -1` is the countdown a `for` head wants:

```slate
var seen = []

for x in 10..7 by -1
    push(seen, x)

print(seen)
print((0..10 by -1).length, (10..0 by 2).length)
```

```output
[10, 9, 8, 7]
0 0
```

**A step whose sign disagrees with the ends covers nothing** — which is the answer `10..0` gave
before there were steps at all — so those two lengths are zero rather than a complaint.

**A step of `0` is refused**, where it is written if it is a number and where it is worked out if it
is not, since a range that never moves would never reach its end:

```slate
print(0..<10 by 0)
```

```error
a range steps by 0
```

**`by` is a soft word**: it means a step only straight after a range, and is an ordinary name
everywhere else.

```slate
val by = 3

print(by * 2, (0..<12 by by).length)
```

```output
6 4
```

A range whose top is left out takes no step — a word standing where the top belongs is read as that
top, so `0..by` is a range up to what `by` holds.

## Field and index

`.` reads a field, `[…]` indexes an array, a string or an object.

**`?.` guards its own link and not the rest of the chain**, which is Kotlin's rule:

```slate
val a = { b: { c: 1 } }

print(a?.b?.c)
print(a.missing?.c)         // `?.` on the link that may be absent
```

```output
1
null
```

`a?.b.c` reads `b` off `a` or answers `null`, and then asks `.c` of whatever that was — so a nullish
`a` faults at `.c`, and `a?.b?.c` is what the reader means. The rule is the one slate states everywhere
about absence: **it stops at the boundary it arose at**, and one character quietly excusing every link
after it is the opposite of that.

- `o?.m(a)` **does not evaluate its arguments** where there is nothing to call the method on.
- There is no `a?.[i]`.
- `o?.f = v` is refused: there is no answer to what writing into absence should do.

## `with`

`a with b` answers a copy of `a` with `b`'s fields written over it. The right-hand side may be a
literal or any expression answering an object:

```slate
val base = { a: 1, b: 2 }

print(base with { b: 9 })
print(base with { c: 3 })
```

```output
{a: 1, b: 9}
{a: 1, b: 2, c: 3}
```

It binds as tightly as a field selection, so `a + b with { … }` changes `b` rather than the sum.

**There is no spread in a literal.** `{ ...o, b: 2 }` is `o with { b: 2 }` and `[...xs, y]` is
`concat(xs, [y])`, both of which slate has, so a second spelling would buy nothing.

## Spread in a call

`f(...xs)` is the one spread slate has, and it exists because a computed argument list had no spelling
at all:

```slate
show(...parts) = join(parts, "-")
val xs = ["b", "c"]

print(show(...xs))
print(show("a", ...xs, "d"))        // in any order, any number of times
```

```output
b-c
a-b-c-d
```

Spreading something that is not an array is a fault naming the spread rather than the call. **The
[checker](types.md) says nothing about a call that spreads**, the argument count being a run-time fact.

## `match`

`match` is postfix — a transformation of the thing to its left, as in Scala and sysl. It is an
**expression**, so it stands where a value is wanted:

```slate
what(v) = v match
    { kind: "point", at: [0, 0] } -> "origin"
    [first, ...rest] -> "a list starting " + string(first)
    n @ number if n < 0 -> "a negative number"
    _ -> "something else"

print(what({ kind: "point", at: [0, 0] }))
print(what([9, 1]))
print(what(-4))
print(what(true))
```

```output
origin
a list starting 9
a negative number
something else
```

See [Patterns](patterns.md) for what an arm may be written with, and for when the arms have to cover
everything.

**A subject matching no arm is a fault**, as Scala's `MatchError` is.

## `catch`

The postfix form of [fault handling](faults.md) is an expression too:

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

## Blocks

A block's value is its trailing expression, so a lambda or a definition whose body is several
statements answers the last one. `return` is for leaving early and nothing else.

Every [loop is an expression too](statements.md), and `break` is what gives it a value.
