// Numbers: two kinds, and the arithmetic that keeps them apart.

@test
an_integer_is_sixty_four_bits_wide_and_wraps() =
    assertEq(9223372036854775807 + 1, -9223372036854775808)
    assertEq(-9223372036854775808 - 1, 9223372036854775807)

@test
integer_division_truncates_towards_zero() =
    assertEq(7 / 2, 3)
    assertEq(-7 / 2, -3)
    assertEq(7 % 3, 1)
    assertEq(-7 % 3, -1)

@test
a_real_is_a_different_kind_from_an_integer() =
    assertEq(7.0 / 2, 3.5)
    assertEq(1 + 1.5, 2.5)
    assert(1 is integer)
    assert(1.0 is real)
    assert(!(1 is real))

@test
the_two_kinds_are_equal_when_they_stand_for_the_same_number() =
    assert(1 == 1.0)
    assert(!(1 == 1.5))

@test
shifting_is_to_sixty_three_places() =
    assertEq(1 << 3, 8)
    assertEq(-8 >> 1, -4)
    assertEq(1 << 63, -9223372036854775808)

@test
the_bitwise_operators() =
    assertEq(6 & 3, 2)
    assertEq(6 | 3, 7)
    assertEq(6 ^ 3, 5)
    assertEq(~0, -1)

@test
conversions_between_the_kinds() =
    assertEq(integer(3.9), 3)
    assertEq(integer(-3.9), -3)
    assertEq(real(3), 3.0)
    assertEq(number("42"), 42)
    assertEq(number("4.5"), 4.5)
    assertEq(number("nonsense"), null)

@test
number_OF_A_TEXT_DENOTING_NEGATIVE_ZERO_KEEPS_THE_SIGN_THE_WAY_JAVASCRIPT_DOES() =
    // A plain integer literal cannot carry the sign of zero -- `-0` and `0` are one `long` -- so
    // `number("-0")` answers the real `-0` rather than the integer `0`, exactly as JavaScript's
    // `Number("-0")` is `-0` rather than `0`. `0 == -0.0`, so the sign has to be read off which way
    // `1.0` divides rather than off `==`.
    assert(number("-0") is real)
    assert(number("0") is integer)
    assertEq(string(1.0 / number("-0")), "-inf")
    assertEq(string(1.0 / number("0")), "inf")

    // The neighbours: any run of zero digits after the sign, and a `+` that leaves zero positive
    // exactly as a bare `0` does.
    assertEq(string(1.0 / number("-00")), "-inf")
    assertEq(string(1.0 / number("-0.0")), "-inf")
    assertEq(string(1.0 / number("+0")), "inf")

    // Leading whitespace already went through `strtod`, which reads the sign correctly by itself --
    // this is not new here, only checked, since it shares `number`'s path with the fix above.
    assertEq(string(1.0 / number(" -0")), "-inf")

@test
rounding_and_magnitude() =
    assertEq(floor(3.7), 3.0)
    assertEq(ceil(3.2), 4.0)
    assertEq(abs(-4), 4)
    assertEq(abs(-4.5), 4.5)
    assertEq(min(3, 1, 2), 1)
    assertEq(max(3, 1, 2), 3)

@test
a_number_says_what_it_is_when_printed() =
    assertEq(string(1), "1")
    assertEq(string(-0.5), "-0.5")
    assertEq(string(1000000), "1000000")
    assertEq(string(1e21), "1e+21")

    // A real whose value is whole prints as a whole number, so the rendering does not say which of
    // the two kinds it was -- `1.0 is real` is the question that does.
    assertEq(string(1.0), "1")

    // The shortest text that reads back as the same double, which is why this is not 0.30000000000000004.
    assertEq(string(0.1 + 0.2), "0.3")

@test
a_draw_is_a_real_between_zero_and_one() =
    val r = random()

    assert(r is real)
    assert(r >= 0)
    assert(r < 1)

    // A hundred draws, every one of them in range: a generator whose top bit leaked, or one dividing
    // by 2^53 - 1, would be found here rather than by the single draw above.
    var i = 0

    while i < 100
        val x = random()

        assert(x >= 0 && x < 1)
        i += 1

@test
two_draws_are_not_the_same_number() =
    // **A handful rather than a pair**, and the pin is that all eight differ: a generator that never
    // advanced would answer one number eight times, and 53-bit draws collide about once in 2^48
    // runs of this, which is far enough from flaky.
    var seen = []
    var i = 0

    while i < 8
        seen.push(random())
        i += 1

    assert(unique(seen).length == 8)

@test
dividing_an_integer_by_zero_is_a_fault_rather_than_an_answer() =
    assert((1 / 0) catch e -> true)
    assert((1 % 0) catch e -> true)

@test
toFixed_WRITES_THE_GIVEN_NUMBER_OF_DECIMAL_PLACES() =
    assertEq(toFixed(9, 2), "9.00")
    assertEq(toFixed(1.005, 2), "1.00")

    // A tie rounds AWAY from zero, which is JavaScript's rule and not C's `printf`'s.
    assertEq(toFixed(2.5, 0), "3")
    assertEq(toFixed(0.125, 2), "0.13")

    // The sign is taken off first, so a negative rounding to nothing still reads negative.
    assertEq(toFixed(-0.4, 0), "-0")

@test
toFixed_PAST_1e21_ANSWERS_WHAT_STRING_WOULD_RATHER_THAN_REFUSING() =
    // JavaScript's own `toFixed` never refuses on the number's magnitude: past `1e21` it gives up
    // on decimal places and answers what `String(x)` would -- an exponent -- rather than throwing.
    assertEq(toFixed(1e21, 2), "1e+21")
    assertEq(toFixed(-1e21, 2), "-1e+21")
    assertEq(toFixed(1.5e21, 5), "1.5e+21")
    assertEq(toFixed(2e25, 0), "2e+25")

@test
toFixed_OF_NAN_AND_INFINITY_ANSWERS_THEIR_NAMES() =
    // Also never a fault in JavaScript: `NaN.toFixed(2)` is `"NaN"` and `Infinity.toFixed(2)` is
    // `"Infinity"`, spelled out in full rather than in `string`'s own `nan`/`inf`.
    assertEq(toFixed(0.0 / 0.0, 2), "NaN")
    assertEq(toFixed(1.0 / 0.0, 2), "Infinity")
    assertEq(toFixed(-1.0 / 0.0, 2), "-Infinity")

@test
toFixed_REFUSES_A_PLACE_COUNT_OUTSIDE_ZERO_TO_A_HUNDRED() =
    // JavaScript throws a `RangeError` for a digit count outside `0..100`, and this is the one
    // refusal `toFixed` keeps -- the number itself is never the reason to refuse.
    assert((toFixed(1, -1) catch e -> e.message).contains("0 to 100 places"))
    assert((toFixed(1, 101) catch e -> e.message).contains("0 to 100 places"))
