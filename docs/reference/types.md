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

```
type Point = { x: number, y: number }
type Circle = { centre: Point, radius: number }

{ x: 3, y: 4 } is Point                 // true

describe(v) = v match
    Circle -> s"a circle of radius ${v.radius}"
    Point  -> s"the point ${v.x}, ${v.y}"
    _      -> "no idea"

distance(a: Point, b: Point) = ...
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
| a `type`, `class` or `data` name | what that declared |

### `array of T`

An array pattern tests the elements it writes and lets the rest through — `["a", 2] is [string, ...]`
is **true** — so a list of unknown length needs this:

```
type Tags   = array of string
type Counts = object of integer
type Grid   = array of array of integer
```

**An empty container fits**, every element of nothing fitting anything. A floor is said with an
intersection: `[any, ...] & array of string`. The element pattern may not bind, running once per
element.

**A `for` over one types its variable**, so `for u in users` where `users: array of User` makes `u` a
`User`.

### `?` and `|`

**A field the value need not have is marked `?`.** Present it must fit; absent the shape still holds —
which a nullable union cannot say, `tag: string | null` still requiring the key to be there.

```
type Note = { title: string, pinned?: boolean }
```

**`=` is for a pattern that binds and `?` is for one that tests**, and each is refused where the other
belongs.

A union may have `null` as an alternative, which is how a parameter says it will take nothing:

```
type MaybePoint = Point | null
type Shape = { side: number } | { radius: number }
```

### `&`

`&` is `|`'s dual and binds tighter, matching only where every part does. A value picks up fields on
its way down through a stack of functions, and this is how the one at the bottom says what it receives:

```
type Authed = { user: { id: integer } }
type Bodied = { body: string }

serve(req: Authed & Bodied) = req.user.id
```

**A part may bind, where an alternative may not**: every part runs, so `{ a } & { b }` binding both is
sound.

## Annotating

Per parameter, and per result:

```
double(x: number) -> number = x * 2

name(p: { id: number }) -> string = p.id     // error: this answers string, and gave back 7
```

A parameter's complaint lands where the value was handed over:

```
error: `d` takes { x: number, y: number } here, and this is { x: integer }
 --> app.sl:3:9
  |
3 | print(d({ x: 0 }))
  |         ^^^^^^^^
```

**A lambda's parameter cannot be annotated**, and a lambda's result is read off its body — a lambda is
the one function with no way to say what it answers.

## What the checker knows before the program runs

### A call answers in terms of what it was given

`filter`, `sorted`, `reversed`, `slice` and `pop` all give back what they were handed, so the element
type survives them and a mistake is caught where it is written — in either spelling, a method being
checked as the free function it is:

```
f(xs: array of string) = len(xs)

f(filter(ns, n -> n > 1))       // error, where `ns` is an array of integer
f(ns.filter(n -> n > 1))        // the same error
```

`map(ns, n -> string(n))` is an `array of string`, the lambda's result being read off its body.

### A callback knows what it is handed

`map`, `filter`, `forEach` and the rest call their function with one element; `sorted` calls its
comparator with two; `reduce` calls its function with a running value and an element. **The checker says
so**, so a lambda written at the call gets its parameters typed from the array beside it — and what it
*does* with them is checked:

```
g(ss: array of string) = map(ss, s -> s * 2)    // error: `*` does not apply to string and integer
h(ns: array of integer) = map(ns, n -> n * 2)   // an array of integer, not of any
sorted(ns, a -> a)                              // error: `sorted` takes (integer, integer) -> any
```

**None of that is generics and slate has no type variables.** A signature names an argument by
*position*, and the type at that position is filled in at the call. What it costs a reader is nothing —
there is no `<T>` to write anywhere.

### It reads the rest of the block before it says what a name holds

- **A `var` is the union of its initialiser and every value ever assigned to it**, so a counter stays an
  integer through `+= 1` and `n++` and a wrong call is refused before the program runs. A `var` the
  program reassigns to another kind is said nothing about.
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

```
Note.test(v)                // true where it fits
Note.mismatch(v)            // [{ path: "title", wanted: "string", got: "nothing" }, ...]
Note.name()                 // "Note"
```

`mismatch` collects **every** reason rather than stopping at the first, because a person filling in a
form wants to be told about all of it at once, and `path` says where in the value each one is.

**Those three are the whole surface: a shape's fields cannot be read back out**, so nothing can grow to
depend on the structure of a type. `is` is deliberately not extended to take one — a bare name in
pattern position binds, so `v is s` would match everything — and `shape` is a type word, so `s is shape`
asks whether `s` is one of these.

## Interfaces

An interface, in the sense of a set of operations, needs nothing further — functions are values, so
`type Drawable = { draw: function }` is one. A [class](classes.md) promises one with `is` in its header,
which is TypeScript's `implements` and is checked where the class is written.
