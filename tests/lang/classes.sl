// Properties — `get` and `set` in a class body, and what makes one different from a field.
//
// **A property is the one member that is not stored**, so every walk over an object, `toJSON`, `with`
// and a class pattern are questions about fields and none of them mentions one. That claim is worth
// running on both back ends: the interpreter answers it out of `render.sysl`'s `walked_key` and node
// out of `js_rt_pat.sysl`'s `walkedKey`, which are two copies of one rule.

class Rect
    var w
    var h

    get area(self) = self.w * self.h

    get width(self) = self.w

    set width(self, v)
        self.w = v

class Circle
    var r

    get diameter(self) = self.r * 2

    get area(self) = self.diameter * self.diameter

class ReadOnly
    var n

    get twice(self) = self.n * 2

class WriteOnly
    var n

    set half(self, v)
        self.n = v / 2

class Shape
    get label(self) = s"area ${self.area}"

class Square from Shape
    var side

    get area(self) = self.side * self.side

class Loud from Shape
    var side

    get area(self) = self.side

    get label(self) = "loud"

// `get` and `set` are soft words, so a class that wants them as method names keeps them.
class Bag
    var items = []

    get(self, i) = self.items[i]

    set(self, i, v)
        self.items[i] = v

    get size(self) = len(self.items)

writesTwice(o)
    o.twice = 9

@test
a_getter_is_read_with_no_brackets() =
    assertEq(Rect.new(3, 4).area, 12)
    assertEq(Rect.new(3, 4).width, 3)

@test
a_setter_runs_where_the_property_is_assigned() =
    val r = Rect.new(3, 4)

    r.width = 10

    assertEq(r.w, 10)
    assertEq(r.width, 10)
    assertEq(r.area, 40)

@test
a_compound_assignment_reads_the_property_and_writes_it_back() =
    val r = Rect.new(3, 4)

    r.width += 2

    assertEq(r.width, 5)
    assertEq(r.w, 5)

@test
a_getter_may_read_another_getter() =
    assertEq(Circle.new(2).diameter, 4)
    assertEq(Circle.new(2).area, 16)

@test
a_property_is_inherited_and_overridden_exactly_as_a_method_is() =
    // `label` lives on the base and reads `area`, which only the two below it have — the receiver
    // rule doing for a property what it already does for a method.
    assertEq(Square.new(3).label, "area 9")
    assertEq(Loud.new(3).label, "loud")

@test
A_PROPERTY_IS_NOT_A_FIELD_AND_NOTHING_THAT_WALKS_ONE_REPORTS_IT() =
    val r = Rect.new(3, 4)

    assertEq(keys(r), ["w", "h"])
    assertEq(len(r), 2)
    assert(!has(r, "area"))
    assertEq(string(r), "Rect(w = 3, h = 4)")
    assertEq(toJSON(r), "{\"w\":3,\"h\":4}")

    // The key it is really stored under is on the CLASS, and is hidden there too.
    assertEq(keys(Rect), ["new"])

@test
a_copy_made_with_with_answers_the_property_from_its_own_fields() =
    val r = Rect.new(3, 4)
    val wider = r with { w: 10 }

    assertEq(wider.area, 40)
    assertEq(r.area, 12)

@test
a_class_pattern_takes_apart_fields_and_not_properties() =
    val said = Rect.new(3, 4) match
        Rect(w, h) -> s"${w} by ${h}"
        _ -> "something else"

    assertEq(said, "3 by 4")

@test
ONLY_A_DOT_READS_A_PROPERTY_BECAUSE_AN_INDEX_READS_THE_OBJECTS_OWN_TABLE() =
    val r = Rect.new(3, 4)

    assert(!has(r, "area"))
    assertEq(r["area"] ?? "nothing", "nothing")

@test
a_property_with_only_a_get_is_read_only_and_the_fault_names_it() =
    assertEq(ReadOnly.new(2).twice, 4)
    assertFaults(() -> writesTwice(ReadOnly.new(2)),
        "`twice` is read-only on ReadOnly -- it has a `get` and no `set`")

@test
a_property_with_only_a_set_is_write_only_and_the_READ_is_the_mistake() =
    val w = WriteOnly.new(0)

    w.half = 10

    assertEq(w.n, 5)
    assertFaults(() -> WriteOnly.new(0).half,
        "`half` is write-only on WriteOnly -- it has a `set` and no `get`")

@test
A_GETTER_IS_NOT_A_METHOD_AND_CALLING_ONE_SAYS_SO() =
    assertFaults(() -> Rect.new(3, 4).area(),
        "`area` is a property, not a method -- it is read as `.area`, with no brackets after it")

@test
A_PROPERTY_BELONGS_TO_THE_OBJECTS_A_CLASS_MAKES_AND_NOT_TO_THE_CLASS() =
    // The spelling that reaches a base's METHOD — `Shape.describe(self)` — has no counterpart for a
    // property, and this is what a reader gets for trying it rather than an argument count they
    // never wrote.
    assertFaults(() -> Shape.label,
        "`label` is a property of the objects `Shape` makes, and this is the class itself")

@test
get_and_set_are_soft_words_and_a_class_may_still_use_them_as_methods() =
    val b = Bag.new()

    push(b.items, 1)
    push(b.items, 2)
    b.set(0, 9)

    assertEq(b.get(0), 9)
    assertEq(b.size, 2)
