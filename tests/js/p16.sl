// A class name and a data name as SHAPE VALUES, on both back ends.
//
// The two hold the shape differently and the difference is the reason this file exists: the
// interpreter interns a slot holding the resolved pattern and the scope the declaration ran in,
// while the emitted program keeps the same pattern data `is` is emitted against -- and that pattern
// names the class it sits inside, so it has to be worked out on first use rather than where it is
// written. What the two PRINT is the only thing that says they agree.

class Point
    var x
    var y

class Box
    var v

    // A rest parameter, so the one function serves both calls below: reached as `Box`'s own field
    // it is given what was written, and reached from `Lid` through the chain it is also given the
    // class -- the receiver rule telling a shared member which one it is working on.
    val test = (...args) -> "mine"

class Lid from Box
    var w

data Failure
    NotFound(what)
    Denied(who, why)
    Empty

    said(self) = self match
        NotFound(w) -> "no " + w
        Denied(w, _) -> "not " + w
        Empty -> "nothing"

print(Point.name(), Point.test(Point(1, 2)), Point.test({ x: 1, y: 2 }))
print(Point.mismatch(3))
print(Point.mismatch({ x: 1 }))

print(Failure.name(), Failure.test(NotFound("a")), Failure.test(Empty), Failure.test(3))
print(Failure.mismatch("no"))

print(NotFound.name(), NotFound.test(NotFound("a")), NotFound.test(Denied("a", "b")))
print(Denied.mismatch(Empty))
print(Empty.name(), Empty.test(Empty), Empty.test(NotFound("a")))

// A static the program declared wins over the shape's, and the two it did not declare still answer.
print(Box.test(1), Box.name(), Box.mismatch(2))

// A subclass reaches the base's static through the chain -- which hands it the class it was reached
// from, a shared member being told which one it is working on -- and answers about ITSELF where the
// shape is what answers.
print(Lid.mismatch(2), Lid.test(1))

// **A parameter annotated `shape` takes all three declarations**, which is the whole use a shape
// value has -- and an annotation is the only check a consumer's call gets.
fits(s: shape, v) = s.test(v)

print(Point is shape, Failure is shape, Empty is shape, Point(1, 2) is shape)

print(fits(Point, Point(1, 2)), fits(Failure, Empty), fits(Failure, 1))
print(has(Point(1, 2), "name"))

// A tag is not a field, on either back end.
print(keys(Point), keys(Failure), len(Point))
// `Failure` itself is left out of this line: its shared object holds a method, and the two back ends
// print a FUNCTION differently -- `<function of 1>` against `<function>`. That is a divergence of
// its own and not this file's business; `keys` above is what says the tag is not a field.
print(Point, Empty, NotFound("a"), Denied("a", "b"))
print(NotFound("x").said(), Empty.said())
