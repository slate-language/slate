// Objects that share their behaviour.
//
// A slate object is a hash table, and `proto` is an ordinary field in it -- no syntax, no new kind of
// value. What it buys is that a lookup which misses carries on into the proto, so one table of
// methods serves every object pointing at it.
//
// **A method reached through a proto is handed the object it was found on.** One `dist` serves every
// point, so it cannot have captured a particular one -- it has to be told. A method stored on the
// object itself has already captured what it needs and is given nothing extra, which is why the
// older idiom below still reads the same.

val Shape = {
    // `self` is the object the method was reached from. It is an ordinary parameter.
    describe: self -> s"${self.kind} with area ${self.area()}",

    // A default any shape may override.
    kind: "shape"
}

val Square = {
    proto: Shape,
    kind: "square",
    area: self -> self.side * self.side
}

val Circle = {
    proto: Shape,
    kind: "circle",
    area: self -> 3.14159 * self.radius * self.radius
}

square(side) = { side: side, proto: Square }
circle(radius) = { radius: radius, proto: Circle }

print(square(4).describe())
print(circle(1).describe())

// `describe` lives on `Shape` and calls `area`, which only `Square` and `Circle` have -- so the call
// goes back down to whichever object it started from. That is dispatch, and it needed no keyword.
val shapes = [square(2), circle(2), square(3)]

for s in shapes
    print(s.describe())

// The proto is the identity: two squares share one, and a square is not a circle.
print(square(1).proto == square(9).proto, square(1).proto == Circle)

// A field written on the object shadows what the proto would have given.
print({ side: 2, proto: Square, kind: "a very square square" }.describe())

// **The older idiom is untouched.** A method the object carries itself captured what it needed when
// it was made, so it takes no receiver -- and there is one of it per object, which is the cost the
// proto above exists to avoid.
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
