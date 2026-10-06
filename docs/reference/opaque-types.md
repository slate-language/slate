---
title: Opaque types
weight: 75
---

# Opaque types

A glyph id and a node id are both integers, and a width in points and a width in ems are both reals.
In a large program they still must not mix. An **opaque type** gives a representation a name of its
own:

```slate
opaque type GlyphId = integer
```

**Inside the file that declares it, a `GlyphId` IS an integer.** You write no casts. A
representation goes where the type is declared, and the representation's operators work on a value
of the type:

```slate
opaque type GlyphId = integer

glyph(n: integer) -> GlyphId = n
next(g: GlyphId) -> GlyphId = g + 1
twice(g: GlyphId) -> GlyphId = next(next(g))
index(g: GlyphId) -> integer = g

print(index(twice(glyph(40))), index(next(1)))
```

```output
42 2
```

**Everywhere else it is a type of its own.** Another file sees only what the declaring file
exports. A bare integer does not fit a `GlyphId`, a `GlyphId` does not fit an `integer`, and none of
an integer's operators or methods apply to one. Its only methods are the four every value has
(`toString`, `eq`, `ne`, `equals`):

```slate
// glyphs.sl
export opaque type GlyphId = integer

export glyph(n: integer) -> GlyphId = n
export next(g: GlyphId) -> GlyphId = g + 1
```

```slate
// main.sl
import { glyph, next } from "./glyphs.sl"

next(glyph(41))       // fine
next(41)              // `next` takes GlyphId here, and this is integer
glyph(1) + 1          // `+` does not apply to GlyphId and integer
val n: integer = glyph(1)   // `n` was declared integer, and this is GlyphId
```

The checker refuses each of the last three before the program runs. **The machine refuses them
too.** Suppose a value reaches the same place by a route the checker cannot follow, such as a
function nobody annotated. Then the run stops there with the same mistake:
`` `g` was declared GlyphId, and was given 41 ``.

## The machine carries it

slate's checker may only report what the machine would also refuse (see [Types](types.md)). That
rule is why an opaque type is not an alias that vanishes at run time. **A value of one carries its
type.** It is the representation, boxed with the declaration that made it. So `is` answers
honestly, on both back ends:

```slate
opaque type GlyphId = integer

glyph(n: integer) -> GlyphId = n

print(glyph(1) is GlyphId, glyph(1) is integer, 1 is GlyphId)
print(GlyphId.test(glyph(1)), GlyphId.name())
```

```output
true false false
true GlyphId
```

The box costs one small allocation when a value is made. A file that declares no opaque type
compiles exactly as it did before.

**The declaring file sees through the box because the compiler writes the conversions into that
file's code.** The machine never asks who is calling. A conversion is written at three kinds of
place in the declaring file:

- **A representation is handed to the type.** This happens at an argument, a binding declared with
  the type, a compound assignment to one, and every way a function declared `-> GlyphId` answers,
  including a `return` deep inside a block. At each of these the value is boxed.
- **A value of the type is handed to something its representation fits.** For example, a function
  declared `-> integer` may answer a `GlyphId`. There the box is opened.
- **An operand.** The operands of an operator, a method call, a field or element read, and a `for`
  are given the representation of any type the file declared. This covers a helper nobody annotated
  too, so `helper(x) = x * 2` still doubles a `GlyphId`.

A box is opened only where something reads the value, never at a parameter. Suppose a parameter
accepted a bare integer because the call came from inside the file. Then it would have to know who
called it. No such parameter exists, so the outside can never get a representation past one.

**A conversion is written only where the checker can see one is owed.** A value the checker knows
nothing about is handed over as it is, and the machine refuses it with the usual sentence if it does
not fit. That is the same gradual bargain as everywhere else in slate.

## A bound: how far the outside may use it

`is` in the header names what the rest of the program may use the type **as**. The word means what
it means in `class Pen is Drawable`:

```slate
opaque type Points is real = real

pt(x: real) -> Points = x

val width = pt(12.5)
val r: real = width

print(width + 1.0, sqrt(pt(16.0)), r)
```

```output
13.5 4 12.5
```

A `Points` may go wherever a `real` is wanted, and `+`, `sqrt` and a binding declared `real` all
take one. It is still a `Points`: **a bare real does not fit a `Points` anywhere but in its own
file.** That is the one-way door Scala writes `opaque type Points <: Double = Double`.

The bound may be wider than the representation, so `is number = real` is legal. It may not be
something the representation is not:

```slate
opaque type Points is string = real
```

```error
`Points` is made of real, which is not string
```

## What it prints and encodes as

**`print`, `string`, a `${}` hole and `toJSON` write what the value is made of.** The type is a
promise about where the value may go, not part of the data. So `s"${width}pt"` is `12.5pt`, and a
JSON document holds the bare representation. **A diagnostic names the type**, because a message
saying "was given 5" about a `GlyphId` would send you looking for a stray integer:
`` `n` was declared integer, and was given GlyphId(3) ``.

**Two values are equal when they have the same type and equal representations.** A value is never
equal to its bare representation, because they are different kinds. Values hash the same way, so
a `Set` or a `Map` keyed by `GlyphId`s works. A value is always true in a condition, whatever it is
made of. A value crosses to an [actor](../library/actor.md) as its own type.

JSON read back from a document is text from outside the program, so it arrives as the bare
representation. It becomes the type again only where the declaring file says so. That is exactly
the rule the type exists to keep.

## What is not converted

- **A container is not opened up.** An `array of GlyphId` holds values of the type, even in the
  declaring file. `[1, 2]` where an `array of GlyphId` is declared is refused, both by the checker
  and by the machine, which checks the elements. Build one with the file's own maker:
  `[glyph(1), glyph(2)]`.
- **A test asks about the value itself.** `g is integer` is false even in the declaring file.
- **`x++` on a name holding one** is left to the machine, which refuses it as it would refuse `+`
  outside. Write `x += 1`, which is converted.
- **An opaque type takes no type parameters.** A representation over a parameter would have to be
  checked against an argument nobody wrote down when a value is made.

A function imported from another file is normally `any` to the checker. The exception is a function
whose signature names an opaque type: the checker carries that signature across the import, so the
boundary is checked where it matters. Imports that do not involve an opaque type are checked
exactly as before.
