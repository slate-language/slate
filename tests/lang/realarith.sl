// What an operator answers when a REAL is among its operands, asked of both hosts.
//
// **The interpreter answers a real in the operator's own instruction**, beside the pair of whole
// numbers, and hands everything else to the general arithmetic; the JavaScript back end has one path.
// So a fast path that promoted differently, rounded differently, or forgot what NaN, an infinity or
// a negative zero does would be a wrong answer on one host only -- and every question here is asked
// through a function's parameters, so neither operand is a literal the compiler could have seen.
//
// A real is printed with `string`, which is how a whole-valued real is told from the integer it
// equals only by `is real` -- both are checked where the kind is the point.

plus(a, b) = a + b
minus(a, b) = a - b
times(a, b) = a * b
over(a, b) = a / b
below(a, b) = a < b
atMost(a, b) = a <= b
above(a, b) = a > b
atLeast(a, b) = a >= b
equal(a, b) = a == b
unequal(a, b) = a != b
negate(a) = -a
remainder(a, b) = a % b
whole(a, b) = a \ b

// The sign of a zero, which `==` cannot see: one over it is an infinity of the same sign.
signOf(z) = string(1.0 / z)

// What a fault said, or "" where there was none.
said(f) =
    var message = ""

    try
        f()
    catch e
        message = e.message

    message

// -- the four arithmetic operators -----------------------------------------------------------------

@test
TWO_REALS_ANSWER_A_REAL_THROUGH_EVERY_ARITHMETIC_OPERATOR()
    assertEq(string(plus(1.5, 2.25)), "3.75")
    assertEq(string(minus(1.5, 2.25)), "-0.75")
    assertEq(string(times(1.5, 2.25)), "3.375")
    assertEq(string(over(1.5, 0.5)), "3")
    assert(over(1.5, 0.5) is real, "a real quotient that is whole is still a real")
    assert(times(2.0, 1.5) is real, "a real product that is whole is still a real")

@test
AN_INTEGER_ON_THE_LEFT_OF_A_REAL_PROMOTES()
    assertEq(string(plus(1, 2.5)), "3.5")
    assertEq(string(minus(1, 2.5)), "-1.5")
    assertEq(string(times(3, 2.5)), "7.5")
    assertEq(string(over(5, 2.5)), "2")
    assert(times(2, 1.5) is real, "an integer times a real is a real")
    assert(plus(2, 1.0) is real, "an integer plus a real is a real")

@test
A_REAL_ON_THE_LEFT_OF_AN_INTEGER_PROMOTES()
    assertEq(string(plus(2.5, 1)), "3.5")
    assertEq(string(minus(2.5, 1)), "1.5")
    assertEq(string(times(2.5, 3)), "7.5")
    assertEq(string(over(2.5, 5)), "0.5")
    assert(minus(3.0, 1) is real, "a real minus an integer is a real")

@test
TWO_INTEGERS_STILL_DIVIDE_INTO_A_REAL_AND_STILL_GROW_WHERE_THEY_OVERFLOW()
    assertEq(string(over(1, 2)), "0.5")
    assert(over(4, 2) is real, "`/` of two integers is a real")
    assertEq(string(plus(9223372036854775807, 1)), "9223372036854775808")
    assertEq(string(minus(-9223372036854775807, 2)), "-9223372036854775809")
    assertEq(string(times(4611686018427387904, 2)), "9223372036854775808")
    assert(plus(1, 2) is integer, "two integers add to an integer")

@test
A_REAL_MEETING_A_GROWN_INTEGER_IS_STILL_THE_GENERAL_ARITHMETIC()
    val big = times(4611686018427387904, 4)

    assertEq(plus(big, 0.5), plus(0.5, big))
    assert(plus(0.5, big) is real, "a real plus a big integer is a real")
    assert(below(0.5, big), "a real is below a big integer")

@test
A_NEGATIVE_REAL_NEGATES_AND_ZERO_KEEPS_ITS_SIGN()
    assertEq(string(negate(2.5)), "-2.5")
    assertEq(signOf(negate(0.0)), "-Infinity")
    assertEq(signOf(times(-1, 0.0)), "-Infinity")
    assertEq(signOf(times(0.0, -1)), "-Infinity")
    assertEq(signOf(minus(0.0, 0.0)), "Infinity")
    assertEq(signOf(plus(negate(0.0), 0.0)), "Infinity")
    assertEq(signOf(plus(negate(0.0), negate(0.0))), "-Infinity")
    assert(equal(negate(0.0), 0), "a negative zero equals zero")

// -- NaN and the infinities ------------------------------------------------------------------------

@test
NAN_IS_EQUAL_TO_NOTHING_AND_ORDERED_AGAINST_NOTHING()
    val nan = over(0.0, 0.0)

    assertEq(string(nan), "NaN")
    assertEq(string(plus(nan, 1)), "NaN")
    assertEq(string(times(2, nan)), "NaN")
    assert(!equal(nan, nan), "NaN equals itself")
    assert(unequal(nan, nan), "NaN is not unequal to itself")
    assert(!equal(nan, 1), "NaN equals an integer")
    assert(unequal(1, nan), "an integer is not unequal to NaN")
    assert(!below(nan, 1) && !atMost(nan, 1) && !above(nan, 1) && !atLeast(nan, 1), "NaN is ordered")
    assert(!below(1, nan) && !atMost(1, nan) && !above(1, nan) && !atLeast(1, nan), "NaN is ordered")
    assert(!below(nan, nan) && !atLeast(nan, nan), "NaN is ordered against itself")

