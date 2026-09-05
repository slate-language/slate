// `_` where a value goes -- the function nobody wrote.

@test
a_placeholder_is_the_parameter_of_the_argument_it_stands_in() =
    assertEq(map([1, 2, 3], _ * 2), [2, 4, 6])
    assertEq(filter([1, 2, 5, 9], _ > 3), [5, 9])
    assertEq(map(["ada", "al"], len(_)), [3, 2])

@test
a_placeholder_reads_the_same_as_the_lambda_it_stands_for() =
    assertEq(map([1, 2, 3], _ * 2), map([1, 2, 3], n -> n * 2))
    assertEq(filter([1, 2, 5], _ > 3), filter([1, 2, 5], n -> n > 3))

@test
a_placeholder_may_reach_a_field() =
    val ps = [{ name: "ada", age: 36 }, { name: "al", age: 20 }]

    assertEq(map(ps, _.name), ["ada", "al"])
    assertEq(map(filter(ps, _.age > 30), _.name), ["ada"])

@test
every_placeholder_is_a_parameter_of_its_own_left_to_right() =
    // The surprise worth knowing: two `_`s are two parameters, not two mentions of one. A
    // comparator wants exactly that, so it is where the rule reads as it should.
    val ps = [{ name: "ada", age: 36 }, { name: "al", age: 20 }]

    assertEq(map(sorted(ps, _.age < _.age), _.name), ["al", "ada"])

@test
a_call_around_a_placeholder_is_the_body_of_the_function() =
    // A lone `_` is handed to the scope outside it, so `f(_)` is a way of naming `f` rather than a
    // way of handing it an identity.
    twice(n) = n * 2

    assertEq(map([1, 2, 3], twice(_)), [2, 4, 6])

@test
handing_a_lone_placeholder_outward_is_what_makes_a_partial_application() =
    add(a, b) = a + b

    assertEq(map([1, 2, 3], add(_, 10)), [11, 12, 13])
    assertEq(map([1, 2, 3], add(10, _)), [11, 12, 13])

@test
a_placeholder_alone_where_nothing_encloses_it_is_the_identity() =
    val same = _

    assertEq(same(7), 7)
    assertEq(map([1, 2, 3], same), [1, 2, 3])

@test
brackets_are_a_placeholder_scope_of_their_own() =
    val add_one = (_ + 1)

    assertEq(add_one(41), 42)
    assertEq(map([1, 2], (_ * 10)), [10, 20])

@test
a_bindings_value_is_a_placeholder_scope() =
    val longer = len(_) > 3

    assertEq(longer("abcd"), true)
    assertEq(longer("ab"), false)

@test
an_assignments_value_is_a_placeholder_scope() =
    var f = n -> n

    f = _ * 3

    assertEq(f(4), 12)

@test
a_returns_value_is_a_placeholder_scope() =
    doubler() =
        return _ * 2

    assertEq(doubler()(21), 42)

@test
a_placeholder_in_a_pattern_is_still_the_wildcard() =
    // `_` in a match arm, in a destructuring and as a name bound by `val` are all patterns, and
    // none of them makes a function.
    val said = 7 match
        0 -> "zero"
        _ -> "something"

    val [_, second] = [1, 2]

    assertEq(said, "something")
    assertEq(second, 2)

@test
a_placeholder_function_closes_over_what_is_around_it() =
    val by = 10

    assertEq(map([1, 2], _ * by), [10, 20])
