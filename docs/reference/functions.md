---
title: Functions
weight: 60
---

# Functions

**There is no keyword on a function.** The shape is what identifies it: a name, a parameter list in
brackets, and then either `=` and an expression or an indented block.

```slate
double(x) = x * 2

add(a, b)
    a + b

grade(mark)
    if mark >= 90
        "A"
    else
        "C"
end grade

print(double(21), add(1, 2), grade(95), grade(20))
```

```output
42 3 A C
```

A block's value is its trailing expression, so `return` is for leaving early and nothing else.

Functions are values. A definition binds a name in the scope it is written in, so a nested definition
is a closure over that scope:

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

## Lambdas

`->` with the parameters on its left:

```slate
val double = x -> x * 2
val add = (a, b) -> a + b
val zero = () -> 0

print(double(21), add(1, 2), zero())
```

```output
42 3 0
```

`->` is the one right-associative operator, so `x -> y -> x + y` is a function answering a function.

**A lambda's body may be a block, written where the lambda is passed.** A newline inside brackets
normally means nothing, so a callback would otherwise have to be lifted out and named before the call
that wanted it:

```slate
forEach([1, 2, 3], x ->
    val doubled = x * 2
    print(x, doubled))
```

```output
1 2
2 4
3 6
```

`->` and `match` are the two tokens that suspend the bracket rule, and only where they end a line.
**A block lambda has to be the last argument**, because its block runs to the end of its last line and
a `,` arriving there has nothing to mean. Every callback slate itself takes is last for that reason;
`setTimeout(fn, ms)` keeps node's order and so takes a one-line function.

A lambda's parameters may be annotated; its result may not, the arrow already standing between the
parameters and the body. What it answers is read off that body — see [Types](types.md).

## `_`, a lambda with its parameter left out

A `_` where a value goes is the parameter of a function nobody wrote. What that function's *body* is
is the smallest thing around the `_`: a call's argument, a bracketed group, or the value of a
binding, an assignment or a `return`.

```slate
val ns = [1, 2, 5, 9]

print(map(ns, _ * 2))
print(filter(ns, _ > 3))
print(map(["ada", "grace"], upper(_)))
```

```output
[2, 4, 10, 18]
[5, 9]
["ADA", "GRACE"]
```

**Every `_` is a parameter of its own, left to right.** Two of them make a function of two
parameters, which is exactly what a comparator wants:

```slate
val people = [{ name: "grace", age: 45 }, { name: "ada", age: 36 }]

print(map(sorted(people, _.age < _.age), _.name))
```

```output
["ada", "grace"]
```

**That rule is also this notation's one surprise.** `_ > 3 && _ < 9` is a function of *two*
parameters and not one test of one number, so it is refused where a callback taking one was wanted.
Write the parameter out when you mean to mention it twice: `n -> n > 3 && n < 9`.

**A lone `_` is handed outward to the thing around it**, which is what makes `f(_)` a way of naming
`f` rather than a way of handing it an identity — and what makes `add(_, 1)` the partial application
it reads as. Where there is nothing around it, a `_` on its own is the identity function:

```slate
add(a, b) = a + b

print(map([1, 2, 3], add(_, 1)))

val id = _

print(id(7))
```

```output
[2, 3, 4]
7
```

A `_` with no argument, no group and no right-hand side around it has nothing for its function to
be, and is refused where it stands:

```slate
_.length
```

```error
`_` stands for the parameter of a function
```

**`_` in a pattern is untouched.** A match arm's `_`, a destructuring's and the name in `val _ =
f()` all mean the wildcard they always did — the notation here is about `_` standing where a
*value* goes.

## Type parameters

`[T]` after the name says the definition is generic over a type, and the answer is said in terms of
what the call was given:

```slate
first[T](xs: array of T) -> T = xs[0]

print(first(["ada", "grace"]), first([1, 2]))
```

```output
ada 1
```

There are no type arguments at a call — they are solved from the arguments, and every argument has to
fit the type the parameter was solved to, so `pair(1, "x")` for `pair[T](a: T, b: T)` is refused.
[Types](types.md) says how the answer is picked and what a union does.

## Defaults

A parameter may carry what it is when nobody gives one, on a definition, a lambda, a method, or a
class's `new`. The annotation comes first and the default after it:

```slate
greet(name, greeting = "hello") = greeting + ", " + name
f(n: integer = 0) = n

print(greet("ada"))
print(greet("ada", "hi"))
print(f(), f(7))
```

```output
hello, ada
hi, ada
0 7
```

**The default is worked out at the call, not where the function was written.** Everything else follows
from that:

- `f(xs = [])` gives every call an array of its own.
- A default may read the parameters to its left: `slice(xs, from, to = xs.length)`.
- A default that would fault costs nothing to a call that gave the argument.

**A parameter that may be left out has to come last**, or leaving it out would slide every later
argument one place left. The parser says so where it is written, and an arity complaint then names a
**range** rather than only its upper end.

**A parameter nobody gave is not bound at all**, which is why there is no sentinel: slate refuses to
store absence, so there is no "given, and the value was absence" to tell from "not given". `f(1, null)`
therefore passes `null` and does **not** take the default — which is the simpler rule, JavaScript's
`f(1, undefined)` doing the opposite.

