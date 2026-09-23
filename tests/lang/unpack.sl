// What a destructuring binding says when the value does not fit.
//
// **A binding has no next arm, so a shape that does not fit is a fault, and the fault says which
// half is wrong** -- the shape the binding wanted, and the thing that arrived. The sentences are
// asserted WHOLE rather than by a fragment, because the point of this file is that both back ends
// say the same words: a `val`, a `for` head and a parameter each reach the fault by their own path,
// and on the interpreter a row of bare names skips the matcher altogether.

said(f) =
    try
        f()
        "no fault"
    catch e
        e.message

class Point
    var x

@test
an_array_too_short_or_too_long_says_how_many_it_takes() =
    assertEq(said(() ->
        val [a, b] = [1]
        a), "this binding takes 2 elements out of an array, and this one has 1")

    assertEq(said(() ->
        val [a, b] = [1, 2, 3]
        a), "this binding takes 2 elements out of an array, and this one has 3")

    // An open pattern, a rest and a default each make the count a floor.
    assertEq(said(() ->
        val [a, b, ...r] = [1]
        a), "this binding takes at least 2 elements out of an array, and this one has 1")

    assertEq(said(() ->
        val [a, b = 2] = []
        a), "this binding takes at least 1 element out of an array, and this one has 0")

@test
a_value_that_is_not_an_array_is_named() =
    assertEq(said(() ->
        val [a, b] = 1
        a), "this binding takes an array apart, and this is an integer")

    assertEq(said(() ->
        val [a] = "xy"
        a), "this binding takes an array apart, and this is a string")

    assertEq(said(() ->
        val [a] = { a: 1 }
        a), "this binding takes an array apart, and this is an object")

    assertEq(said(() ->
        val [a] = Point.new(1)
        a), "this binding takes an array apart, and this is an object")

@test
an_object_missing_a_field_names_the_field() =
    assertEq(said(() ->
        val { a, b } = { b: 1 }
        a), "this object has no field called `a`, which this binding takes out of it")

    // A field with a default may be missing, so it is never the one named.
    assertEq(said(() ->
        val { a, b = 1 } = {}
        a), "this object has no field called `a`, which this binding takes out of it")

    assertEq(said(() ->
        val { y } = Point.new(1)
        y), "this object has no field called `y`, which this binding takes out of it")

    // A field a proto supplies is there, as it is to `.`.
    assertEq(said(() ->
        val base = { a: 1 }
        val { a, b } = { proto: base, c: 1 }
        b), "this object has no field called `b`, which this binding takes out of it")

@test
a_value_that_is_not_an_object_is_named() =
    assertEq(said(() ->
        val { a } = null
        a), "this binding takes an object apart, and this is null")

    assertEq(said(() ->
        val { a } = [1]
        a), "this binding takes an object apart, and this is an array")

    assertEq(said(() ->
        val { a } = 1.5
        a), "this binding takes an object apart, and this is a real")

    assertEq(said(() ->
        val { a } = true
        a), "this binding takes an object apart, and this is a boolean")

@test
a_nested_failure_says_the_outer_shape_fits_and_a_part_does_not() =
    assertEq(said(() ->
        val [a, [b, c]] = [1, [2]]
        a), "this array has the right number of elements, and one of them does not fit the binding")

    assertEq(said(() ->
        val [a, { b }] = [1, { c: 1 }]
        a), "this array has the right number of elements, and one of them does not fit the binding")

    assertEq(said(() ->
        val { a: [b, c] } = { a: 1 }
        b), "every field this binding names is there, and one of them does not fit")

    assertEq(said(() ->
        val { a, b: [c] } = { a: 1, b: [] }
        a), "every field this binding names is there, and one of them does not fit")

@test
a_for_head_says_what_a_val_says() =
    var seen = []

    assertEq(said(() ->
        for [a, b] in [[1, 2], [3]]
            seen.push(a)
        0), "this binding takes 2 elements out of an array, and this one has 1")

    assertEq(said(() ->
        for { a } in [{ a: 1 }, { b: 2 }]
            seen.push(a)
        0), "this object has no field called `a`, which this binding takes out of it")

    assertEq(said(() ->
        for [a, b] in [5]
            seen.push(a)
        0), "this binding takes an array apart, and this is an integer")

    // The turns before the one that did not fit still ran.
    assertEq(seen, [1, 1])

@test
a_parameter_says_what_a_val_says() =
    pair([a, b]) = a
    field({ a }) = a

    assertEq(said(() -> pair([1])), "this binding takes 2 elements out of an array, and this one has 1")
    assertEq(said(() -> pair("ab")), "this binding takes an array apart, and this is a string")
    assertEq(said(() -> field(5)), "this binding takes an object apart, and this is an integer")
    assertEq(said(() -> field({ b: 1 })), "this object has no field called `a`, which this binding takes out of it")
