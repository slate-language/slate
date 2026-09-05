// A file whose test passes and whose `@teardown` does not.
//
// **A passing test with a broken teardown is not a passing file**, so the teardown's fault is a
// failure of its own on the last line rather than something folded into the test or swallowed.
@teardown
shut_the_thing() =
    throw "the thing would not shut"

@test
one_that_passes() =
    assertEq(6 * 7, 42)
