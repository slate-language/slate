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
a_parameter_may_take_its_argument_apart_and_may_carry_a_default() =
    doubled({ n }) = n * 2
    greet(who, greeting = "hello") = greeting + " " + who

    assertEq(doubled({ n: 4 }), 8)
    assertEq(greet("ada"), "hello ada")
    assertEq(greet("ada", "hi"), "hi ada")

@test
a_rest_parameter_gathers_and_a_call_may_spread() =
    count(first, ...rest) = [first, len(rest)]

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

    assertEq(len(problems), 2)

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
