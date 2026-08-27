// A module with tests beside the code, which is what `@test` in the same file is for: the tests can
// reach what the file did not export.

val factor = 3

export triple(x) = x * factor

@test
it_multiplies_by_the_factor() =
    assertEq(triple(2), 6)

@test
a_test_beside_the_code_reaches_what_is_private_to_it() =
    assertEq(factor, 3)
