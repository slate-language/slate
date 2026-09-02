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

// -- taking a class apart in a pattern ---------------------------------------------------------------

// A class name in a pattern tests which class made the value. Written with fields after it, it takes
// the value apart in the same breath -- which is what a Scala case class does, and what `data`'s
// variants already did.

// **By position**, in the order the constructor takes them. That is not a convention to remember:
// the list a pattern is checked against IS the parameter list of the `new` the class was given, so
// `Square(n)` binds what `Square.new(4)` sets. A class that builds its own object in a hand-written
// `new` has no such list, and slate says so rather than guessing.
tell(v) = v match
    Square(n) -> s"a square of side ${n}"
    Circle(r, _) -> s"a circle of radius ${r}"
    _ -> "something else"

print(tell(Square.new(4)))
print(tell(Circle.new(1)))
print(tell(7))

// **Or by name**, which is the one to reach for by default: it does not depend on the order, it picks
// the fields it wants out of however many there are, and it reads as the object literal does.
// `{ side }` is the shorthand for `{ side: side }` that every object pattern has.
describe_one(v) = v match
    Square { side } -> s"square ${side}"
    Circle { radius: r } -> s"circle ${r}"
    _ -> "?"

print(describe_one(Square.new(2)))
print(describe_one(Circle.new(3)))

// **Naming the class is what lets a MISSPELLED FIELD be caught.** A bare `{ raduis: r }` is a legal
// pattern that simply never matches, because any object may lack any field -- so the arm is silently
// dead. Written after a class name there is a declaration to check it against, and `Circle { raduis: r }`
// is refused where it stands.

// Both forms nest, and both take an `@` binding, patterns being patterns wherever they stand.
val pair = [Square.new(2), Circle.new(1)]

print(pair match
    [whole @ Square { side }, Circle(r, _)] -> s"${side} and ${r}, from ${whole.name()}"
    _ -> "?")

// **The test is the proto WALK, not one link of it**, so a pattern written for a base class takes an
// object of a class descended from it apart. That is the same question `is` answers.
print(Loud.new(3) match
    Square(n) -> s"a Loud of side ${n}, matched as a Square"
    _ -> "?")

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

// **AN OBJECT MAY ANSWER FOR AN OPERATOR.** `equals` and `hash` have always been proto hooks looked
// up by name, and these are the same mechanism widened: the word is the method's name, so a class
// body writes one with the definition syntax it already has.
class Money
    var cents

    plus(self, o) = Money(self.cents + o.cents)
    minus(self, o) = Money(self.cents - o.cents)
    times(self, n) = Money(self.cents * n)
    negated(self) = Money(-self.cents)

    // **Ordering is ONE hook, not four.** It answers a number below, at or above zero, and `<`,
    // `<=`, `>` and `>=` all read its sign -- so a type cannot order inconsistently with itself.
    compare(self, o) = self.cents - o.cents

    string(self) = "$" + string(self.cents / 100)

val rent = Money(90000)
val bill = Money(4500)

print((rent + bill).string(), (rent - bill).string(), (rent * 2).string(), (-bill).string())
print(bill < rent, rent <= rent)

// **`==` keeps its own hook and is NOT routed through `compare`**, a type whose ordering is coarser
// than its equality being an ordinary thing to want. `equals` is handed no receiver, which is what
// keeps every hook written before operators existed working -- so it is written as a captured
// function rather than as a method, and a class wanting one says so on the object.
print(rent == Money(90000), rent == bill)

// So a comparator is an ordinary `<`, and sorting falls out of the one hook.
print(map(sorted([rent, bill, Money(12000)], (a, b) -> a < b), m -> m.string()))

// **THE LEFT OPERAND DECIDES AND THE RIGHT IS NEVER ASKED**, which is `equals`'s rule already --
// so there is no reflected form and `2 * rent` is not `rent.times(2)`.
print((2 * rent) catch e -> e.message)

// **AND A FUNCTION MAY GATHER WHAT IS LEFT OVER.** slate could spread at a call long before it
// could gather at a definition; `...rest` is always bound, to an empty array where a call gave
// nothing past the fixed parameters.
total(first, ...others) =
    var sum = first

    for m in others
        sum = sum + m

    sum

print(total(rent).string())
print(total(rent, bill, Money(12000)).string())

// It composes with the spread it is the counterpart of.
val monthly = [rent, bill]

print(total(...monthly).string())
