# Types

slate is dynamically typed with a **gradual checker**: nothing has to be annotated, and what is
annotated is checked twice — once by a pass before the program runs, and once by the machine when the
value actually arrives.

## The rule the checker obeys

**The pass may only report what the machine would also refuse.** A program that runs is never refused
before it runs. Everything below follows from that one constraint: where the pass cannot be certain, it
says nothing rather than guessing, and the machine still checks.

What that costs against TypeScript is worth saying plainly: TS catches a mistake on a path you never
ran, and this only fires where the pass can prove the value is wrong or where that path executes.

## `type`

A type is a shape with a name:

```slate
type Point = { x: number, y: number }
type Circle = { centre: Point, radius: number }

describe(v) = v match
    Circle -> s"a circle of radius ${v.radius}"
    Point  -> s"the point ${v.x}, ${v.y}"
    _      -> "no idea"

print({ x: 3, y: 4 } is Point)
print(describe({ centre: { x: 0, y: 0 }, radius: 2 }))
print(describe({ x: 3, y: 4 }))
print(describe("nothing"))
```

```output
true
a circle of radius 2
the point 3, 4
no idea
```

**It is TypeScript's `type`** — the same declaration, the same structural reading, asking for *at
least* those fields. What differs is that slate's is not erased: one declaration serves both the
pattern and the check at a boundary, where a TypeScript app that reads an API response writes the shape
twice, once as a `type` and once as a schema for the run.

**Nothing of a type's structure exists at run time.** A name in pattern position is replaced by the
pattern the type declared, while the program is compiled, so `p is Point` costs no instruction.

**A type may not bind a name.** `type Tagged = { x: n }` is refused: a name written inside a type would
be introduced wherever the type is used. It is the rule an alternative of a `|` already followed.

`export type` is how an interface leaves the file it was written in, and both halves cross — the shape
the compiler resolves and the value the name binds.

## The type expressions

| written | means |
|---|---|
| `any` | anything, and what an unannotated thing is |
| `number` `integer` `real` `string` `boolean` `array` `object` `function` `null` | a kind |
| `{ a: T, b?: U }` | an object with at least those fields |
| `[T, U]` | an array whose first elements fit |
| `array of T` | an array every element of which fits `T` |
| `object of T` | an object every value of which fits `T` |
| `T \| U` | either |
| `T & U` | both |
| `(T)` | the same `T`, bracketed to group it |
| `A -> B` | a function of one parameter |
| `(A, B) -> C`, `() -> C` | a function of none or several |
| a `type`, `class` or `data` name | what that declared |
| `Name[A, B]` | a generic type, given what it is generic over |

### `array of T`

An array pattern tests the elements it writes and lets the rest through — `["a", 2] is [string, ...]`
is **true** — so a list of unknown length needs this:

```slate
type Tags   = array of string
type Counts = object of integer
type Grid   = array of array of integer

print(["a", "b"] is Tags, [1] is Tags, [] is Tags)
print({ a: 1 } is Counts, { a: "x" } is Counts)
print([[1, 2], [3]] is Grid)
```

```output
true false true
true false
true
```

**An empty container fits**, every element of nothing fitting anything. A floor is said with an
intersection: `[any, ...] & array of string`. The element pattern may not bind, running once per
element.

**A `for` over one types its variable**, so `for u in users` where `users: array of User` makes `u` a
`User`.

### `?` and `|`

**A field the value need not have is marked `?`.** Present it must fit; absent the shape still holds —
which a nullable union cannot say, `tag: string | null` still requiring the key to be there.

```slate
type Note = { title: string, pinned?: boolean }

print({ title: "a" } is Note)               // absent, and the shape still holds
print({ title: "a", pinned: true } is Note)
print({ title: "a", pinned: 1 } is Note)    // present, and does not fit
```

```output
true
true
false
```

**`=` is for a pattern that binds and `?` is for one that tests**, and each is refused where the other
belongs.

A union may have `null` as an alternative, which is how a parameter says it will take nothing:

```slate
type Point = { x: number, y: number }
type MaybePoint = Point | null
type Shape = { side: number } | { radius: number }

print(null is MaybePoint, { x: 1, y: 2 } is MaybePoint, 3 is MaybePoint)
print({ side: 1 } is Shape, { radius: 1 } is Shape, { area: 1 } is Shape)
```

