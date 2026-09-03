# Classes

A class is an [object with a proto](objects.md) and a word in front of it. `class` binds a name to an
object literal and `from` is that object's `proto`, so what runs is what protos already did.

```slate
class Shape
    val sides = 0

    describe(self) = s"a ${self.name()} of area ${self.area()}"

class Square from Shape
    val sides = 4
    var side

    name(self) = "square"

    area(self) = self.side * self.side

print(Square.new(4).describe())
```

```output
a square of area 16
```

A class belongs to the **top level of a file**, as a `type` does and for the same reason: its name is
resolved while compiling. `class` is a soft word, so a program already using it as a variable name is
untouched.

## What the word buys

**A method is written in the ordinary definition syntax.** A field's value is an expression, so a method
in a literal is a lambda and its body is whatever fits after `->`. A definition's body may be an indented
run of statements, take annotated or destructured parameters, be `async`, or `yield`. A class of twenty
methods reads like twenty functions rather than like twenty fields.

**`is` asks which class a value was made from**, and walks the whole chain. This is the one thing `class`
adds that a hand-written proto could not have:

```slate
class Shape
class Square from Shape
    var side

val sq = Square.new(1)

print(sq is Square, sq is Shape)
print({ side: 1, proto: Square } is Square)
print({ side: 1 } is Square)
print(Square is Square)
```

```output
true true
true
false
false
```

A bare name in pattern position is a binding unless something has declared it, and a class declaration
is what declares it — so the name works everywhere a type does: in `is`, in a `match` arm, and in a
parameter's annotation. **A class crosses a file under `export` as both halves at once**, the value and
the type.

## `val` and `var`

**`val` is the class's and `var` is each object's**, and that distinction is the one that bites. A `val`
is one value however many objects there are; a `var` declares a field each object gets, and its
initialiser runs **once per object**:

```slate
class Bag
    var items = []          // a NEW array for every bag
    val kind = "bag"        // one string, shared

val a = Bag()
val b = Bag()

push(a.items, 1)

print(a.items, b.items, a.kind)
```

```output
[1] [] bag
```

A mutable literal under `val` is refused, and the message names `var` as the fix:

```slate
class Bag
    val items = []
```

```error
var
```

TypeScript spells the per-instance one `items = []`, so a reader coming from TS writes `val` and gets
one array every instance pushes into. **A mutable literal under `val` is therefore refused**, and the
message names `var` as the fix. Only a *literal* is refused: an object bound outside the class and named
here is sharing somebody asked for, and still compiles.

## The generated `new`

**A class that declares fields and writes no constructor is given one**, taking all of them — the fields
with no initialiser first, then the initialised ones, each optional with its initialiser as its default:

```slate
class Square
    var side
    var tags = []

print(Square.new(4))            // tags is a fresh []
print(Square.new(4, ["red"]))   // and tags said otherwise
```

```output
Square(side = 4, tags = [])
Square(side = 4, tags = ["red"])
```

A default is [worked out at the call](functions.md), so leaving `tags` out still gives every square its
own array. An initialiser may read a field bound before it — `var side` then `var area = side * side`.

**An initialised field comes after an uninitialised one whatever order they were written in**, since a
default has to be trailing: `var kind = "plain"` above `var side` gives `new(side, kind = "plain")`.

**A class that declares nothing gets no `new` at all**, rather than one answering an empty object;
`{ side: 4, proto: Square }` still works and is how such a class is made.

## Writing your own `new`

Write one when it has something to do. **`var` in its parameter list declares the field and assigns it**
— TypeScript's parameter property — and `self` is the object being made. The body runs for its effect
and the object is what comes back:

```slate
class Rect
    var area = 0

    new(var w, var h)
        if w < 0 || h < 0 then throw "a side cannot be negative"

        self.area = w * h

print(Rect(3, 4).area)
print(Rect(-1, 4).area catch e -> e.message)
```

```output
12
a side cannot be negative
```

A class with no declared fields keeps the plain form, where the body's value *is* the object:
`new(v) = { v: v }`. It is given the class as its proto on the way out.

## Class patterns

A class name written with fields after it tests and takes apart at once, which is what a Scala case
class does — by position, or by name:

```slate
class Square
    var side

class Circle
    var radius

class Rect
    var w
    var h

tell(v) = v match
    Square(n) -> s"a square of side ${n}"
    Circle { radius: r } -> s"a circle of ${r}"
    Rect { w, h } -> s"${w} by ${h}"
    _ -> "something else"

print(tell(Square(3)), tell(Circle(7)), tell(Rect(2, 5)), tell(42))
```

```output
a square of side 3 a circle of 7 2 by 5 something else
```

**The positional order is the constructor's, and that holds by construction rather than by convention**
— the field list a pattern is checked against *is* the parameter list of the `new` the class was given,
so `Square(n)` binds what `Square.new(4)` sets and the two cannot drift apart.

A class that builds its own object in a hand-written `new` has no such list and is **refused the
positional form by name**, with the named one offered instead.

**Naming the class is what lets a misspelled field be caught**: a bare `{ raduis: r }` is a legal pattern
that never matches, where `Circle { raduis: r }` is refused where it stands.

**The class name is also a shape value**, so `Circle.test(v)` asks at run time what `v is Circle` asks
where it is written, and `Circle.mismatch(v)` and `Circle.name()` answer too — see
[Types](types.md#a-type-is-a-value-under-its-own-name). A static the class declares under one of those
three names wins over it.

## `is` in the header

`is` in a class header is TypeScript's `implements` — a promise, checked where the class is written:

```slate
type Drawable = { draw: function }

class Pen is Drawable
    var ink

    draw(self) = "pen with " + self.ink

print(Pen("blue").draw())
```

```output
pen with blue
```

Leave `draw` out and the fault names the class, rather than arriving wherever something first wanted
to draw one:

```slate
type Drawable = { draw: function }

class Pen is Drawable
    var ink

    scribble(self) = "pen"
```

```error
Drawable
```

**It inherits nothing;** `from` does that. What it buys is *when* you find out: leave `draw` out and the
fault names the class rather than arriving wherever something first wanted to draw one. A class may
promise several types (`is Drawable, Named`) and descend from one.

A promise is kept by a method a base supplies, because an [object pattern](patterns.md) counts a field a
proto supplies.

## There is no `super`

And none is needed. A base class is an ordinary value in scope, and a method stored on it directly is
handed no receiver — so passing one is how you call it:

```slate
class Shape
    describe(self) = s"a shape of area ${self.area()}"

class Square from Shape
    var side

    area(self) = self.side * self.side

class Loud from Square
    new(side) = { side: side }

    describe(self) = upper(Shape.describe(self)) + "!"

print(Loud(2).describe())
```

```output
A SHAPE OF AREA 4!
```

`Shape.describe(self)` names the class the call was written in, which is what a super call means.
Counting links from whatever object turned up — `self.proto.proto` — is a different and wrong thing.

## Calling a class

**An object with a `new` is callable**, so `Square(4)` is `Square.new(4)`. That is what makes a
[data variant](data-types.md)'s constructor an ordinary function.
