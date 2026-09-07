---
title: "slate:dom"
weight: 210
---

# The document is a package

**`slate:dom` is not a built-in module any more.** The document is written in slate now, over
[`external`](../reference/external.md), and it is installed the way anything else a program depends
on is installed:

```
$ slate install github.com/slate-language/dom
```

```slate
import { byId, setText, on } from dom
```

The names are the ones the built-in module had — `createElement`, `setChildren`, `byId`, `query`,
the read side hydration needs, the page's `location`, `history`, `localStorage` and cookie doors —
and a program that was written against `slate:dom` runs unchanged once the import line drops the
`slate:` and the package is added. **The reference is the package's own README**:
<https://github.com/slate-language/dom>.

## Why it moved

**Because the language grew the declaration it needed.** The built-in module was thirteen
hand-written natives and then forty-four, every one of them a door in the compiler, at a time when
slate had no way to name a JavaScript value at all. [`external`](../reference/external.md) is that
way, and it made the whole surface something a *program* can write — so the document stopped being a
thing the compiler has to know about and became a package that can be released, versioned and
depended on like [lath](https://github.com/slate-language/lath) or anything else.

**What a compiler carries, it carries for everybody.** A name in the built-in scope is one no program
can have; forty-four of them for a surface only a browser can run was the largest such bill in the
language, paid by every program whether it had a page or not.

## The old import

Naming the module now says where it went:

```slate
import { byId } from slate:dom

print(1)
```

```error
`slate:dom` is no longer built in -- the document is the `dom` package: `slate install github.com/slate-language/dom`, then `import { byId } from dom`
```

## The framework

The package is the seam, not the framework. [lath](https://github.com/slate-language/lath) is
React's model *and* React's mechanism, written in slate over
[elements](../reference/elements.md), with the document as one of its two hosts — the other rendering
to markup beside [`slate:http`](http.md), so server-side rendering is a by-product rather than a
project.

```
$ slate install github.com/slate-language/lath
```
