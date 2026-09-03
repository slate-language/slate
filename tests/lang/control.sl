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

@test
async a_timer_resumes_the_program_later() =
    var seen = []

    setTimeout(() -> push(seen, "timer"), 10)
    push(seen, "now")

    await sleep(20)

    assertEq(seen, ["now", "timer"])

@test
async timers_fire_in_the_order_they_come_due() =
    var seen = []

    setTimeout(() -> push(seen, "c"), 30)
    setTimeout(() -> push(seen, "a"), 10)
    setTimeout(() -> push(seen, "b"), 20)

    await sleep(50)

    assertEq(seen, ["a", "b", "c"])

@test
async two_timers_due_at_once_fire_in_the_order_they_were_set() =
    var seen = []

    setTimeout(() -> push(seen, "first"), 10)
    setTimeout(() -> push(seen, "second"), 10)

    await sleep(20)

    assertEq(seen, ["first", "second"])

@test
async a_cancelled_timer_never_fires() =
    var seen = []
    val id = setTimeout(() -> push(seen, "no"), 10)

    clearTimeout(id)

    await sleep(20)

    assertEq(seen, [])

@test
async an_interval_repeats_until_it_is_cancelled() =
    var n = 0
    var id = null

    tick()
        n = n + 1

        if n == 3 then clearInterval(id)

    id = setInterval(tick, 10)

    await sleep(60)

    assertEq(n, 3)

@test
async a_promise_settles_before_a_timer_that_is_already_due() =
    // A continuation is a microtask and a timer is a macrotask, so everything already resolved runs
    // before the loop takes its next turn. Both back ends have to agree about that ordering.
    var seen = []

    setTimeout(() -> push(seen, "timer"), 0)

    await resolve(0)

    push(seen, "promise")

    await sleep(10)

    assertEq(seen, ["promise", "timer"])

@test
async a_for_await_walks_a_generator_because_await_of_a_plain_value_answers_it() =
    // The one rule covering both kinds of source: a generator's `next()` answers `{value, done}`
    // outright, and awaiting something that is not a promise answers it and yields.
    twoOf()
        yield 1
        yield 2

    var seen = []

    for await x in twoOf()
        push(seen, x)

    assertEq(seen, [1, 2])

@test
async a_for_await_walks_a_source_whose_next_answers_a_promise() =
    counted(n)
        var i = 0
        val it = {}

        it.next = async () ->
            await sleep(1)

            if i >= n then { done: true, value: null }
            else
                i += 1
                { done: false, value: i * 10 }

        it

    var seen = []

    for await v in counted(3)
        push(seen, v)

    assertEq(seen, [10, 20, 30])

@test
async a_for_await_breaks_with_a_value_and_takes_an_else() =
    counted(n)
        var i = 0
        val it = {}

        it.next = () ->
            if i >= n then { done: true, value: null }
            else
                i += 1
                { done: false, value: i * 10 }

        it

    val found = 'search for await v in counted(9)
        if v == 30 then break 'search v

    assertEq(found, 30)

    val nothing = for await v in counted(0)
        v
    else
        "none arrived"

    assertEq(nothing, "none arrived")

@test
async a_for_await_evaluates_its_subject_once() =
    // Emitting the subject inside the loop would make a fresh generator every turn and the loop would
    // never end. Both back ends are asserted against it.
    var made = 0

    twoOf()
        yield 1
        yield 2

    once()
        made = made + 1

        twoOf()

    var seen = []

    for await x in once()
        push(seen, x)

    assertEq(seen, [1, 2])
    assertEq(made, 1)
