# `slate:dom`

The document. **The one module that works in one host out of three** — it is real only in a browser,
reached through [`slate js`](../reference/javascript.md).

```
import { byId, setText, on } from slate:dom
```

| | |
|---|---|
| `createElement(tag)`, `createText(s)` | |
| `setAttribute`, `removeAttribute`, `setProperty` | |
| `on(node, event, fn)`, `off(node, id)` | |
| `setChildren(node, kids)`, `setText(node, s)` | |
| `byId(id)`, `query(selector)` | |
| `markup(node)` | |
| `release(node)` | give a handle back |

**`on` and `off` rather than `addEventListener`**, and `byId` rather than `getElementById`. The DOM's names
are long because JavaScript had no modules when they were chosen; these are reached through an import that
already says `dom`.

## A node is a slate integer

**That is the decision everything else follows from.** The engine keeps the elements in a table and hands
out the index, so **no foreign object ever becomes a slate value**: `==` compares what slate says it
compares, `print` has something to say, a node travels through an array or a pattern like any other value,
and the checker learns nothing new. It is the arrangement the timers already use.

The cost is that **a handle is held until `release` gives it back**.

## An event arrives as a slate object

`{ type, value, checked, key, stop, prevent }`, built when the handler fires. A `MouseEvent` has no
representation in slate, and inventing one would mean inventing a value that could not be printed, compared
or stored.

**`value` and `checked` are set as properties and not attributes**, and an input is where the difference
shows: the attribute says what the field started as and the property says what it holds now, so a re-render
that set the attribute would leave a typed-in field alone and the page would appear frozen.

## Under the interpreter

**Every name faults, and the module still exists.** Leaving it out would make `import { byId } from
slate:dom` a complaint about the *module*, which sends a reader looking for a spelling mistake in the one
line that is right. The refusal instead names the **command**, because the command is the mistake — the
same program is correct in a browser.

## The framework

`slate:dom` is the seam, not the framework. `lath` is React's model *and* React's mechanism, written in
slate over [elements](../reference/elements.md), with this module as one of its two hosts — the other
rendering to markup beside [`slate:http`](http.md), so server-side rendering is a by-product rather than a
project.

```
$ slate add github.com/slate-language/lath
```

**It is a package rather than part of the language, and deliberately so**: a UI framework iterates far
faster than a compiler, and baking one in would tie every framework fix to a language release.
