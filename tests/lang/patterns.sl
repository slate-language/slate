// Patterns: what `match`, `is`, a binding and a parameter all read.

type Named = { name: string }
type Tags = array of string
type Counts = object of integer
type Optional = { title: string, size?: integer }

data Shape
    Circle(r)
    Rect(w, h)
    Nothing

@test
a_match_answers_the_first_arm_that_applies() =
    describe(v) = v match
        0 -> "zero"
        integer -> "an integer"
        [a, b] -> "a pair"
        { name } -> name
        _ -> "something else"

    assertEq(describe(0), "zero")
    assertEq(describe(7), "an integer")
    assertEq(describe([1, 2]), "a pair")
    assertEq(describe({ name: "ada" }), "ada")
    assertEq(describe("x"), "something else")

@test
an_alternative_may_not_bind_and_a_literal_alternative_may() =
    weekend(d) = d match
        "sat" | "sun" -> true
        _ -> false

    assert(weekend("sun"))
    assert(!weekend("wed"))

@test
a_match_over_a_data_type_reads_a_variants_fields_positionally() =
    area(s) = s match
        Circle(r) -> r * r
        Rect(w, h) -> w * h
        Nothing -> 0

    assertEq(area(Circle(3)), 9)
    assertEq(area(Rect(2, 5)), 10)
    assertEq(area(Nothing), 0)

@test
no_arm_applying_is_a_fault() =
    only(v) = v match
        1 -> "one"

    assert(only(2) catch e -> true)

@test
a_binding_may_take_a_value_apart() =
    val [a, b] = [1, 2]
    val { x, y } = { x: 3, y: 4 }
    val [p, [q]] = [5, [6]]

    assertEq(a + b, 3)
    assertEq(x + y, 7)
    assertEq(p + q, 11)

@test
a_binding_that_does_not_fit_is_a_fault() =
    assert(unpack([1]) catch e -> true)

unpack(xs) =
    val [a, b] = xs

    a

@test
a_pattern_may_carry_a_default_and_it_fires_on_absence_alone() =
    val { title = "Untitled", size = 1 } = { size: 0 }

    assertEq(title, "Untitled")
    assertEq(size, 0)

    // Each binding gets a container of its own, which is what a default worked out AT THE BINDING
    // buys over one worked out once.
    fresh() =
        val { xs = [] } = {}

        push(xs, 1)

        xs

    assertEq(fresh(), [1])
    assertEq(fresh(), [1])

@test
a_row_of_names_with_defaults_binds_the_same_at_every_site() =
    // **The interpreter takes a row of bare names apart without the matcher, defaults and all**, so
    // each shape a default can take is asked here: a `val`, a parameter, a `for` head, a default that
    // reads a name to its left, one that runs only where the name is missing, and a loop whose second
    // turn leaves out what its first supplied -- the cell must take the default, not the last value.
    sized(opts) =
        val { width = 10, height, scale = 2 } = opts

        width * height * scale

    assertEq([sized({ width: 3, height: 4, scale: 5 }), sized({ height: 4 })], [60, 80])

    boxed({ w = 1, h = w * 2 }) = [w, h]

    assertEq([boxed({}), boxed({ w: 3 }), boxed({ h: 9 }), boxed({ w: 3, h: 4 })], [[1, 2], [3, 6], [1, 9], [3, 4]])

    var ran = 0

    counted() =
        ran = ran + 1
        ran * 100

    picked(o) =
        val { a, b = counted() } = o

        a + b

    assertEq([picked({ a: 1, b: 2 }), picked({ a: 1 }), picked({ a: 1, b: 3 })], [3, 101, 4])
    assertEq(ran, 1)

    turns(rows) =
        var seen = []

        for { k, v = "none" } in rows
            push(seen, k + ":" + v)

        seen

    assertEq(turns([{ k: "a", v: "x" }, { k: "b" }, { k: "c", v: "y" }]), ["a:x", "b:none", "c:y"])

    pairs(rows) =
        var seen = []

        for [a, b = 0] in rows
            push(seen, a + b)

        seen

    assertEq(pairs([[1, 2], [5], [3, 4]]), [3, 5, 7])

    // A field a proto supplies counts, and a `var` row can be written afterwards.
    reread(o) =
        var { x, y = 7 } = o

        y = y + x

        [x, y]

    assertEq(reread({ proto: { x: 1 } }), [1, 8])
    assertEq(reread({ x: 2, y: 3 }), [2, 5])

