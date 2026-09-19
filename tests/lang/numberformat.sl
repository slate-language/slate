// `toExponential` and `toPrecision`, on both back ends.
//
// **The digits are JavaScript's, ties included**, so every expectation here was taken from node
// rather than worked out by hand -- which is the only way to write a test of this kind, the cases
// that matter being the ones where a value that reads as a tie is not one. `1.25` at one digit
// really is halfway and rounds away from zero; `1.35` and `1.45` are not, the doubles nearest them
// lying just above and just below, and each rounds the way its own value says.
//
// The interpreter's own refusals and `toFixed`'s neighbours are in `dev/slatelang/slate/
// tests_builtins.sysl`; what is here is what a slate program can see, on every back end there is.

@test
toExponential_WITH_NO_COUNT_WRITES_THE_DIGITS_THE_VALUE_NEEDS() =
    assertEq(toExponential(0.1), "1e-1")
    assertEq(toExponential(123456), "1.23456e+5")
    assertEq(toExponential(1.5e21), "1.5e+21")
    assertEq(toExponential(5e-324), "5e-324")
    assertEq(toExponential(1.7976931348623157e308), "1.7976931348623157e+308")

    // A whole number's trailing zeros are not digits it needs.
    assertEq(toExponential(100), "1e+2")
    assertEq(toExponential(120), "1.2e+2")

@test
toExponential_OF_ZERO_IS_0e_PLUS_0_AND_A_NEGATIVE_ZERO_KEEPS_NO_SIGN() =
    // JavaScript's own drops the sign here, the sign being taken off before anything is written and
    // negative zero not being less than zero. `string(-0)` is `-0` in slate and stays that way.
    assertEq(toExponential(0), "0e+0")
    assertEq(toExponential(0.0), "0e+0")
    assertEq(toExponential(0.0 * -1.0), "0e+0")
    assertEq(toExponential(0, 3), "0.000e+0")

@test
toExponential_WITH_A_COUNT_WRITES_EXACTLY_THAT_MANY_AFTER_THE_POINT() =
    assertEq(toExponential(255, 2), "2.55e+2")
    assertEq(toExponential(0.5, 0), "5e-1")
    assertEq(toExponential(-1.5, 3), "-1.500e+0")
    assertEq(toExponential(5e-324, 3), "4.941e-324")

    // Rounding up carries past the last place, and the exponent moves with it.
    assertEq(toExponential(9.99, 1), "1.0e+1")

@test
toExponential_ROUNDS_A_TIE_AWAY_FROM_ZERO_ON_THE_VALUE_THE_DOUBLE_HOLDS() =
    // `1.25` is exactly halfway and goes up; `1.35` is a shade above halfway and `1.45` a shade
    // below, so neither is a tie at all and each goes the way its own value points.
    assertEq(toExponential(1.25, 1), "1.3e+0")
    assertEq(toExponential(1.35, 1), "1.4e+0")
    assertEq(toExponential(1.45, 1), "1.4e+0")

@test
toExponential_KEEPS_EVERY_DIGIT_OF_A_WHOLE_NUMBER() =
    // slate's integer is 64 bits and is not measured through a double, so a value past `2^53` names
    // itself. This is `toFixed`'s rule and the reason an integer takes its own path on both ends.
    assertEq(toExponential(9007199254740993), "9.007199254740993e+15")
    assertEq(toExponential(-9007199254740993, 16), "-9.0071992547409930e+15")

@test
toPrecision_WITH_NO_COUNT_IS_WHAT_string_ANSWERS() =
    assertEq(toPrecision(1.5), string(1.5))
    assertEq(toPrecision(1e21), string(1e21))
    assertEq(toPrecision(123456), string(123456))
    assertEq(toPrecision(0.0000001), "1e-7")

@test
toPrecision_WRITES_THAT_MANY_SIGNIFICANT_DIGITS() =
    assertEq(toPrecision(123.456, 4), "123.5")
    assertEq(toPrecision(2.5, 1), "3")
    assertEq(toPrecision(1.005, 3), "1.00")
    assertEq(toPrecision(1.45, 2), "1.4")
    assertEq(toPrecision(0, 3), "0.00")
    assertEq(toPrecision(0, 1), "0")

    // A carry past the last place moves the exponent, which here changes the layout with it.
    assertEq(toPrecision(9.99, 2), "10")

@test
toPrecision_CHOOSES_ITS_LAYOUT_BY_THE_EXPONENT_AND_NOT_BY_THE_MAGNITUDE() =
    // Plain while the exponent is in `-6 <= e < p`, exponential outside it -- a narrower band than
    // `string`'s, which is why `123456` comes out as an exponent here and plainly there.
    assertEq(toPrecision(0.000123, 2), "0.00012")
    assertEq(toPrecision(-0.000123, 2), "-0.00012")
    assertEq(toPrecision(0.000000123, 2), "1.2e-7")
    assertEq(toPrecision(123456, 2), "1.2e+5")
    assertEq(toPrecision(1e21, 3), "1.00e+21")

@test
BOTH_OF_THEM_ANSWER_THE_NAMES_OF_NAN_AND_INFINITY() =
    // Never a fault on the number itself, which is `toFixed`'s rule here too.
    assertEq(toExponential(0.0 / 0.0, 2), "NaN")
    assertEq(toExponential(1.0 / 0.0, 2), "Infinity")
    assertEq(toExponential(-1.0 / 0.0, 2), "-Infinity")
    assertEq(toPrecision(0.0 / 0.0, 2), "NaN")
    assertEq(toPrecision(1.0 / 0.0, 2), "Infinity")
    assertEq(toPrecision(-1.0 / 0.0, 2), "-Infinity")

@test
BOTH_OF_THEM_ARE_METHODS_ON_A_NUMBER_TOO() =
    assertEq((255).toExponential(2), "2.55e+2")
    assertEq((0.1).toExponential(), "1e-1")
    assertEq((123.456).toPrecision(4), "123.5")
    assertEq((1.5).toPrecision(), "1.5")

@test
toExponential_REFUSES_A_DIGIT_COUNT_OUTSIDE_ZERO_TO_A_HUNDRED() =
    // JavaScript throws a `RangeError` for a count outside its range, and this is the one thing
    // either of these refuses -- the number itself is never the reason.
    assert((toExponential(1, -1) catch e -> e.message).contains("0 to 100 digits"))
    assert((toExponential(1, 101) catch e -> e.message).contains("0 to 100 digits"))

@test
toPrecision_REFUSES_A_DIGIT_COUNT_OUTSIDE_ONE_TO_A_HUNDRED() =
    // One significant digit is the fewest that says anything, so the range starts at one rather
    // than at nought -- which is the only way its range differs from `toExponential`'s.
    assert((toPrecision(1, 0) catch e -> e.message).contains("1 to 100 significant digits"))
    assert((toPrecision(1, 101) catch e -> e.message).contains("1 to 100 significant digits"))