```output
true true false
true true false
```

### `&`

`&` is `|`'s dual and binds tighter, matching only where every part does. A value picks up fields on
its way down through a stack of functions, and this is how the one at the bottom says what it receives:

```slate
type Authed = { user: { id: integer } }
type Bodied = { body: string }

handle(req: Authed & Bodied) = req.user.id

print(handle({ user: { id: 7 }, body: "hi" }))
```

```output
7
```

**A part may bind, where an alternative may not**: every part runs, so `{ a } & { b }` binding both is
sound.

### A function type

**`integer -> integer` is the type of `n -> n + 1`, and it is spelled the way the lambda is.** One
parameter needs no brackets; none or several are a bracketed list:

```slate
apply(f: integer -> integer) -> integer = f(1)
twice(f: (integer, integer) -> integer) = f(2, 3)
later(f: () -> string) = f()

print(apply(n -> n + 1), twice((a, b) -> a * b), later(() -> "hi"))
```

```output
2 6 hi
```

**The arrow is the loosest thing in a type and groups to the right.** `string | null -> integer` is a
function taking either — which is what a parameter usually means — and a union *holding* a function
says so with brackets:

```slate
type Handler = string | null -> integer
type MaybeFn = (integer -> integer) | null

run(f: MaybeFn) = if f is null then 0 else f(2)

print(run(null), run(n -> n * 10))
```

```output
0 20
```

**Writing one down is what types the lambda handed to it**, which is where most of what it buys shows
up: the parameters flow inwards and what the body does with them is checked.

```slate
apply(f: integer -> integer) = f(1)

print(apply(n -> n + "x"))
```

```error
`+` does not apply to an integer and a string
```

**What is checked is the arity and the parameters, and deliberately not the result.** A function's own
`-> string` is checked against what that function answers and never against what somebody who was
handed it expected, so a mismatch there is a complaint no run could make. Where the result matters —
`f(cb) = cb(1) + 1` — it is read off the annotation and the arithmetic is checked on its own.

**At run time a function type asks what it can ask: is this callable, and would it take a call of this
size.** What a function will *do* with what it is given is not a question about the value in front of
you, which is why the parameters are the checker's business and the count is both.

## Annotating

Per parameter, and per result:

```slate
double(x: number) -> number = x * 2

print(double(21))
```

```output
42
```

A result that does not fit what was promised is a fault where the answer was written:

```slate
name(p: { id: number }) -> string = p.id

print(name({ id: 7 }))
```

```error
this answers string, and gave back 7
```

A parameter's complaint lands where the value was handed over:

```slate
type Point = { x: number, y: number }

d(b: Point) = b.x

print(d({ x: 0 }))
```

```error
`d` takes { x: number, y: number } here, and this is { x: integer }
```

**A lambda's parameters may be annotated and its result may not.** The arrow already separates the
parameters from the body, so there is nowhere for a result to be written; it is read off the body.

```slate
val g = (n: integer) -> n + 1

print(g(2))
```

```output
3
```

### A binding

**`val x: T = e` and `var n: T = e`**, checked where the value arrives and again by the pass that runs
before the program does:

```slate
val name: string = "ada"
val tags: array of string = ["reading", "writing"]
var count: integer = 0

count += 1

print(name, tags, count)
```

```output
ada ["reading", "writing"] 1
```

**An annotated `var` is TypeScript's `let`: the declared type is what the name holds for its whole
life**, so every assignment is checked against it rather than against what happens to be there.

```slate
var n: integer = 0

n = "later"
```

```error
`n` was declared integer, and this is string
```

An **unannotated** `var` is left as it always was — the union of its initialiser and every value ever
assigned to it — so a program that deliberately reuses a name for another kind is untouched.

### A rest parameter

**`...rest: array of T` describes the array**, because the array is what the name holds: a call gathers
what is left over into one, and it is checked once, where the gathering happened.

```slate
total(...ns: array of number) = reduce(ns, (a, b) -> a + b, 0)

print(total(1, 2, 3))
```

```output
6
```

## What the checker knows before the program runs

### A call answers in terms of what it was given

`filter`, `sorted`, `reversed`, `slice` and `pop` all give back what they were handed, so the element
type survives them and a mistake is caught where it is written — in either spelling, a method being
checked as the free function it is:

