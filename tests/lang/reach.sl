// What a default may read: the bindings to its LEFT, a global, and the names a lambda inside it binds
// for itself. A read of its own name or of one to its right is refused before the program runs, on
// both back ends, so what is left to pin here is that everything legal answers the same on both.

val base = 10

t(v) = v

early(a = 1, b = a + 1) = [a, b]

reaches(x, y = x + 1, z = base, w = ((b) -> b)(5), b = 2) = [x, y, z, w, b]

@test
a_default_reads_the_parameter_to_its_left() =
    assertEq(early(), [1, 2])
    assertEq(early(4), [4, 5])

@test
a_named_call_that_skips_a_default_still_works_it_out_from_the_left() =
    // The shape the refused `early(a = t(b), b = 2)` had, written the legal way round.
    assertEq(early(b = 3), [1, 3])
    assertEq(early(a = 4), [4, 5])

@test
a_default_reads_a_global_and_a_lambda_binds_its_own_names() =
    assertEq(reaches(1), [1, 2, 10, 5, 2])
    assertEq(reaches(1, b = 9), [1, 2, 10, 5, 9])

@test
a_pattern_default_reads_the_names_to_its_left() =
    val { a = 1, b = a + 1 } = {}
    val { c, d = c * 2 } = { c: 5 }
    val [e = 3, f = e + t(1)] = []

    assertEq([a, b, c, d, e, f], [1, 2, 5, 10, 3, 4])
