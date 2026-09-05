// A file the host is not for, said once rather than in every test.
//
// **`skip` in a `@setupAll` leaves out every test in the file**, which is what a suite needs where
// one host has something another has not: the question is asked once and the reason is the same.
val hasWings = false

@setupAll
check_the_host() =
    if !hasWings then skip("this host has no wings")

@test
one_that_is_left_out() =
    assert(false, "a test the host was not prepared for must not be reached")

@test
another_that_is_left_out() =
    assert(false, "nor this one")
