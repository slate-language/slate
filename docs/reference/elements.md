# Elements

`<div class="x">hi {name}</div>` parses. slate calls it **slx**, after tsx — the surface is JSX's, and
the mechanism it is meant to serve is React's.

**Elements are read in every file.** `.slx` is a name for a reader and an editor and says nothing to the
compiler: slate's [type parameters](types.md) are written `[T]` and never `<T>`, so a `<` where an
operand would begin can only be an element — which is the entire reason `.tsx` had to be a separate
parse mode from `.ts` and slx does not.

## What an element is

**An element adds nothing to the tree.** It is desugared in the parser:

```slate
<div class="x">hi</div>   →   createElement("div", { class: "x" }, ["hi"])
```

So **what an element means is a function a program can read** rather than a rule inside the compiler.
`createElement` and `Fragment` come from wherever the program gets them — `lath` is one such —
and a file that writes an element and imports neither is refused by the undefined-name check.

```slate
import { createElement, Fragment, mount, useState } from lath
import { domHost } from lath/dom

Counter({ start = 0 }) =
    val [count, setCount] = useState(start)

    <div class="counter">
        <p>{count}</p>
        <button onClick={() -> setCount(count + 1)}>+1</button>
    </div>

mount(<Counter/>, domHost("#app"))
```

## The rules

**`<` in prefix position begins nothing else**, which is the whole of the ambiguity: `<` is otherwise
always an infix operator, so where an operand is expected it can only be a tag. The byte after the `<` is
checked too, so `<<` and `<=` are never mistaken for a tag with a strange name.

**A lowercase tag is a host element and travels as the string `"div"`; a capitalised one is a name in
scope.** React's rule, kept because it is learned behaviour costing no syntax.

**`class`, not `className`; `for`, not `htmlFor`.** React's spellings exist only because JSX compiles into
a JavaScript object literal where those were reserved words. An attribute here is its own lexical context
and can take the right name.

**A bare attribute is `true`** — `<input disabled>`.

**An attribute's value is a quoted string or a `{ … }`, and a bare word is refused.** `class=wide` would
be a variable in every other position and a string to everyone who writes it.

**`{...props}` is the spread an object literal already takes**, folded into the same `with`, so an
attribute written after a spread wins over it.

**A hyphen is part of a name inside a tag and a subtraction outside one** — `data-id`, `aria-label`,
`<my-widget>`. A dot stays a token, so `<Menu.Item>` is an ordinary field selection.

**Whitespace inside a tag is skipped whole, newlines included**, since a tag with an attribute per line is
the ordinary way to write one.

**A mismatched closing tag names both names**, either one being possibly the mistake.

## The children

**The children travel as one array, not as trailing arguments.** React spells its own
`createElement(type, props, ...children)`; an array is the better answer anyway, being what
`props.children` holds in the end, so a component passing its children on writes them as the value they
already are.

**The whitespace rule is JSX's.** A run of text holding no line break is kept exactly as written — the
space in `<h1>Count: {n}</h1>` is one the reader meant. A run that spans lines is trimmed per line, blank
lines dropped, the rest joined with one space, because it is mostly the indentation that lined it up
under its tag. Any other rule makes an indented element read differently from the same element on one
line.

## Inside an element

Between a tag's `>` and the `<` that ends it, a space is a character, `//` is not a comment and a newline
is not a line ending.

**A `{` inside an element opens a hole**, and a `{` inside that hole is an ordinary brace — so the `}` of
an object literal written in a hole is not taken for the one closing the hole.

**An element opens a layout bracket at its `<` and closes it at its end**, which is what lets a tag be
written across lines with its children indented under it. It is the same mechanism `(` uses, so an `->`
written inside a hole still opens a block and a callback can be written where it is passed.
