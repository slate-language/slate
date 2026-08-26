# slate

A small indentation-structured language, written in [sysl](https://sysl.sh) to find out what sysl is
like to write a real front end in.

**The language is a means rather than an end.** What is being tested is sysl. A tree-walking
interpreter is one of the few programs that reaches for nearly everything a language has — recursive
data through references, payload-carrying enums, traits with associated types, generics over a
container, closures that outlive the frame that made them, and an error path that has to carry a
position from the byte that caused it all the way to the sentence a person reads. Where sysl makes
one of those awkward, that is the finding, and the finding is the point.

```
slate/
    tok.sysl        what the lexer answers with
    lex.sysl        bytes to tokens, with indentation as structure
    ast.sysl        the tree
    parse.sysl      statements, by recursive descent
    expr.sysl       expressions, by binding power
    value.sysl      what a program computes with, and the scope chain
    eval.sysl       the walk
    builtin.sysl    the functions a program has without writing them
    show.sysl       the tree as `(+ 1 (* 2 3))`, for the tests
    tests.sysl      what all of it claims, run by `sysl test .`
main.sysl           the driver: a path in, a report out
examples/tour.slate the language in one file
```

## Running it

```
sysl test .
sysl run . -- examples/tour.slate
```

## The language

The syntax follows sysl's, which is itself Scala with some Python and Kotlin. `val` and `var`; no
keyword on a function, the shape being what identifies it; a block whose value is its trailing
expression, so `return` is for leaving early and nothing else; `if`/`elif`/`else` with an inline
`then` form; and `end` left as a soft word so a program may still use the name.

```
val name = "slate"
var n = 0

double(x) = x * 2

add(a, b)
    a + b

grade(mark)
    if mark >= 90
        "A"
    elif mark >= 80
        "B"
    else
        "C"

first_even(xs)
    for x in xs
        if x % 2 == 0
            return x
    nil

counter()
    var count = 0
    bump()
        count = count + 1
        count
    bump

val c = counter()

print(c(), c(), c())            // 1 2 3

print([x -> x * 2, 21])
print({ name: "ada", born: 1815 }.name)
```

It is dynamically typed. Values are `nil`, booleans, integers, reals, strings, arrays, objects and
functions. Arrays and objects are reference types and compare by their contents. Only `false` and
`nil` are false — zero and the empty string are not, which is the rule Ruby and Lua take and the one
JavaScript and Python are most often criticised for.

`&&` and `||` short-circuit and answer the operand that decided, which is the one place slate's rule
is not sysl's: sysl's operands are `bool` and there is nothing else for it to give back.

## What it leans on

`sh.sysl.parsing` does the scanner tier — spans, the byte cursor, literal reading, the diagnostic
renderer, the binding-power loop, and the layout pass. Slate is that package's first consumer of
**`layout`**: `json` has no line structure and `ogol` has no indentation, so the column stack had
been written and never run by anything.

Two of its own notes turn out to matter here and are worth repeating:

- **The `TokenStream` the Pratt loop runs on is the parser, not the token cursor.** A `led` callback
  is handed the `*S` it was called with, so making `S` the parser is what lets a callback complain
  about what it just read.
- **A parse error is a node, not a `Result`.** It keeps the tree shaped and lets one pass report
  every mistake in a file.

## What is not here yet

`match`, string interpolation, a module system, and anything resembling a standard library beyond
five builtins. The tour is the current surface, and it is meant to grow in whatever direction puts
the most pressure on sysl.

## Licence

ISC.
