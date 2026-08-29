// Classes, which are the objects on the previous page with a word in front of them.
//
// `class` binds a name to an object and `from` is that object's `proto`, so everything `objects.sl`
// showed is still what runs. What the word adds is two things a literal cannot give: **a method
// written in the ordinary definition syntax**, so its body may be a run of statements rather than
// whatever fits after `->`; and a **nominal identity**, so `v is Square` can ask which class a value
// was made from.

class Shape
    // A value the class itself carries. Every object made from it reads this one unless something
    // nearer says otherwise.
    val sides = 0

    // `self` is the object the method was reached from. It is an ordinary parameter, and a method
    // reached through a proto is handed the object -- which is the rule protos already had.
    describe(self) = s"a ${self.name()} of area ${self.area()}"

class Square from Shape
    val sides = 4

    // `new` is the constructor. It takes no receiver, there being no object yet, and whatever it
    // answers is given the class as its proto -- which is the `proto:` line you would otherwise have
    // to remember on every path that makes one.
    new(side) = { side: side }

    name(self) = "square"

    area(self) = self.side * self.side

class Circle from Shape
    new(radius) = { radius: radius }

    name(self) = "circle"

    area(self) = 3.14159 * self.radius * self.radius

val shapes = [Square.new(4), Circle.new(1), Square.new(2)]

for s in shapes
    print(s.describe())

// `describe` lives on `Shape` and calls `area`, which only the two below it have -- so the call goes
// back down to whichever object it started from. That is dispatch, and no keyword arranges it.
print(Square.new(3).sides, Circle.new(3).sides)

// `is` asks which class an object was made from, and it walks the whole chain.
val sq = Square.new(1)

print(sq is Square, sq is Shape, sq is Circle)

// **It is not the same question as comparing protos.** `==` on objects is deep, so an object that
// merely holds the same fields compares equal -- and `is` says no, because it was not made here.
print({ side: 1, proto: Square } is Square, { side: 1 } is Square)

// A method may be given an annotation like any other, and a class name stands where a type does.
biggest(a: Shape, b: Shape) = if a.area() > b.area() then a else b

print(biggest(Square.new(2), Circle.new(2)).describe())

// -- overriding, and reaching what was overridden --------------------------------------------------

// There is no `super`, and none is needed: a base class is an ordinary value in scope, and a method
// stored on it directly is handed no receiver -- so passing one is how you call it.
class Loud from Square
    new(side) = { side: side }

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
