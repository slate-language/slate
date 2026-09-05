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
- A default may read the parameters to its left: `slice(xs, from, to = len(xs))`.
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

## Callbacks take as many arguments as they declare

**A call the program writes is strict**: `f(1, 2)` where `f` takes one argument is refused, and so is
`f()` where it takes one. The count is a claim you made, and getting it wrong is a mistake.

**A callback is different.** Where a builtin calls a function *you* supplied, it passes as many
arguments as that function declares and no more:

```slate
print(map([1, 2, 3], () -> 9))          // the element is there and this one ignores it
print(map([1, 2, 3], (v) -> v * 2))     // and this one reads it

forEach([1, 2], () -> print("tick"))

setTimeout(() -> print("later"), 0)
```

```output
[9, 9, 9]
[2, 4, 6]
tick
tick
later
```

This is what a handler wants to look like — `on(node, "click", () -> setCount(n + 1))` for one that
does not read the event, `onData(socket, () -> stop())` for a reader that does not care what arrived
— and it is the rule everywhere a native calls back: array walks, `sorted`, timers, sockets,
WebSocket handlers, [the document](../library/dom.md)'s events.

**Declaring more than the caller has is still a fault, and it names the caller**, because your
function is not the thing that is wrong:

```slate
map([1], (a, b) -> a)
```

```error
`map` takes (integer) -> any here, and this is (integer, any) -> integer
```

That is the checker, which knows what `map` hands over. Reached through a value it cannot see, the
machine says the same thing in its own words — *"`map` calls this with 1 argument and it takes 2
arguments"*.

TypeScript draws the line in the same place, and for the same reason: a function of fewer parameters
is usable wherever more are supplied, while a direct call with the wrong count is an error.

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
