// Numbers: two kinds, and the arithmetic that keeps them apart.

@test
an_integer_never_wraps_it_grows() =
    assertEq(9223372036854775807 + 1, 9223372036854775808)
    assertEq(-9223372036854775808 - 1, -9223372036854775809)
    assertEq(4611686018427387904 * 2, 9223372036854775808)
    assertEq(string(9223372036854775807 + 1), "9223372036854775808")

@test
the_one_division_that_grows_is_the_most_negative_over_minus_one() =
    val least = -9223372036854775808

    assertEq(least / -1, 9223372036854775808)
    assertEq(least % -1, 0)
    assertEq(-least, 9223372036854775808)
    assertEq(abs(least), 9223372036854775808)

@test
a_number_that_grew_and_came_back_is_the_number_it_came_back_as() =
    // The normalization rule, which is what keeps `==` and hashing free of a width case.
    assertEq((1 << 100) - (1 << 100) + 5, 5)
    assert((1 << 100) - (1 << 100) + 5 is integer)

    val m = Map()

    m.set(5, "five")
    assertEq(m.get((1 << 100) - (1 << 100) + 5), "five")

@test
a_wide_integer_is_still_an_integer() =
    assert(pow(2, 100) is integer)
    assert(pow(2, 100) is number)
    assert(!(pow(2, 100) is real))

@test
a_wide_integer_and_a_real_compare_exactly_and_arithmetic_promotes() =
    // `1e30` is not the number `10 ^ 30`; it is `1000000000000000019884624838656`.
    assert(!(pow(10, 30) == 1e30))
    assert(pow(10, 30) < 1e30)
    assert(pow(10, 30) + 1 < 1e30)
    assertEq(integer(1e30), 1000000000000000019884624838656)
    assert(pow(10, 30) + 0.5 is real)

@test
a_wide_integer_is_written_and_read_as_its_digits() =
    assertEq(string(pow(2, 100)), "1267650600228229401496703205376")
    assertEq(number("1267650600228229401496703205376"), pow(2, 100))
    assertEq(0xffffffffffffffffffff, 1208925819614629174706175)
    assertEq(1_000_000_000_000_000_000_000_000, 1000000000000000000000000)

@test
a_wide_integer_goes_through_json_as_its_digits() =
    // JSON's grammar bounds a number at nothing, so the digits are the encoding: nothing is
    // rounded on the way out and nothing is lost on the way back.
    assertEq(toJSON(pow(10, 30)), "1000000000000000000000000000000")
    assertEq(toJSON(-pow(10, 30)), "-1000000000000000000000000000000")
    assertEq(parseJSON("1000000000000000000000000000000").value, pow(10, 30))
    assertEq(parseJSON(toJSON(pow(2, 100))).value, pow(2, 100))

    // 2^63 is the first whole number past a 64-bit integer, and it survives exactly.
    assertEq(toJSON(9223372036854775808), "9223372036854775808")
    assertEq(parseJSON("9223372036854775808").value, 9223372036854775808)

@test
a_number_json_can_hold_in_64_bits_comes_back_as_an_ordinary_integer() =
    // The reader normalizes, so a value the digits do hold is the value the literal is -- equal to
    // it, and the same key in a table.
    val back = parseJSON("9223372036854775807").value

    assertEq(back, 9223372036854775807)

    val m = Map()

    m.set(9223372036854775807, "most")
    assertEq(m.get(back), "most")

@test
a_document_keeps_its_wide_integers_and_its_reals_apart() =
    val doc = { id: pow(10, 30), items: [1, pow(2, 64)], scale: 1e30 }
    val back = parseJSON(toJSON(doc)).value

    assertEq(back.id, pow(10, 30))
    assert(back.id is integer)
    assertEq(back.items[1], pow(2, 64))

    // `1e30` is a real and stays one, an exponent being what says so however large the number is.
    assert(back.scale is real)
    assertEq(back.scale, 1e30)

@test
a_factorial_is_the_number_and_not_a_remainder_of_it() =
    var f = 1

    for i in 1..30
        f = f * i

    assertEq(string(f), "265252859812191058636308480000000")

@test
a_wide_literal_in_a_pattern_matches_the_number_it_spells() =
    val said = pow(10, 30) match
        1000000000000000000000000000000 -> "yes"
        _ -> "no"

    assertEq(said, "yes")

    val least = -9223372036854775808 match
        -9223372036854775808 -> "yes"
        _ -> "no"

    assertEq(least, "yes")

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
a_real_literal_rounds_to_the_nearest_double_however_many_digits_it_has() =
    // A real literal used to be refused as "too large to hold" past twenty digits of fraction, the
    // lexer having built the fraction into a 64-bit integer on the way to finding where it ends. It
    // has to round to the nearest double whatever its length, exactly as node's reader does for the
    // same text -- which is what makes this a differential test rather than one pinned by hand.
    assertEq(0.123456789012345678901, 0.12345678901234568)
    assertEq(0.1234567890123456789012345678901234567890, 0.12345678901234568)
    assertEq(99999999999999999999.5, 100000000000000000000.0)

