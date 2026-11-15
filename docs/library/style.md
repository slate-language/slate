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
