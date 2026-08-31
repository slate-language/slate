// Data types, which are the closed side of the language `classes.sl` opened.
//
// A class is open: anything may descend from it, and no list says what the possibilities are. A
// `data` declaration is the other bargain -- it names every value its type can have, once, in one
// place, and a `match` over one is then something the compiler can check you have finished.
//
// Underneath, a variant IS a class from the data type, so nothing here is new machinery: the data
// type is the `proto`, `Circle(r)` declares a field and gets the constructor a class would, and
// `is` asks what it asks of any class.

data Shape
    // A variant with fields. `Circle(3)` makes one, and `Circle(r)` in a pattern takes it apart --
    // the field names come from this line, so they are written once.
    Circle(r)
    Rect(w, h)

    // A variant with no fields is the VALUE, not something to call. `Empty` is written where a value
    // is wanted and where a pattern is, and there is only ever one of it.
    Empty

    // A definition under the variants belongs to the data type, so every variant has it -- the
    // receiver rule protos already had, doing the work an abstract method does elsewhere.
    area(self) = self match
        Circle(r) -> 3 * r * r
        Rect(w, h) -> w * h
        Empty -> 0

    describe(self) = s"${self.name()} of ${self.area()}"

    name(self) = self match
        Circle(_) -> "a circle"
        Rect(w, h) if w == h -> "a square"
        Rect(_, _) -> "a rectangle"
        Empty -> "nothing"

val shapes = [Circle(2), Rect(3, 3), Rect(2, 5), Empty]

for s in shapes
    print(s.describe())

// A data value prints as the variant that made it, which is what makes one worth putting in a list.
print(shapes)

// **A data value does not change.** That is what lets one be compared by what it holds and used as a
// key, and it is why there is a copy rather than a write.
val c = Circle(3)
val bigger = c with { r: 10 }

print(c, bigger, c == Circle(3), c == bigger)

// So a table may be keyed by one.
var seen = {}

for s in shapes
    seen[s] = s.area()

print(seen[Rect(2, 5)], seen[Empty])

// **A match over an ANNOTATED data type must cover every variant**, which is most of what the closed
// list buys. Take the `Empty` arm out of this one and the compiler says so, naming it -- rather than
// the program running until the first `Empty` reaches it. The annotation is what makes that fair: it
// is the promise that every `Shape` may arrive here.
//
// A guarded arm does not count towards it, since its guard may say no to a value its pattern fits.
sides(s: Shape) = s match
    Circle(_) -> 0
    Rect(_, _) -> 4
    Empty -> 0

print(map(shapes, sides))

// Recursive, which is where the closed list earns the most: every case of the walk is on the page.
data Tree
    Leaf(v)
    Node(left, right)

    total(self) = self match
        Leaf(v) -> v
        Node(l, r) -> l.total() + r.total()

    depth(self) = self match
        Leaf(_) -> 1
        Node(l, r) -> 1 + max(l.depth(), r.depth())

val t = Node(Leaf(1), Node(Leaf(2), Node(Leaf(3), Leaf(4))))

print(t)
print(t.total(), t.depth())
