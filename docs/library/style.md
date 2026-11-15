---
title: "slate:style"
weight: 105
---

# `slate:style`

The stylesheets a program brings in, as text.

```slate
import "./theme.css"
import { sheets } from slate:style

print(sheets().length)
print(sheets()[0].trim())
```

```output
1
body { margin: 0; }
```

| | |
|---|---|
| `sheets()` | the text of every stylesheet the program bare-imported, as an array of strings |

## A bare import is a stylesheet

**`import "./theme.css"` binds no name**, so the only thing it can be for is what the file does by being
part of the program — and a stylesheet is the one kind of file that does something by being there. It
is read while the program is compiled, as [any file that is not slate](../reference/modules.md) is, and
`sheets()` hands back what was read.

Anything else written bare is refused, in one sentence saying which form it wanted:

```slate
import "./header.html"
```

```error
a bare `import` is for a stylesheet
```

## A stylesheet's own `@import`

**A relative `@import` in a stylesheet is replaced by the file it names**, read beside the
stylesheet, while the program is compiled — because a sheet put into a page as text has no address
of its own, and a browser would fetch `./reset.css` from beside the *page*. A condition is kept as
the block that means the same thing:

```slate
import layout from "./layout.css"

print(layout.trim())
```

```output
* { box-sizing: border-box; }

@media print {
.layout { display: block; }
}
.layout { display: grid; }
```

- **Only `./` and `../` are inlined**, in any of `"…"`, `'…'`, `url(…)`. `https:`, `//` and a root
  path `/…` are left as written, as is anything inside a comment or a string.
- **A media list becomes `@media`, `supports(…)` becomes `@supports`, and `layer` or `layer(name)`
  becomes `@layer`.** A layer *and* a condition together is refused: as nested blocks the layer would
  exist even where the condition is false, which the `@import` does not say.
- **A file imported twice in one stylesheet's tree, under the same condition, is inlined once — where
  it is first met.** That is not quite a browser's rule: a browser fetches it once but applies it at
  *every* place it is imported, so a rule written between the two imports that the second copy would
  override again stays overriding here. Import a shared file once, at the top, and the two agree.
- **Refused, each at the `@import` in the CSS file that wrote it:** a file that is not there, a cycle
  (the chain named), a target that is not `.css`, an `@import` after a rule (a browser ignores it, so
  inlining it would apply rules that never applied), and an absolute `@import` in an inlined file that
  would land after rules or inside a block.

```slate
import broken from "./broken.css"
```

```error
cannot read `docs/library/nowhere.css`, which `docs/library/broken.css` imports
```

Every consumer gets the inlined text — a named import and `sheets()`, the interpreter and `slate js`,
and a [bundle](../reference/packages.md), which carries the inlined text and none of the files it was
made from.

## The set is known before the program runs

**slate has no dynamic modules**, so every file a program is made of — and every stylesheet among them
— is read before its first line runs. Nothing registers a sheet and nothing can forget to:

- **The order is the order the files were met.** A module's imports are followed before the line after
  them, so a sheet a module brings in comes where that module was first imported; within a file, it is
  the order they were written.
- **A sheet imported from several places is there once**, at the first place it was met.
- **Naming one is not bringing it in.** `import card from "./card.css"` is a string the program holds;
  only a bare import adds the sheet to `sheets()`. A file imported both ways is still read once.
- **A package's modules count**, a package being part of the program like any other file.
- **A program with none answers `[]`**:

```slate
import { sheets } from slate:style

print(sheets().length)
```

```output
0
```

```slate
import "./theme.css"
import "./card.css"
import card from "./card.css"
import { sheets } from slate:style

print(sheets().length)
print(sheets()[1] == card)
```

```output
2
true
```

**It is the same answer on every back end** — the interpreter, `slate js`, and a
[bundle](../reference/packages.md), whose stylesheets travel inside it with every other file it needs.
`sheets()` answers a fresh array each time, so a program that changes the one it was given changes its
own copy.
