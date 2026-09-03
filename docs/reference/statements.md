# Statements

## Declarations

```slate
val name = "slate"
var n = 0
```

**`val` cannot be assigned to again; `var` can.** A `val` bound to an array or an object still allows
that container to be changed — the binding is what is fixed, not the value.

A [definition](functions.md) is a statement too, and so are `type`, `class` and `data`, each of which
belongs to the top level of a file.

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

### What a loop answers

**`break` is what gives a loop a value.** A loop that finishes on its own answers `null`, or whatever
its `else` clause left:

```slate
find_first(xs, wanted)
    for i in 0..<len(xs) do
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
