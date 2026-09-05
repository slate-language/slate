// A file with one of each verdict, which is what the runner has to be able to report.
//
// **The skip is written as a program would write one** — a question about the host, asked once, with
// the reason beside it — rather than as an unconditional `skip`, so that this reads as the thing it
// is for.
val hasWings = false

@test
a_test_that_holds() =
    assertEq(6 * 7, 42)

@test
a_test_that_is_not_for_this_host() =
    if !hasWings then skip("this host has no wings")

    assertEq(1, 2)

@test
async an_async_test_that_is_not_for_this_host_either() =
    await sleep(0)

    if !hasWings then skip("still no wings, one turn later")

    assertEq(1, 2)

@test
a_skip_is_not_something_a_catch_can_swallow() =
    val caught = try
        skip("a library cannot take this decision away")
        "swallowed"
    catch e
        "swallowed"

    assertEq(caught, "unreachable")