```slate
f(xs: array of string) = len(xs)

h(ns: array of integer) = f(ns.filter(n -> n > 1))
```

```error
`f` takes array of string here, and this is array of integer
```

`f(filter(ns, n -> n > 1))` draws the same complaint, a method being checked as the free function it
is.

`map(ns, n -> string(n))` is an `array of string`, the lambda's result being read off its body.

### A callback knows what it is handed

`map`, `filter`, `forEach` and the rest call their function with one element; `sorted` calls its
comparator with two; `reduce` calls its function with a running value and an element. **The checker says
so**, so a lambda written at the call gets its parameters typed from the array beside it — and what it
*does* with them is checked:

```slate
h(ns: array of integer) = map(ns, n -> n * 2)   // an array of integer, not of any

print(h([1, 2, 3]))
```

```output
[2, 4, 6]
```

What the callback *does* with what it was handed is checked:

```slate
g(ss: array of string) = map(ss, s -> s * 2)
```

```error
`*` does not apply to string and integer
```

and so is its arity:

```slate
q(ns: array of integer) = sorted(ns, a -> a)
```

```error
`sorted` takes (integer, integer) -> any here, and this is (integer) -> integer
```

**None of that is a type variable.** A builtin's signature names an argument by *position*, and the
type at that position is filled in at the call — no binding, no scope, nothing to write anywhere. What
a program writes for itself is the next section.

## Type parameters

**`first[T](xs: array of T) -> T` is how a function you write says the same thing a builtin says**: the
answer is whatever the call was given.

```slate
first[T](xs: array of T) -> T = xs[0]

print(first(["ada", "grace"]), first([1, 2]))
```

```output
ada 1
```

The parameters are solved from the arguments left to right, so a callback written at the call is typed
from the arguments before it — and what it does with them is checked:

```slate
map2[A, B](xs: array of A, f: A -> B) -> array of B = map(xs, f)

print(map2(["a", "b"], s -> upper(s)))
```

```output
["A", "B"]
```

**They are declared in one place and nowhere else** — `[T]` after the name of a definition or a type —
and there are no bounds, no variance and no defaults. A generic type is used by giving it what it is
generic over, and the shape that comes out is the shape both declarations describe:

```slate
type Pair[A, B] = { first: A, second: B }

show(p: Pair[string, integer]) = s"${p.first} is ${p.second}"

print(show({ first: "ada", second: 36 }))
print({ first: "ada", second: "x" } is Pair[string, integer])
```

```output
ada is 36
false
```

**A generic type used without its arguments is refused rather than quietly erased**, because a check
that passes for the wrong reason is worse than no check:

```slate
type Pair[A, B] = { first: A, second: B }

show(p: Pair) = p.first
```

```error
`Pair` is generic over 2 types, so it needs them here
```

### Every argument must fit the type the parameter was solved to

**A type parameter is solved from the arguments, and every one of them has to be contained in the
answer.** The candidates are gathered across the whole call and the one that every other candidate
fits is chosen; where there is no such candidate the call is refused, naming the parameter, what it
was taken to be, and the argument that disagrees:

```slate
pair[T](a: T, b: T) -> array of T = [a, b]

print(pair(1, "x"))
```

```error
`T` is integer from an argument before this one, and this is string
```

**A union is still an answer where the PROGRAM declared one**, because then it is a candidate like any
other and the value beside it fits:

```slate
pair[T](a: T, b: T) -> array of T = [a, b]

val mixed: integer | string = 1

print(pair(mixed, "x"))
```

```output
[1, "x"]
```

**`fits` is the same relation used everywhere else on this page, so an integer does not fit a `real`.**
`pair(1, 2.5)` is refused for that reason, and `number` is the type that takes both — which is what to
annotate with where a call means to mix them:

```slate
pair[T](a: T, b: T) -> array of T = [a, b]

print(pair(1, 2.5))
```

```error
`T` is integer from an argument before this one, and this is real
```

### What a type parameter still does not do

**It is erased, so nothing at run time knows it was there.** The machine sees values, not the calls
that were made — which is exactly why the check above happens while compiling or not at all.

