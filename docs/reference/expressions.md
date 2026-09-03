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

## Arithmetic and bitwise

`+ - * / %` over integers and reals; see [Values](values.md) for what `/` does between two integers.
`+` on two strings concatenates.

`| ^ & ~` and the shifts `<< >>` work on 64-bit integers.

## Comparison

**Comparisons chain rather than associate**, which is mathematics' reading and sysl's:

```
0 <= n < 10                 // `n` is evaluated once
```

`==` and `!=` compare by value; see [Values](values.md).

## Logic

`&&` and `||` short-circuit and **answer the operand that decided**, not a boolean:

```
1 && 2                      // 2
null || "x"                 // "x"
```

`??` answers its left operand unless that is `null`:

```
false ?? "d"                // false -- `false` is a value
null ?? "d"                 // "d"
```

## `is`

`is` puts a [pattern](patterns.md) where a condition is wanted, using the same grammar a `match` arm
does:

```
v is number
v is not string
v is 1 | 3 | 5
v is Point
```

It sits between `&&` and the comparisons, so `a is P && b > 0` is two terms.

## Ranges

A range is a **value**:

```
for i in 0..<n              // exclusive
for i in 1..10              // inclusive
xs[1..<3]
"hello"[..2]
```

An end left out is taken from whatever the range is used on. Ranges do not associate, so `a..b..c` is
refused. **`a..=b` is refused by name**, since a reader arriving from Rust writes it once.

## Field and index

`.` reads a field, `[…]` indexes an array, a string or an object.

**`?.` guards its own link and not the rest of the chain**, which is Kotlin's rule:

```
a?.b.c                      // reads `b` off `a` or answers null, then asks `.c` of that
a?.b?.c                     // what the reader means
```

A nullish `a` therefore faults at `.c` in the first line. The rule is the one slate states everywhere
about absence: **it stops at the boundary it arose at**, and one character quietly excusing every link
after it is the opposite of that.

- `o?.m(a)` **does not evaluate its arguments** where there is nothing to call the method on.
- There is no `a?.[i]`.
- `o?.f = v` is refused: there is no answer to what writing into absence should do.

## `with`

`a with b` answers a copy of `a` with `b`'s fields written over it. The right-hand side may be a
literal or any expression answering an object:

```
base with { f: v }
header with claims.header
```

It binds as tightly as a field selection, so `a + b with { … }` changes `b` rather than the sum.

**There is no spread in a literal.** `{ ...o, b: 2 }` is `o with { b: 2 }` and `[...xs, y]` is
`concat(xs, [y])`, both of which slate has, so a second spelling would buy nothing.

## Spread in a call

`f(...xs)` is the one spread slate has, and it exists because a computed argument list had no spelling
at all:

```
total(...xs)
f(a, ...xs, b)              // in any order, any number of times
```

Spreading something that is not an array is a fault naming the spread rather than the call. **The
[checker](types.md) says nothing about a call that spreads**, the argument count being a run-time fact.

## `match`

`match` is postfix — a transformation of the thing to its left, as in Scala and sysl. It is an
**expression**, so it stands where a value is wanted:

```
val what = v match
    { kind: "point", at: [0, 0] } -> "origin"
    [first, ...rest] -> "a list starting " + string(first)
    n @ number if n < 0 -> "a negative number"
    _ -> "something else"
```

See [Patterns](patterns.md) for what an arm may be written with, and for when the arms have to cover
everything.

**A subject matching no arm is a fault**, as Scala's `MatchError` is.

## `catch`

The postfix form of [fault handling](faults.md) is an expression too:

```
val text = readFileSync(path) catch e -> ""

val port = toPort(argument) catch e ->
    print(s"${e.message}, so using the default")
    8080
```

## Blocks

A block's value is its trailing expression, so a lambda or a definition whose body is several
statements answers the last one. `return` is for leaving early and nothing else.

Every [loop is an expression too](statements.md), and `break` is what gives it a value.
