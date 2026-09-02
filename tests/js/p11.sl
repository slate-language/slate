// A declared type as a VALUE, on both back ends.
//
// The two hold a shape entirely differently -- the interpreter keeps a slot with the resolved
// pattern and the scope it was declared in, and the emitted program keeps the same pattern data
// `is` is emitted against, captured lexically -- so what they PRINT is the only thing that says
// they agree.

class Circle
    var r

data Shape
    Sq(w)
    Nothing

type NewNote = { title: string, text: string, pinned?: boolean }
type Pair = [integer, integer]
type Deep = { user: { name: string } }
type Holder = { c: Circle }
type Either = { v: integer | string }
type Both = { a: integer } & { b: string }
type Open = [integer, ...]
type Made = Sq(integer)

print(NewNote)
print(NewNote.name())
print(NewNote is shape)
print(NewNote == NewNote)
print(NewNote == Pair)

// A field the subject need not have, and one it must.
print(NewNote.test({ title: "a", text: "b" }))
print(NewNote.test({ title: "a", text: "b", pinned: true }))
print(NewNote.test({ title: "a", text: "b", pinned: 1 }))
print(NewNote.test({ title: "a", text: "b", extra: 1 }))
print(NewNote.mismatch({ title: 4 }))
print(NewNote.mismatch({ title: "a", text: "b" }))
print(NewNote.mismatch(7))

print(Pair.mismatch([1, "x"]))
print(Pair.mismatch([1]))
print(Pair.mismatch([1, 2, 3]))
print(Pair.mismatch("no"))
print(Open.mismatch([1, 2, 3]))
print(Open.mismatch([]))

print(Deep.mismatch({ user: { name: 1 } }))
print(Deep.mismatch({ user: 3 }))

// A class named inside a type, which is what a shape has to carry a scope for.
print(Holder.test({ c: Circle.new(1) }))
print(Holder.mismatch({ c: 3 }))

print(Either.mismatch({ v: true }))
print(Both.test({ a: 1, b: "y" }))
print(Both.mismatch({ a: "x" }))
print(Made.test(Sq(2)))
print(Made.mismatch(Sq("w")))
print(Made.mismatch(Nothing))

// A shape passed to a function is the whole reason a type is a value.
checked(shape, v) = if shape.test(v) then "fits " + shape.name() else shape.name() + ": " + toJSON(shape.mismatch(v))

print(checked(NewNote, { title: "a", text: "b" }))
print(checked(Pair, [1, "x"]))
