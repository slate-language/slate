// Assignment: the compound forms, and the three that write only under a condition.
//
// The compiler's own tests drive the interpreter in this process, so they say nothing about
// `slate js` — and the three short-circuiting forms are emitted natively there, which is exactly
// the place two back ends can disagree about what is falsy.

// A module-level `var` is a different storage from a local one, so each form is asked of both.
var topAbsent = null
var topZero = 0
var topEmpty = ""

topAbsent ??= "written"
topZero ??= 99
topEmpty ||= "filled"

@test
A_SHORT_CIRCUITING_ASSIGNMENT_WRITES_A_MODULE_LEVEL_var() =
    assertEq(topAbsent, "written")
    assertEq(topZero, 0)
    assertEq(topEmpty, "filled")

@test
the_three_forms_ask_the_question_the_operator_they_are_named_after_asks() =
    var a = null
    var b = 3

    a ??= 5
    b ??= 5

    assertEq(a, 5)
    assertEq(b, 3)

    var c = 0
    var d = 1

    c ||= 9
    d ||= 9

    assertEq(c, 9)
    assertEq(d, 1)

    var e = 1
    var f = null

    e &&= 7
    f &&= 7

    assertEq(e, 7)
    assertEq(f, null)

@test
WHAT_IS_FALSE_AND_WHAT_IS_ABSENT_ARE_TWO_DIFFERENT_QUESTIONS() =
    // `??=` asks about absence alone, so every falsy value that is there is left where it is.
    var zero = 0
    var empty = ""
    var no = false
    var nan = 0 / 0

    zero ??= 1
    empty ??= "x"
    no ??= true
    nan ??= 5

    assertEq(zero, 0)
    assertEq(empty, "")
    assertEq(no, false)
    assertEq(nan == nan, false)

    // `||=` asks about truth, and all four of those are false by it.
    var zero2 = 0
    var empty2 = ""
    var no2 = false
    var nan2 = 0 / 0

    zero2 ||= 1
    empty2 ||= "x"
    no2 ||= true
    nan2 ||= 5

    assertEq(zero2, 1)
    assertEq(empty2, "x")
    assertEq(no2, true)
    assertEq(nan2, 5)

@test
A_FIELD_A_MISSING_FIELD_AND_AN_ELEMENT_ARE_EACH_A_PLACE() =
    val o = { a: null, b: 2 }

    o.a ??= 1
    o.b ||= 33

    assertEq(o, { a: 1, b: 2 })

    // A field that is not there at all reads as an absence, so `??=` writes it.
    val bare = { }

    bare.made ??= 5

    assertEq(bare, { made: 5 })

    val xs = [null, 0, 5]

    xs[0] ??= 1
    xs[1] ||= 2
    xs[2] &&= 6

    assertEq(xs, [1, 2, 6])

@test
THE_VALUE_IS_NOT_WORKED_OUT_WHERE_THE_PLACE_IS_LEFT_ALONE() =
    var calls = 0

    built()
        calls += 1
        "made"

    var there = 3
    var missing = null

    there ??= built()

    assertEq(calls, 0)

    missing ??= built()

    assertEq(missing, "made")
    assertEq(calls, 1)

    var truthy = 1

    truthy ||= built()

    assertEq(calls, 1)

    var falsy = null

    falsy &&= built()

    assertEq(calls, 1)

@test
the_place_is_worked_out_exactly_once_whichever_way_the_test_goes() =
    var reached = 0

    where()
        reached += 1
        0

    val absent = [null]

    absent[where()] ??= 4

    assertEq(absent, [4])
    assertEq(reached, 1)

    val present = [9]

    present[where()] ??= 4

    assertEq(present, [9])
    assertEq(reached, 2)

    var asked = 0

    which()
        asked += 1
        { n: null }

    which().n ??= 7

    assertEq(asked, 1)

@test
a_compound_form_evaluates_its_place_once_as_well() =
    var n = 10

    n += 5
    n -= 1
    n *= 2

    assertEq(n, 28)

    var reached = 0

    next()
        reached += 1
        0

    val xs = [10]

    xs[next()] += 1

    assertEq(xs, [11])
    assertEq(reached, 1)
