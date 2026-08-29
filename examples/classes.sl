// Classes, which are the objects on the previous page with a word in front of them.
//
// `class` binds a name to an object and `from` is that object's `proto`, so everything `objects.sl`
// showed is still what runs. What the word adds is two things a literal cannot give: **a method
// written in the ordinary definition syntax**, so its body may be a run of statements rather than
// whatever fits after `->`; and a **nominal identity**, so `v is Square` can ask which class a value
// was made from.

// An interface is a `type` over function fields -- nothing further is needed, functions being values.
type Drawable = { draw: function }

// `is Drawable` is a promise, not an inheritance: it gives the class nothing and only checks that it
// has what the type names. Leave `draw` out and the fault lands here, on the class that got it wrong,
// rather than wherever something first wanted to draw one.
class Shape is Drawable
    // A value the class itself carries. Every object made from it reads this one unless something
    // nearer says otherwise.
    val sides = 0

    draw(self) = s"<${self.name()}>"

    // `self` is the object the method was reached from. It is an ordinary parameter, and a method
    // reached through a proto is handed the object -- which is the rule protos already had.
    describe(self) = s"a ${self.name()} of area ${self.area()}"

class Square from Shape
    val sides = 4

    // **`var` declares a field each OBJECT gets**, where `val` above declares one the class holds. A
    // class that declares fields and writes no constructor is given one, taking every declared field
    // in the order they were written -- so `Square.new(4)` needs no `new` of its own.
    var side

    name(self) = "square"

    area(self) = self.side * self.side

class Circle from Shape
    var radius

    // A field with an initialiser is not a parameter of the generated constructor, and the
    // initialiser runs **once per object** -- which is the whole difference between `var` and `val`.
    // Under `val` every circle would share one array and push into it together.
    var marks = []

    name(self) = "circle"

    area(self) = 3.14159 * self.radius * self.radius

val shapes = [Square.new(4), Circle.new(1), Square.new(2)]

for s in shapes
    print(s.describe())

// `describe` lives on `Shape` and calls `area`, which only the two below it have -- so the call goes
// back down to whichever object it started from. That is dispatch, and no keyword arranges it.
print(Square.new(3).sides, Circle.new(3).sides)

// A subclass keeps the promise with a method its base supplies -- a pattern asks whether the value
// HAS the field, which is the question `.` answers, so it looks up the chain like everything else.
print(Square.new(1).draw(), Square.new(1) is Drawable)

// `is` asks which class an object was made from, and it walks the whole chain.
val sq = Square.new(1)

print(sq is Square, sq is Shape, sq is Circle)

// **It is not the same question as comparing protos.** `==` on objects is deep, so an object that
// merely holds the same fields compares equal -- and `is` says no, because it was not made here.
print({ side: 1, proto: Square } is Square, { side: 1 } is Square)

// A method may be given an annotation like any other, and a class name stands where a type does.
biggest(a: Shape, b: Shape) = if a.area() > b.area() then a else b

print(biggest(Square.new(2), Circle.new(2)).describe())

// One array each, not one between them.
val one = Circle.new(1)
val two = Circle.new(1)

one.marks.push("here")

print(one.marks, two.marks)

// -- a field the class gives a value, which a call may still say otherwise about ---------------------

// A declared field with an initialiser is an OPTIONAL parameter of the constructor, and that
// initialiser is its default. A default is worked out at the call, so leaving it out still gives
// every object its own array -- and an initialised field comes after the ones without, whatever
// order they were written in, because a default has to be trailing.
class Note
    var text
    var tags = []

val plain = Note.new("hello")
val tagged = Note.new("hello", ["urgent"])

plain.tags.push("mine")

print(plain.tags, tagged.tags, Note.new("x").tags)

// -- a constructor with something to do -------------------------------------------------------------

// Where a constructor has to check or compute, `var` in its parameter list declares the field and
// assigns it in one place, and `self` is the object being made. The body runs for its effect; the
// object is what comes back.
class Rect
    var area = 0

    new(var w, var h)
        if w < 0 || h < 0 then throw "a side cannot be negative"

        self.area = w * h

    describe(self) = s"${self.w}x${self.h} = ${self.area}"

print(Rect.new(3, 4).describe())

try
    Rect.new(-1, 2)
catch e
    print("refused: " + e.message)

// -- overriding, and reaching what was overridden --------------------------------------------------

// There is no `super`, and none is needed: a base class is an ordinary value in scope, and a method
// stored on it directly is handed no receiver -- so passing one is how you call it.
// **A field declaration is the class's own, not its base's.** `Square` declares `side`, and `Loud`
// declares it again to get a constructor of its own -- there being no `super` to pass it up to.
class Loud from Square
    var side

    describe(self) = upper(Shape.describe(self)) + "!"

print(Loud.new(2).describe())

// -- when a class is not what you want ---------------------------------------------------------------

// A class is shared behaviour. A method that has to capture something -- a counter, a handle, a
// secret nobody else may reach -- belongs on the object, and that is still an ordinary closure.
counter() =
    var n = 0
    var c = {}

    c.bump = () ->
        n += 1
        n

    c

val c = counter()

c.bump()
print(c.bump())
