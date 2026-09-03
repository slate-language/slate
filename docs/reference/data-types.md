# Data types

`data` declares a closed set of variants — an algebraic data type — and that closed set is what makes a
`match` over one worth checking.

```
data Shape
    Circle(r)
    Rect(w, h)
    Empty

    area(self) = self match
        Circle(r) -> 3 * r * r
        Rect(w, h) -> w * h
        Empty -> 0

print(Circle(3), Circle(3).area())      // Circle(3) 27
```

**A variant is a [class](classes.md) from the data type**, which is the whole of the implementation:
`is Shape`, an annotation, `export`, a cross-file import and a method on the shared body are all
machinery `class` already had. `Circle(3)` is the generated constructor, reached by the rule that
calling an object calls its `new`.

**A variant that declares no fields is a value rather than a maker.** `Empty` is the value, not
`Empty()`, and the test for it is identity.

## A data value does not change

A write to one of its fields is refused, and `v with { r: 4 }` answers a new one that differs there. Two
equal ones are equal and hash alike, so **a data value is an ordinary table key**.

## Exhaustive `match`

**A `match` over an annotated subject must cover every variant**, and the complaint names each one left
out:

```
sides(s: Shape) = s match
    Circle(_) -> 0
    Rect(_, _) -> 4
    Empty -> 0
```

It is checked exactly where the shape was written down — an unannotated subject is said nothing about —
and a `_` arm is how a program says it has finished listing.

## Patterns

Variants take the same two forms a class does — `Circle(r)` by position, `Circle { r }` by name — and a
field name the variant does not carry is refused where it is written. See [Patterns](patterns.md).

## Encoding

Without a `toJSON`, a variant encodes as its own fields: `Circle(3)` is `{"r":3}`, never the chain it
hangs from. A `toJSON(self)` on the shared body says otherwise — see [Objects](objects.md).
