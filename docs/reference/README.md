# Language reference

Every construct in slate, written down once, in its own place.

## The pages

| | |
|---|---|
| [Lexical structure](lexical.md) | files, comments, indentation, names, literals, interpolation |
| [Values](values.md) | the nine kinds, truth, equality, conversion |
| [Expressions](expressions.md) | operators, the precedence table, ranges, `with`, `??`, `?.`, spread |
| [Statements](statements.md) | `val` and `var`, assignment, `if`, every loop, blocks |
| [Patterns](patterns.md) | `match`, `is`, what binds, what tests, exhaustiveness |
| [Functions](functions.md) | definitions, lambdas, defaults, named arguments, `...rest` |
| [Types](types.md) | `type`, annotations, what the checker will and will not say |
| [Objects](objects.md) | fields, `proto`, the receiver rule, operator hooks |
| [Classes](classes.md) | `class`, `from`, `is`, `new`, class patterns |
| [Data types](data-types.md) | `data`, variants, immutability, exhaustive `match` |
| [Modules](modules.md) | `export`, `import`, the three kinds of specifier |
| [Asynchrony](asynchrony.md) | `async`, `await`, promises, the two queues, generators |
| [Faults](faults.md) | `throw`, `try`/`catch`, and results as the other channel |
| [Elements](elements.md) | slx — `<div>` in the source, and what it desugars to |
| [Tests](tests.md) | `@test`, `slate test`, the assertions |
| [Packages](packages.md) | the manifest, `slate add`, the cache, `slate.sum` |
| [JavaScript](javascript.md) | `slate js`, and where the two back ends differ |

## How to read a rule here

**A rule about what slate refuses is a rule about what it refuses to COMPILE unless the page says
otherwise.** slate has two moments at which a program can be told it is wrong, and they are not
interchangeable: the compile, which happens before anything runs and may only refuse a program that
would genuinely fail; and the run, which is where a dynamically typed language does most of its
checking. A page says which.

**Two failure channels run through the whole language, and knowing which is which explains most of
the library.** A condition the caller was always going to deal with — a file that is not there, a
connection refused, text that will not parse — is an **answer**: a result object the caller has to
look at. A defect in the program — the wrong kind of argument, a division by zero, a value with no
JSON form — is a **fault**, which unwinds until something catches it. Neither is used for the other's
job anywhere in slate.

**slate refuses to store absence.** There is no `undefined`; `null` is a value like any other and is
the only one. Nothing in the language can put "no value at all" into an array, an object field, a
parameter or a variable — which is why `pop` on an empty array faults rather than answering nothing,
why a parameter nobody gave is not bound rather than bound to a sentinel, and why an optional object
field is a shape question rather than a value.