**So `x is T` cannot be asked**, and it is refused where it is written rather than answering
something. **There are no type arguments at a call either** — `first[string](xs)` is an index followed
by a call, and no grammar can have both — so they are solved from the arguments or not given.

**Inside the definition a `T` is a value nothing is known about**, which is what makes `upper(xs[0])`
in a generic function perfectly legal: `T` may be a string, and refusing a program that runs is the one
thing the checker may not do.

### It reads the rest of the block before it says what a name holds

- **A `var` is the union of its initialiser and every value ever assigned to it**, so a counter stays an
  integer through `+= 1` and `n++` and a wrong call is refused before the program runs. A `var` the
  program reassigns to another kind is said nothing about. **An ANNOTATED `var` is what it was declared
  and every assignment is checked against that**, which is the one place the pass refuses something the
  machine would have run: the annotation is a promise the program made, and being held to it is what
  writing one is for.
- **An array literal says what it was built out of**, so `map([1, 2], n -> n * 2)` types its callback
  and `first([1, 2])` answers an integer. Elements that disagree make a union and one that is not known
  gives the whole thing up. **A NAME does not keep it**: an array is mutable and outlives the line that
  built it, so the element type is dropped where a literal is bound to a name — the rule an object's
  shape already follows. An annotation is not dropped, being a promise the machine checks.
- **A local object's fields are known** for as long as nothing can have made them stale: its name never
  mentioned except to read a field off it, so nothing else holds the object and no field of it is ever
  written. `o with { … }` is a mention.
- **An annotated parameter's shape is not carried past the call.** The object came from somewhere else,
  the caller may hold another name for it, and the annotation is checked on the way in and says nothing
  about after.

### Where it steps aside

- **A call that spreads** — `f(...xs)` — is not checked for arity, the count being a run-time fact.
- **A receiver whose type is `any`** is never asked what methods it has.
- **An object's field names** are the program's, so an object is never asked whether it has one.
- **A method name is refused before it runs where the receiver's kind is certain** — `"abc".push(1)`,
  `date(…).hour()` — because that asks the machine's own question: the dispatch table is one table.

## A type is a value under its own name

Which is what makes the declaration the validator — nothing written twice, and no schema library to
keep in step with it:

```slate
type Note = { title: string, pinned?: boolean }

print(Note.test({ title: "a" }))
print(Note.mismatch({ }))
print(Note.name())
```

```output
true
[{path: "title", wanted: "string", got: "nothing"}]
Note
```

`mismatch` collects **every** reason rather than stopping at the first, because a person filling in a
form wants to be told about all of it at once, and `path` says where in the value each one is.

**Those three are the whole surface: a shape's fields cannot be read back out**, so nothing can grow to
depend on the structure of a type. `is` is deliberately not extended to take one — a bare name in
pattern position binds, so `v is s` would match everything — and `shape` is a type word, so `s is shape`
asks whether `s` is one of these.

**This covers all three declarations that name a type**, so a [class](classes.md) name and a
[data](data-types.md) name answer the same three about themselves — the shape being the very pattern
`is` tests, interned where the declaration stands:

```slate
class Point
    var x
    var y

data Failure
    NotFound(what)
    Empty

print(Point.name(), Point.test(Point(1, 2)), Point.test({ x: 1, y: 2 }))
print(Failure.test(Empty), Failure.mismatch(3))
print(NotFound.test(NotFound("a")), NotFound.test(Empty))
```

```output
Point true false
true [{path: "", wanted: "Failure", got: "integer"}]
true false
```

A class and a variant ask a **nominal** question — was this value made from that declaration — so
`test` is `is` and a `mismatch` against one names the type and stops. There is nothing more useful to
say about a value that was made from something else.

**A static the class itself declares wins over all three**, the shape answering only where the
object's own fields and its whole proto chain have said nothing. So `test` and `name` are still words
a class may use for its own purposes.

`shape` as a type word takes all three, so `f(s: shape)` is how a function says it wants one — and
`Point is shape` is true where `Point(1, 2) is shape` is not, a value being what the type describes
rather than the type.

## Interfaces

An interface, in the sense of a set of operations, needs nothing further — functions are values, so
`type Drawable = { draw: function }` is one. A [class](classes.md) promises one with `is` in its header,
which is TypeScript's `implements` and is checked where the class is written.
