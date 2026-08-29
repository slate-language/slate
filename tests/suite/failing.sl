@test
one_that_passes() = assert(true)

@test
an_assertion_that_does_not_hold() =
    assertEq(triple_trouble(), 7)

triple_trouble() = 6

@test
a_fault_rather_than_an_assertion() =
    val v = 1 / 0
    assert(true)

@test
one_that_prints_before_it_fails() =
    print("context the reader wants")
    assert(false, "meant to fail")

@test
async an_async_one_that_fails() =
    await sleep(1)
    assertEq(1, 2)