@test
a_parameter_may_take_its_argument_apart_and_may_carry_a_default() =
    doubled({ n }) = n * 2
    greet(who, greeting = "hello") = greeting + " " + who

    assertEq(doubled({ n: 4 }), 8)
    assertEq(greet("ada"), "hello ada")
    assertEq(greet("ada", "hi"), "hi ada")

@test
a_rest_parameter_gathers_and_a_call_may_spread() =
    count(first, ...rest) = [first, rest.length]

    assertEq(count(1), [1, 0])
    assertEq(count(1, 2, 3), [1, 2])
    assertEq(count(...[1, 2, 3]), [1, 2])

@test
a_type_is_a_named_pattern_and_a_value() =
    assert({ name: "ada" } is Named)
    assert(!({ name: 1 } is Named))
    assert(Named.test({ name: "ada" }))
    assertEq(Named.name(), "Named")

@test
array_of_and_object_of_describe_a_container_of_unknown_length() =
    assert(["a", "b"] is Tags)
    assert([] is Tags)
    assert(!(["a", 1] is Tags))
    assert({ a: 1, b: 2 } is Counts)

@test
an_optional_field_may_be_missing_and_may_not_be_wrong() =
    assert({ title: "x" } is Optional)
    assert({ title: "x", size: 1 } is Optional)
    assert(!({ title: "x", size: "big" } is Optional))

@test
mismatch_collects_where_test_stops() =
    val problems = Optional.mismatch({ size: "big" })

    assertEq(problems.length, 2)

@test
a_test_narrows_the_name_it_tested() =
    said(v) = if v is string then upper(v) else "not text"

    assertEq(said("ab"), "AB")
    assertEq(said(1), "not text")

@test
an_is_binds_into_the_surrounding_scope() =
    val v = { name: "ada" }

    assert(v is { name })
    assertEq(name, "ada")

@test
A_WILDCARD_BESIDE_A_BINDING_BINDS_NOTHING_AND_SHIFTS_NOTHING() =
    // A `_` takes a position and gives no value back, so a name written after one in the same
    // pattern must still get its own element rather than its neighbour's.
    val [_, second] = [1, 2]
    val [third, _, first] = [3, 9, 1]
    val { a: _, b } = { a: 1, b: 2 }

    assertEq(second, 2)
    assertEq([third, first], [3, 1])
    assertEq(b, 2)

    val said = [1, 2, 3] match
        [_, x, _] -> x
        _ -> 0

    assertEq(said, 2)

@test
A_LITERAL_MEANS_THE_SAME_AS_A_WHOLE_ARM_AND_INSIDE_A_SHAPE() =
    // A string, an integer, a boolean and a null are each written as a whole arm and again one
    // level down, where an array or an object pattern is what reaches them.
    kind(w) = w match
        "add" -> 1
        7 -> 2
        true -> 3
        null -> 4
        _ -> 0

    assertEq([kind("add"), kind(7), kind(true), kind(null)], [1, 2, 3, 4])
    assertEq([kind("sub"), kind(8), kind(false)], [0, 0, 0])

    said(v) = v match
        ["add", n] -> n
        [1, n] -> n * 10
        { tag: null, n } -> n * 100
        _ -> 0

    assertEq([said(["add", 5]), said([1, 5]), said({ tag: null, n: 5 })], [5, 50, 500])
    assertEq(said([2, 5]), 0)

    // A literal element that does not fit lets the next arm try, and a name beside it still binds.
    val moved = [2, 9] match
        [1, n] -> n
        [k, n] -> k + n

    assertEq(moved, 11)
