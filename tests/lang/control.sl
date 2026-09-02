// Control flow, closures, generators, faults and `async`.

@test
every_loop_is_an_expression_and_break_gives_it_a_value() =
    var i = 0
    val found = loop
        i = i + 1

        if i == 3 then break i

    assertEq(found, 3)

@test
a_loop_that_finishes_on_its_own_takes_its_else() =
    val answer = for x in [1, 2, 3]
        if x > 5 then break "big"
    else
        "none were big"

    assertEq(answer, "none were big")

@test
a_for_walks_an_array_a_range_and_an_objects_entries() =
    var seen = []

    for x in [1, 2]
        push(seen, x)

    for i in 0..<2
        push(seen, i)

    for [k, v] in entries({ a: 1 })
        push(seen, k)
        push(seen, v)

    assertEq(seen, [1, 2, 0, 1, "a", 1])

@test
a_while_runs_while_its_condition_holds() =
    var n = 0

    while n < 3
        n = n + 1

    assertEq(n, 3)

@test
continue_skips_the_rest_of_the_turn() =
    var seen = []

    for x in [1, 2, 3, 4]
        if x % 2 == 0 then continue

        push(seen, x)

    assertEq(seen, [1, 3])

@test
an_if_is_an_expression() =
    assertEq(if true then 1 else 2, 1)
    assertEq(if false then 1 else 2, 2)

@test
only_null_undefined_and_false_are_falsy() =
    assert(boolean(0))
    assert(boolean(""))
    assert(boolean([]))
    assert(!boolean(null))
    assert(!boolean(false))

@test
a_closure_keeps_the_scope_that_made_it() =
    counter() =
        var n = 0

        () ->
            n = n + 1

            n

    val next = counter()

    assertEq(next(), 1)
    assertEq(next(), 2)
    assertEq(counter()(), 1)

@test
a_fault_is_caught_and_carries_a_message_and_a_line() =
    val e = (1 / 0) catch e -> e

    assert(contains(e.message, "zero"))
    assert(e.line is integer)
    assert(e.file is string)

@test
a_throw_carries_a_value_of_the_programs_own() =
    val said = raiser("gone wrong") catch e -> e.message

    assertEq(said, "gone wrong")

raiser(m) =
    throw m

@test
a_caught_fault_put_back_keeps_its_own_words() =
    val said = again() catch e -> e.message

    assert(contains(said, "zero"))

again() =
    try
        1 / 0
    catch e
        throw e

@test
a_try_answers_its_body_where_nothing_went_wrong() =
    val v = try
        41 + 1
    catch e
        0

    assertEq(v, 42)

@test
a_generator_is_a_function_that_holds_a_yield() =
    upTo(n) =
        var i = 0

        while i < n
            yield i

            i = i + 1

    var seen = []

    for x in upTo(3)
        push(seen, x)

    assertEq(seen, [0, 1, 2])

@test
a_generator_may_be_stepped_by_hand() =
    two() =
        yield "a"
        yield "b"

    val g = two()

    assertEq(next(g).value, "a")
    assertEq(next(g).value, "b")
    assert(next(g).done)

@test
async an_async_function_answers_a_promise() =
    later() =
        41

    val p = resolve(41)

    assert(p is promise)
    assertEq(await p + 1, 42)

@test
async a_rejected_promise_is_caught_as_a_fault() =
    val said = (await reject("no")) catch e -> e.message

    assertEq(said, "no")

@test
async a_promise_may_be_settled_from_outside() =
    val p = pending()

    settle(p, 42)

    assertEq(await p, 42)

@test
async awaiting_something_that_is_not_a_promise_answers_it() =
    assertEq(await 7, 7)
