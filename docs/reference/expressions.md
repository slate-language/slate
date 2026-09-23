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
| 60 | `*` `/` `\` `%` `<<` `>>` | **a shift binds like a multiplication** |
| 80 | `++` `--` (postfix), call, `[…]`, `.`, `?.`, `?.[`, `?.(`, `with` | |

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

`+ - * / %` over integers and reals, and `\` over integers alone. **`/` answers a real whatever it
was handed and `\` is the whole-number division**; see [Values](values.md) for the pair and for what
each does by zero. `+` on two strings concatenates.

`| ^ & ~` and the shifts `<< >>` work on integers, of any width — they read a value as an endless
run of two's-complement bits, so `~x` is `-x - 1`, `<<` grows and `>>` floors. See
[Values](values.md).

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

**`?.` guards the whole chain after it**, which is JavaScript's rule:

```slate
val a = { b: { c: { d: 1 } } }
val gone = { }

print(a?.b.c.d)
print(gone.missing?.b.c.d ?? "none")
```

```output
1
none
```

The **run of links** is what the character guards, not the one link it was written on. Where the
left is null or absent, every `.`, `[…]` and `(…)` after it is skipped — nothing along the rest of
the chain is worked out at all — and the expression answers `null`.

There are **three** guarded links, and each one opens a chain that reaches to the end of the run:

| written | guards | where the left is there |
|---|---|---|
| `o?.f` | `o` | reads `f` off it |
| `xs?.[i]` | `xs` | reads `i` out of it — the key is not worked out otherwise |
| `f?.(a)` | `f` | calls it — the arguments are not worked out otherwise |

```slate
val holder = { xs: [10, 20], go: n -> n * 2 }
val empty = { }
val deep = { rows: [{ pick: () -> "here" }] }

print(holder.xs?.[1])
print(holder.go?.(21))
print(empty.xs?.[1] ?? "none")
print(empty.go?.(21) ?? "none")
print(deep?.rows[0].pick())
```

```output
20
42
none
none
here
```

### What a chain does NOT guard

**A guard answers for the absence it was written about and for no other.** A link *after* it that
finds a nullish value of its own faults there, exactly as it would with no `?.` in the line:

```slate
val a = { b: null }

print(a?.b.c)
```

```error
there is nothing here to read `c` from
```

`a?.b?.c` is what says both may be missing. So a chain is read link by link: each `?.` marks one
place a value may not be there, and marks it once.

**Brackets end a chain.** `(a?.b)` is a chain that is over, so what follows the brackets asks the
answer it gave:

```slate
val a = null

print((a?.b).c)
```

```error
there is nothing here to read `c` from
```

### The rest of the rules

- **A guard answers for an ABSENCE and never for a wrong kind.** `f?.()` where `f` holds a `3`
  faults exactly as `f()` would; the character says *this may not be here*, not *this may be
  anything*.
- `o.m?.()` reads `o.m` as the value it is and calls that, which is what `o.m` means everywhere
  else in the language. **`o?.m()` is the spelling that guards the object** and calls `m` as its
  method.
- **Nothing in the skipped part runs** — not a key, not an argument, not a call:

```slate
var calls = 0

side() =
    calls += 1
    0

val gone = null

print(gone?.rows[side()].pick(side()) ?? "none")
print(calls)
```

```output
none
0
```

- `o?.f = v` and `xs?.[i] = v` are refused: there is no answer to what writing into absence should
  do.

```slate
val xs = null

xs?.[0] = 1
```

```error
cannot be assigned to
```

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

## Spread

`f(...xs)` exists because a computed argument list had no spelling at all, and an array literal and
an object literal take one too — `[...xs, y]` is `concat(xs, [y])` written the way a reader expects,
and `{ ...o, b: 2 }` is `o with { b: 2 }`:

```slate
show(...parts) = join(parts, "-")
val xs = ["b", "c"]
val o = { a: 1 }

print(show(...xs))
print(show("a", ...xs, "d"))        // in any order, any number of times
print([...xs, "d"], { ...o, b: 2 })
```

```output
b-c
a-b-c-d
["b", "c", "d"] {a: 1, b: 2}
```

**What may be spread is exactly what a [`for`](statements.md#loops) walks and what `array(x)` takes:
an array, bytes, a range, a generator, a set or a map.** A map spreads its pairs and a buffer the
number at each position; a generator is run out, which is the only way there is to know what it
holds. A **string** is deliberately not on that list — `chars(s)` is how slate spells one as its
characters, and a spread that flattened text would be a surprise in every program that meant to pass
one string.

```slate
counting()
    yield 1
    yield 2

print([...0..<3], [...counting()], [...Set(["a"])])
```

```output
[0, 1, 2] [1, 2] ["a"]
```

Spreading anything else is a fault naming the spread rather than the call, because that is where the
reader has to look. **The [checker](types.md) says nothing about a call that spreads**, the argument
count being a run-time fact.

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