@test
shifting_left_grows_and_shifting_right_drags_the_sign_down() =
    assertEq(1 << 3, 8)
    assertEq(-8 >> 1, -4)
    assertEq(1 << 63, 9223372036854775808)
    assertEq(1 << 100, 1267650600228229401496703205376)
    assertEq((1 << 100) >> 99, 2)

    // No width, so a shift past one is not a mistake: it floors toward negative infinity.
    assertEq(7 >> 200, 0)
    assertEq(-1 >> 200, -1)

@test
the_bitwise_operators_read_an_endless_twos_complement() =
    assertEq(6 & 3, 2)
    assertEq(6 | 3, 7)
    assertEq(6 ^ 3, 5)
    assertEq(~0, -1)

    // Python's reading, which is the only one that is total: `~x` is `-x - 1` at every width.
    assertEq(~5, -6)
    assertEq(-6 & 3, 2)
    assertEq(-6 | 3, -5)
    assertEq(-6 ^ 3, -7)
    assertEq((1 << 100) | 1, 1267650600228229401496703205377)
    assertEq(~(1 << 100), -1267650600228229401496703205377)

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
    assertEq(string(1.0 / number("-0")), "-Infinity")
    assertEq(string(1.0 / number("0")), "Infinity")

    // The neighbours: any run of zero digits after the sign, and a `+` that leaves zero positive
    // exactly as a bare `0` does.
    assertEq(string(1.0 / number("-00")), "-Infinity")
    assertEq(string(1.0 / number("-0.0")), "-Infinity")
    assertEq(string(1.0 / number("+0")), "Infinity")

    // Leading whitespace already went through `strtod`, which reads the sign correctly by itself --
    // this is not new here, only checked, since it shares `number`'s path with the fix above.
    assertEq(string(1.0 / number(" -0")), "-Infinity")

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
    assertEq(string(2.0), "2")
    assertEq(string(-2.0), "-2")
    assertEq(string(100.0), "100")

@test
a_real_prints_the_shortest_text_that_reads_back_as_the_same_double() =
    // **`0.1 + 0.2` IS NOT `0.3`, AND THE TEXT SAYS SO.** Six significant figures said it was, which
    // left a program unable to see the value it was holding and two different reals printing alike.
    assertEq(string(0.1 + 0.2), "0.30000000000000004")
    assertEq(string(1 / 3.0), "0.3333333333333333")
    assertEq(string(123456789.123), "123456789.123")

    // Seventeen figures where sixteen would name a different double, and one where the value's own
    // expansion has hundreds.
    assertEq(string(1.7976931348623157e308), "1.7976931348623157e+308")
    assertEq(string(5e-324), "5e-324")

@test
the_plain_band_ends_at_1e21_and_1e_minus_7_as_it_does_in_javascript() =
    assertEq(string(1e20), "100000000000000000000")
    assertEq(string(1e21), "1e+21")
    assertEq(string(1.5e21), "1.5e+21")
    assertEq(string(1e-6), "0.000001")
    assertEq(string(1e-7), "1e-7")

    // No zero padding the exponent out to two digits, which is where C's `%g` and JavaScript part.
    assertEq(string(1e100), "1e+100")

@test
not_a_number_and_the_infinities_are_spelled_as_javascript_spells_them() =
    assertEq(string(0.0 / 0.0), "NaN")
    assertEq(string(1.0 / 0.0), "Infinity")
    assertEq(string(-1.0 / 0.0), "-Infinity")

    // A negative zero keeps its sign, which is the one place this rule does not follow the host:
    // `String(-0)` is `"0"` in JavaScript, hiding the thing a reader printing a zero is asking.
    assertEq(string(0.0), "0")
    assertEq(string(-0.0), "-0")

@test
the_text_a_real_prints_reads_back_as_the_same_real() =
    // The property the whole rule exists for, and the one a fixed number of figures cannot have.
    for x in [0.1 + 0.2, 1 / 3.0, 1e21, 1e-7, 1e20, 123456789.123, 1.7976931348623157e308, 5e-324,
            2.0, -0.5, 0.000001]
        assertEq(number(string(x)), x)

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
    // `"Infinity"`, which is what `string` spells them as well.
    assertEq(toFixed(0.0 / 0.0, 2), "NaN")
    assertEq(toFixed(1.0 / 0.0, 2), "Infinity")
    assertEq(toFixed(-1.0 / 0.0, 2), "-Infinity")

@test
toFixed_REFUSES_A_PLACE_COUNT_OUTSIDE_ZERO_TO_A_HUNDRED() =
    // JavaScript throws a `RangeError` for a digit count outside `0..100`, and this is the one
    // refusal `toFixed` keeps -- the number itself is never the reason to refuse.
    assert((toFixed(1, -1) catch e -> e.message).contains("0 to 100 places"))
    assert((toFixed(1, 101) catch e -> e.message).contains("0 to 100 places"))

