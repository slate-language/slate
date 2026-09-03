# Statements

## Declarations

```
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

```
n = 3
xs[i] = v
o.f = v
a, b = b, a                 // several places at once
```

**Assignment binds nothing.** `g = 1` where `g` was never declared is refused before the program runs,
naming the nearest name it does know; `val` and `var` are the only things that introduce a name.

The compound forms are `+= -= *= /= %=` and the bitwise `&= |= ^= <<= >>=`. **A compound form
evaluates its place once**, so `xs[next()] += 1` calls `next` a single time.

`++` and `--` step a name, a field or an element, prefix or postfix.

## `if`

```
if mark >= 90
    "A"
elif mark >= 80
    "B"
else
    "C"
```

The inline form takes `then`, and **its body is a statement, not an expression** — which is the rule
that makes the short forms worth having:

```
if n > 2 then break
if n > 2 then return x
if n > 2 then continue
```

An `if` is an expression when every branch answers one: `val g = if c then 1 else 2`.

## Loops

Three of them, and **every one is an expression**:

```
while c
    body

for x in xs
    body

loop
    body
```

`do` introduces a one-line body — `while c do …`, `for x in xs do …`, `loop do …`.

A `for` head may take its element apart with a [pattern](patterns.md):

```
for [k, v] in entries(o)
    print(k, v)
```

### What a loop answers

**`break` is what gives a loop a value.** A loop that finishes on its own answers `null`, or whatever
its `else` clause left:

```
find_first(xs, wanted)
    for i in 0..<len(xs) do
        if xs[i] == wanted then break i
    else
        -1
end find_first
```

The `else` clause runs when the loop ended without a `break`, and its value **is** the loop's.

### Labels

A label says which loop a `break` leaves, which is the only way out of a nested one:

```
'search for a in xs
    for b in ys
        if a * b == 8 then break 'search [a, b]
```

`continue` starts the next turn, and takes a label the same way.

## Blocks

A block's value is its trailing expression. `return` is for leaving a function early and nothing else,
so a function whose last statement is its answer does not write one.

```
counter()
    var count = 0

    bump()
        count = count + 1
        count

    bump
```

## `throw`

`throw v` is a statement, like `return` and `break` — nothing after it runs, and the value is not
optional. See [Faults](faults.md).

## Closing words

`end if`, `end while`, `end for`, `end loop`, and `end <name>` for a definition, a class or a data
type. All are optional and all are for a block long enough to want one.