@test
AN_INFINITY_IS_WHAT_IEEE_SAYS_IT_IS()
    val inf = over(1.0, 0)

    assertEq(string(inf), "Infinity")
    assertEq(string(over(-1, 0.0)), "-Infinity")
    assertEq(string(over(1, 0)), "Infinity")
    assertEq(string(plus(inf, negate(inf))), "NaN")
    assertEq(string(times(inf, 0)), "NaN")
    assertEq(string(minus(inf, 1)), "Infinity")
    assertEq(over(1, inf), 0)
    assert(atMost(inf, inf) && !below(inf, inf), "an infinity is itself")
    assert(above(inf, 9223372036854775807), "an infinity is above every integer")
    assert(below(negate(inf), -9223372036854775807), "minus infinity is below every integer")

// -- the comparisons -------------------------------------------------------------------------------

@test
A_COMPARISON_OF_MIXED_KINDS_PROMOTES_THE_INTEGER()
    assert(below(1, 1.5) && !below(1.5, 1), "`<` of mixed kinds")
    assert(atMost(2, 2.0) && atMost(2.0, 2) && !atMost(2.5, 2), "`<=` of mixed kinds")
    assert(above(2.5, 2) && !above(2, 2.5), "`>` of mixed kinds")
    assert(atLeast(2.0, 2) && atLeast(2, 2.0) && !atLeast(1, 1.5), "`>=` of mixed kinds")
    assert(below(1.25, 1.5) && atLeast(1.5, 1.5) && !above(1.25, 1.5), "two reals")
    assert(equal(2, 2.0) && equal(2.0, 2) && equal(2.5, 2.5), "`==` of numbers that name one number")
    assert(unequal(2, 2.5) && unequal(2.5, 2) && !unequal(2.0, 2), "`!=` of mixed kinds")
    assert(!equal(2.5, "2.5") && unequal(2.5, "2.5"), "a real and a string are not equal")

// -- the operators a real does not reach -----------------------------------------------------------

@test
A_REMAINDER_AND_A_WHOLE_DIVISION_STILL_REFUSE_A_REAL()
    assert(said(() -> remainder(5.5, 2)).contains("a remainder is taken of integers"), "`%` of a real")
    assert(said(() -> remainder(5, 2.0)).contains("a remainder is taken of integers"), "`%` by a real")
    assert(said(() -> whole(5.5, 2)).contains("an integer division is of integers"), "`\\` of a real")
    assertEq(remainder(7, 2), 1)

@test
A_REAL_BESIDE_SOMETHING_THAT_IS_NOT_A_NUMBER_IS_STILL_REFUSED()
    assert(said(() -> times(1.5, {})) != "", "a real times an object was allowed")
    assert(said(() -> below(1.5, {})) != "", "a real compared with an object was allowed")

// -- the fused forms: a product summed, and a sum or difference stored ----------------------------

@test
A_REAL_LOOP_ANSWERS_WHAT_THE_SAME_ARITHMETIC_ANSWERS_UNFUSED()
    var total = 0.0
    var i = 0

    while i < 10
        total = total + i * 1.5 - 0.5
        i = i + 1

    assertEq(string(total), "62.5")
    assert(total is real, "the total is a real")

@test
A_PRODUCT_SUMMED_PROMOTES_WHEREVER_THE_REAL_IS()
    val three = 3
    val half = 0.5
    var a = 1
    var b = 1.0
    var c = 1
    var d = 1.0

    a = a + three * half
    b = b + three * 2
    c = c + half * three
    d = d + half * half

    assertEq(string(a), "2.5")
    assertEq(string(b), "7")
    assert(b is real, "a real plus a whole product is a real")
    assertEq(string(c), "2.5")
    assertEq(string(d), "1.25")

@test
A_PRODUCT_THAT_GROWS_BESIDE_A_REAL_TAKES_THE_GENERAL_PATH()
    val big = 4611686018427387904
    var t = 0.5
    val p = big * 4

    t = t + big * 4
    assertEq(t, 0.5 + p)
    assert(t is real, "a real plus a grown product is a real")

@test
A_REAL_SUM_OR_DIFFERENCE_IS_STORED_INTO_A_LOCAL()
    var r = 1.0
    var n = 1

    r = r + 0.25
    r = r - 0.5
    n = n + 0.5
    assertEq(string(r), "0.75")
    assertEq(string(n), "1.5")
    assert(n is real, "an integer local that took a real sum holds a real")

    n = n - 1
    assertEq(string(n), "0.5")
    r += 2
    r -= 0.75
    assertEq(string(r), "2")
    assert(r is real, "a compound assignment of a real keeps a real")