// The trigonometric, hyperbolic and logarithmic functions, and the two constants. Every assertion
// here is a boolean or an exact integer rather than a printed real, so a last-bit difference between
// the interpreter's `libm` and node's `Math` -- which neither back end promises never to have --
// cannot turn a passing run red on one of them and not the other.
@test
PI_AND_E_ARE_THE_TWO_CONSTANTS() =
    assert(PI > 3.14159 && PI < 3.14160)
    assert(E > 2.71828 && E < 2.71829)

@test
the_trigonometric_functions_agree_with_their_inverses_at_the_easy_points() =
    assertEq(sin(0), 0.0)
    assertEq(cos(0), 1.0)
    assertEq(tan(0), 0.0)
    assertEq(asin(0), 0.0)
    assertEq(acos(1), 0.0)
    assertEq(atan(0), 0.0)

    assert((sin(PI / 2) - 1).abs() < 1e-12)
    assert((asin(1) - PI / 2).abs() < 1e-12)
    assert((acos(0) - PI / 2).abs() < 1e-12)
    assert((atan(1) - PI / 4).abs() < 1e-12)

@test
atan2_KEEPS_JAVASCRIPTS_OWN_ARGUMENT_ORDER_Y_THEN_X() =
    assert((atan2(1, 1) - PI / 4).abs() < 1e-12)
    assert((atan2(1, 0) - PI / 2).abs() < 1e-12)
    assert((atan2(0, -1) - PI).abs() < 1e-12)

@test
the_hyperbolic_functions_at_zero() =
    assertEq(sinh(0), 0.0)
    assertEq(cosh(0), 1.0)
    assertEq(tanh(0), 0.0)

@test
log_log2_log10_and_exp_are_the_inverses_of_each_other() =
    assertEq(log(1), 0.0)
    assertEq(log2(8), 3.0)
    assertEq(log10(1000), 3.0)
    assertEq(exp(0), 1.0)
    assert((log(E) - 1).abs() < 1e-12)

@test
log_OF_A_NON_POSITIVE_NUMBER_ANSWERS_NAN_OR_MINUS_INFINITY_RATHER_THAN_FAULTING() =
    // Exactly what JavaScript's `Math.log` answers, on both back ends: a domain error here is not a
    // fault, unlike `sqrt`'s.
    assertEq(string(log(0)), "-Infinity")
    assert(log(-1) != log(-1))

@test
cbrt_ANSWERS_THE_REAL_CUBE_ROOT_INCLUDING_OF_A_NEGATIVE_NUMBER() =
    // Compared within a tolerance rather than for equality: glibc's cbrt and macOS's disagree in the
    // last bit for these inputs, so an exact assertion is a test of which libm the machine has.
    assert((cbrt(27) - 3.0).abs() < 1e-12)
    assert((cbrt(-27) - (-3.0)).abs() < 1e-12)

@test
hypot_IS_THE_LENGTH_OF_THE_HYPOTENUSE() =
    assertEq(hypot(3, 4), 5.0)
    assertEq(hypot(0, 0), 0.0)

@test
a_number_answers_the_single_argument_ones_as_methods_too() =
    // `sqrt`'s own precedent: a free function of one number is that number's method as well.
    assert(((PI / 2).sin() - 1).abs() < 1e-12)
    assertEq((0).cos(), 1.0)
    assert(((27).cbrt() - 3.0).abs() < 1e-12)
    assert(((1.0).log() - 0).abs() < 1e-12)

@test
the_new_math_functions_take_the_numbers_they_say_and_drop_the_rest() =
    // **A count a builtin is given is a FLOOR**, which is the call rule read at a native: a surplus
    // argument is dropped here exactly as it is at a function the program wrote.
    assert(sin(1, 2) == sin(1))
    assert(hypot(1, 2, 3) == hypot(1, 2))

    // What each one still says is what it WANTS, whether that is a count it did not reach or an
    // argument of the wrong kind.
    assert((sin() catch e -> e.message).contains("`sin` takes one number, and was given 0 arguments"))
    assert((sin("x") catch e -> e.message).contains("`sin` takes a number, and this is a string"))
    assert((atan2(1) catch e -> e.message).contains("`atan2` takes two numbers, and was given 1 argument"))

@test
a_binary_operator_left_dangling_at_the_end_of_a_line_continues_the_statement() =
    // Nothing but blanks or a comment stands between the operator and the newline, so the statement
    // is not finished -- at whatever column the next line happens to sit at, brackets or none.
    val sum = 1 +
        2 +
        3

    assertEq(sum, 6)

    val cmp = 1 < 2 ||
        3 < 4

    assert(cmp)
