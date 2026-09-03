# JavaScript

```
$ slate js hello.sl -o hello.js
```

`slate js` reads the same tree the interpreter walks and writes **one self-contained JavaScript file** —
the runtime, any framework, and the program. There is no bundler, no `node_modules`, and nothing to
install beside it. The output runs under node, under quickjs, and in a browser.

`slate test --js .` compiles a whole directory into one program and runs it under node, reporting in the
same words `slate test` does. **A test is written about the language rather than about an implementation
of it**, so the same file is the check that the two back ends have not drifted apart — which is worth more
than it sounds, since a test driving the interpreter says nothing whatever about `slate js`.

## The value model

**An integer is a `BigInt` and a real is a `number`, and every operator goes through the runtime.** This is
the decision everything else follows from, and it is not caution: slate's integer is 64 bits, wraps,
divides towards zero and shifts to 63 places, and a double does none of those — nor could it be told from
a real afterwards, so `2.5 is integer` would answer whatever the value happened to look like.

The operators follow because the two languages disagree too often for the exceptions to be worth tracking:

| | slate | JavaScript |
|---|---|---|
| `7 / 2` | `3` | `3.5` |
| `0` in a condition | true | false |
| `[1] == [1]` | true | false |
| `1 << 40` | 2^40 | 256 |

## What is not there yet

**`slate:net`, `slate:time`, `slate:regex`, `slate:crypto`, `slate:password`, `slate:brotli`,
`slate:llhttp`, `slate:process`'s `run`, `fetch`, and the modules written over them.** Each is a name that
says *"not in the JavaScript back end yet"* when a program reaches it, rather than a name that is not
there — so a program is told which half of the world it is in.

**`slate:dom` is the other way round**: it works only here. Under the interpreter every one of its names
faults with a sentence naming the *command* rather than the code, because the same program is correct in a
browser and it is the command that is wrong.

## Blocks and order

JavaScript has no block expression, so `val x = if c then 1 else 2` becomes an `if` statement over a
temporary. **An immediately-called function would have been the other way and is wrong**: `return`,
`break`, `await` and `yield` all mean the enclosing function, and a wrapper takes every one of them away.
The one place a wrapper is written is a default parameter, where there is no statement position to hoist
into and nothing of the enclosing function to lose.
