// The object model: what every value prints as, and what it means for two of them to be the same.
//
// This is the area that shipped two divergences between the back ends in one release — a `toString`
// hook running inside a DIAGNOSTIC under node and not in the interpreter, and an object that could
// not be used as a key at all under `slate js`, which made a `hash` hook unreachable there.

class Point
    var x
    var y

class Empty

class Money
    var cents

    equals(self, o) = o is Money && self.cents == o.cents
    toString(self) = "$" + string(self.cents)

class Keyed
    var v

    hash(self) = 7
    equals(self, o) = o is Keyed

data Shape
    Circle(r)
    Nothing

@test
a_class_instance_names_its_class_and_its_own_fields() =
    assertEq(string(Point.new(1, 2)), "Point(x = 1, y = 2)")
    assertEq(string(Point), "<class Point>")
    assertEq(string({ proto: Empty }), "Empty")

@test
equality_is_content_based_for_every_value_a_class_instance_included() =
    val p = Point.new(1, 2)
    val q = Point.new(1, 2)

    assert(p == q)
    assert(p == p)
    assert(Circle(3) == Circle(3))
    assert(Nothing == Nothing)

@test
eq_is_identity_and_is_the_only_way_to_ask_it() =
    val p = Point.new(1, 2)
    val q = Point.new(1, 2)

    assert(!p.eq(q))
    assert(p.eq(p))
    assert(p.ne(q))

    // A value with no identity answers equality instead, so `eq` is total.
    assert(1.eq(1))
    assert("a".eq("a"))
    assert(true.eq(true))
    assert(null.eq(null))
    assert(![1, 2].eq([1, 2]))

@test
a_function_is_equal_to_itself_and_to_nothing_else() =
    val f = (x) -> x
    val g = (x) -> x

    assert(f == f)
    assert(f.eq(f))
    assert(!f.eq(g))
    assert(!f.ne(f))

@test
equals_is_the_same_function_as_the_operator() =
    val p = Point.new(1, 2)

    assert(p.equals(Point.new(1, 2)))
    assert([1, 2].equals([1, 2]))
    assert((1).equals(1))

@test
a_class_that_writes_equals_decides_both_of_them() =
    val m = Money.new(150)

    assert(m == Money.new(150))
    assert(m.equals(Money.new(150)))
    assert(!m.eq(Money.new(150)))
    assert(!(m == 150))

@test
a_class_that_writes_toString_gets_it_everywhere_a_value_is_rendered() =
    val m = Money.new(150)

    assertEq(string(m), "$150")
    assertEq(m.toString(), "$150")
    assertEq(s"cost ${m}", "cost $150")
    assertEq(string([m]), "[$150]")

@test
toString_on_anything_else_is_what_print_would_have_shown() =
    assertEq((42).toString(), "42")
    assertEq([1, 2].toString(), "[1, 2]")
    assertEq(Circle(3).toString(), "Circle(3)")
    assertEq({ a: 1 }.toString(), "{a: 1}")
    assertEq(null.toString(), "null")

@test
a_diagnostic_does_not_run_the_programs_own_toString() =
    // A message about a fault may not run the program's own code to render its values: the hook can
    // fault in turn, and the second fault is the one the reader would be shown. Both back ends have
    // to draw that line in the same place, and for one release they did not.
    val m = Money.new(150)
    val said = (m match
        1 -> "one") catch e -> e.message

    assert(contains(said, "Money(cents = 150)"))
    assert(!contains(said, "$150"))

@test
a_tag_a_declaration_wrote_is_not_a_field() =
    val p = Point.new(1, 2)

    assertEq(keys(Point), ["new"])
    assertEq(keys(p), ["x", "y"])
    assertEq(keys(Circle(3)), ["r"])

@test
the_proto_a_nominal_value_is_reached_through_is_not_a_field_either() =
    // **`entries(One(5))` used to answer `[["a", 5], ["proto", <data One>]]`**, so an object copied
    // out of a data value was not the value it copied and `has(v, "proto")` was true of a name no
    // program wrote. The printer had always hidden it; the six walks over an object had not.
    val c = Circle(3)
    val p = Point.new(1, 2)

    assertEq(entries(c), [["r", 3]])
    assertEq(values(p), [1, 2])
    assertEq(len(p), 2)
    assert(!has(c, "proto"), "a data value's `proto` is machinery and not a field")
    assert(!has(p, "(class)"), "a tag is not a field a program can ask about either")

    // **And a `proto` a PROGRAM wrote is an ordinary field**, which is what keeps this a rule about
    // nominal values rather than a rule about the word.
    val plain = { n: 1, proto: { m: 2 } }

    assertEq(keys(plain), ["n", "proto"])
    assert(has(plain, "proto"))

@test
without_answers_a_new_object_with_that_key_gone() =
    val o = { a: 1, b: 2, c: 3 }

    assertEq(keys(without(o, "b")), ["a", "c"])
    assertEq(keys(o), ["a", "b", "c"])

    // A key that is not there is not an error, so removing one twice does what removing it once did.
    assertEq(keys(without(without(o, "b"), "b")), ["a", "c"])

    // **A copy of a data value is a data value**, which is `with`'s rule read the other way.
    val trimmed = without(Circle(3), "r")

    assert(trimmed is object)
    assertEq(keys(trimmed), [])

@test
with_on_a_data_value_refuses_a_field_its_type_does_not_have() =
    // **`Circle(3) with { id: "x" }` answered a `Circle` carrying an `id`**, printed as though the
    // declaration had a second positional field. Nothing else in the language can build one.
    val said = try
        Circle(3) with { id: "x" }
        ""
    catch e
        e.message

    assert(contains(said, "has no field `id`"), said)

    // A field the type DOES have still updates, which is what `with` is for.
    assertEq((Circle(3) with { r: 5 }).r, 5)

@test
a_class_with_its_own_hash_is_reachable_as_a_key() =
    var u = {}

    u[Keyed.new(1)] = "first"
    u[Keyed.new(2)] = "second"

    assertEq(u[Keyed.new(9)], "second")
    assertEq(len(u), 1)

@test
a_data_value_is_a_key_too() =
    var d = {}

    d[Circle(3)] = "circle three"

    assertEq(d[Circle(3)], "circle three")
    assert(!has(d, Circle(4)))

@test
is_walks_the_proto_chain_and_a_class_is_not_an_instance_of_itself() =
    val p = Point.new(1, 2)

    assert(p is Point)
    assert(!(Point is Point))
    assert(Circle(3) is Shape)
    assert(!(Circle(3) is Point))

@test
a_data_value_does_not_change() =
    val c = Circle(3)

    // An assignment is a statement, so the refusal is provoked inside a function rather than in an
    // expression that catches it.
    assert(writeTo(c) catch e -> true)
    assertEq(c.r, 3)

writeTo(c) =
    c.r = 4