## Named arguments

An argument may say which parameter it fills, which is what makes a default in the *middle* reachable:

```slate
greet(name, greeting = "hello", punct = "!") = greeting + ", " + name + punct

print(greet("ada"))
print(greet("ada", punct = "?"))            // greeting skipped
print(greet(greeting = "hi", name = "ada"))
```

```output
hello, ada!
hello, ada?
hi, ada!
```

**`=` and not `:`**, because the declaration already writes the default after an equals. Assignment is
a statement in slate, so `=` never appears inside an expression and there is nothing for it to be
confused with; `==` is its own token, so `f(ok == true)` is an ordinary positional argument.

A name comes after every positional argument, and it may pick out any parameter. A class's `new` and a
data variant's maker are ordinary functions, so `Rect(h = 4, w = 3)` and `Circle(r = 7)` read the same
way. **A method names its parameters and not its receiver.**

Naming a parameter twice, naming one the function does not have, naming an argument to a builtin, or
naming one to a function that gathers with `...` are each refused with their own sentence — the second
lists the parameters it does have.

## `...rest`

A function may gather what is left over:

```slate
total(first, ...others) = reduce(others, (a, b) -> a + b, first)
val xs = [1, 2, 3]

print(total(1))
print(total(1, 2, 3))
print(total(...xs))         // the spread it is the counterpart of
```

```output
1
6
6
```

**`...rest` is always bound**, to an empty array where a call gave nothing past the fixed parameters,
so there is no absence to test for. It must be last and takes no default — one could never fire. A
default *before* it is fine.

## A function takes as many arguments as it declares, and the rest are dropped

**A call may give more than the function declares. The surplus is dropped**, wherever the call is
written and whoever is making it:

```slate
f(a) = a
val g = (a, b) -> a + b

print(f(1, 2, 3))
print(g(1, 2, 3))
print(map([1, 2, 3], v -> v * 2))
print(map([1, 2, 3], () -> 9))
```

```output
1
3
[2, 4, 6]
[9, 9, 9]
```

This is JavaScript's rule and TypeScript's, and it is what lets a function be used wherever a wider
one is wanted. It is what a handler wants to look like — `on(node, "click", () -> setCount(n + 1))`
for one that does not read the event, `onData(socket, () -> stop())` for a reader that does not care
what arrived — and it holds everywhere something calls a function you wrote: array walks, `sorted`,
timers, sockets, WebSocket handlers, [the document](../library/dom.md)'s events, a method reached
off an object, a function [handed out to a JavaScript host](external.md).

```slate
setTimeout(() -> print("later"), 0)

on2(f) = f(1, 2)

print(on2(a -> a))
```

```output
1
later
```

**Too FEW is still a fault**, and that is not the same question: a parameter with no default has
nothing to bind, and slate stores no absence, so there is no value to give it. Give it a
[default](#defaults) where leaving it out is meant to be allowed.

```slate
f(a, b) = a + b

print(f(1))
```

```error
`f` takes 2 arguments and this gives it 1
```

**A builtin is the exception**, because its parameters are not slate's: it cannot drop what it was
given, and says so.

```slate
print(chars("a", "b"))
```

```error
`chars` takes 1 argument and this gives it 2
```

**So a function declaring MORE than its caller will supply is still refused, and the complaint names
the caller**, your function not being the thing that is wrong:

```slate
map([1], (a, b, c, d) -> a)
```

```error
`map` takes (integer, integer, array of integer) -> any here, and this is (integer, integer, array of integer, any) -> integer
```

That is the checker, which knows what `map` hands over — the element, its position and the array, so
three is what there is and a fourth parameter has nothing to fill it. Reached through a value it
cannot see, the machine says the same thing in its own words — *"`map` calls this with 3 arguments
and it takes 4 arguments"*.

The same rule read as a type: a function of fewer parameters fits wherever more are supplied, and
one of more does not.

```slate
apply(f: (integer) -> integer) = f(1)

print(apply((a, b) -> a))
```

```error
`apply` takes (integer) -> integer here, and this is (any, any) -> any
```

## Destructuring parameters

A parameter may take its argument apart, on a definition or a lambda:

```slate
f({ n }) = n * 2
val g = ({ n }) -> n + 1

print(f({ n: 21 }), g({ n: 1 }))
```

```output
42 2
```

The pattern is any [pattern](patterns.md) that binds.

## Annotations

Per parameter, and per result:

```slate
type Point = { x: number, y: number }

double(x: number) -> number = x * 2
f(a, b: Point, c) = b.x + a + c     // nothing has to be annotated for anything to be

print(double(3), f(1, { x: 2, y: 0 }, 3))
```

```output
6 6
```

An annotation is checked **at the call** for a parameter, and where the function answers for a result.
See [Types](types.md) for what the compiler will say about one before the program runs.

## `async` and generators

`async` in front of a definition or a lambda makes it answer a promise; a function holding a `yield` is
a generator, with no word on the definition. Both are in [Asynchrony](asynchrony.md).

## Methods

A function stored in an object field is a method. Whether it is handed a receiver depends on where it
was found — see [Objects](objects.md).
