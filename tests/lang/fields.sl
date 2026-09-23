// Annotated fields -- `var n: integer` in a class, `val k: T = e` on one, and `Circle(r: real)` in a
// data variant.
//
// **A field is a binding site like any `var`, so its annotation is checked where the value arrives**:
// at the constructor, which is where the object is made. The generated `new` carries the check at the
// top of its body exactly where `new(n: integer)` would, a written `new` checks the fields it fills
// from their initialisers, and a class `val` is checked where the class is made. Every one of these
// is the `CheckType` a local's annotation turns into, so both back ends say one sentence.

class Counter
    var count: integer = 0
    var step: integer | real = 1

    bump(self)
        self.count += self.step

class Holder
    var run: (integer) -> integer = n -> n + 1

class Bag
    var tags: array of string = []
    var seen: Map[string, integer] = Map()
    var pair: [integer, string] = [1, "a"]
    var where: { x: integer, y: integer } = { x: 0, y: 0 }

class Node
    var value: integer
    var next: Node | null = null

class Limits
    val most: integer = 10

class Tagged
    var tag: string = "plain"

    new(var n: integer)
        if n < 0 then throw "negative"

data Shape
    Circle(r: real)
    Rect(w: number, h: number)

data Cell
    Wrapped(run: (integer) -> integer)
    Placed(at: { x: integer, y: integer }, weight: integer = 1)

anything(v) = v

said(f) = f() catch e -> e.message

@test
A_SIMPLE_TYPE_ON_A_CLASS_FIELD_TAKES_ITS_INITIALISER_AND_A_VALUE_THAT_FITS() =
    val c = Counter()

    c.bump()
    assertEq(c.count, 1)
    assertEq(Counter(5, 2.5).step, 2.5)

@test
A_FUNCTION_TYPE_ON_A_CLASS_FIELD_IS_READ_AS_ONE() =
    assertEq(Holder().run(2), 3)
    assertEq(Holder(n -> n * 10).run(2), 20)

@test
A_GENERIC_A_TUPLE_AND_A_SHAPE_ON_A_CLASS_FIELD_ARE_ANNOTATIONS_LIKE_ANY_OTHER() =
    val b = Bag(["x"])

    b.seen.set("a", 1)
    assertEq(b.tags, ["x"])
    assertEq(b.seen.get("a"), 1)
    assertEq(b.pair, [1, "a"])
    assertEq(b.where.x, 0)

@test
A_FIELD_MAY_NAME_ITS_OWN_CLASS() =
    assertEq(Node(1, Node(2)).next.value, 2)
    assertEq(Node(1).next, null)

@test
A_CLASS_FIELD_REFUSES_A_VALUE_THAT_DOES_NOT_FIT_ITS_ANNOTATION() =
    assertEq(said(() -> Counter(anything("x"))), "`count` was declared integer, and was given \"x\"")
    assertEq(said(() -> Node(1, anything(5))), "`next` was declared Node | null, and was given 5")
    assert(said(() -> Holder(anything("no"))).contains("`run` was declared (integer) -> integer"))
    assert(said(() -> Bag(anything([1]))).contains("`tags` was declared array of string"))

@test
AN_ANNOTATED_CLASS_VAL_IS_CHECKED_WHERE_THE_CLASS_IS_MADE() =
    assertEq(Limits.most, 10)

@test
A_WRITTEN_new_CHECKS_WHAT_ITS_PARAMETERS_DECLARE_AND_FILLS_THE_REST_FROM_THEIR_INITIALISERS() =
    assertEq(Tagged(3).tag, "plain")
    assertEq(said(() -> Tagged(anything("x"))), "`n` was declared integer, and was given \"x\"")

@test
A_DATA_VARIANT_FIELD_TAKES_A_TYPE() =
    assertEq(Circle(1.5).r, 1.5)
    assertEq(Rect(2, 3.5).h, 3.5)
    assertEq(Wrapped(n -> n * 2).run(3), 6)
    assertEq(Placed({ x: 1, y: 2 }).weight, 1)
    assertEq(Placed({ x: 1, y: 2 }, 4).at.y, 2)

@test
A_DATA_VARIANT_FIELD_REFUSES_A_VALUE_THAT_DOES_NOT_FIT() =
    assertEq(said(() -> Circle(anything(1))), "`r` was declared real, and was given 1")
    assertEq(said(() -> Placed(anything({ x: 1 }))).contains("`at` was declared"), true)
    assertEq(said(() -> Placed({ x: 1, y: 2 }, anything("heavy"))), "`weight` was declared integer, and was given \"heavy\"")

@test
AN_ANNOTATED_VARIANT_STILL_TAKES_ITS_FIELDS_APART_BY_POSITION() =
    val got = Circle(2.0) match
        Circle(r) -> r
        _ -> 0.0

    assertEq(got, 2.0)
