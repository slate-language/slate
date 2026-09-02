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
dividing_an_integer_by_zero_is_a_fault_rather_than_an_answer() =
    assert((1 / 0) catch e -> true)
    assert((1 % 0) catch e -> true)
