// Leaving a `for` or a `for await` early closes the iterator it was walking -- JavaScript's
// IteratorClose. A `break`, a `return`, a `break` or `continue` to an outer loop and a fault on its way
// past all call the iterator's `return()`; running out calls nothing. A generator's `return()` leaves
// its body from the `yield` it stood at, so the generator's own `using` blocks are released.
//
// **A log is what makes this observable on both back ends**: a generator writes its name down when
// its `using` is released, so the order of the log is the whole assertion.

made(log, name) = { dispose: () -> push(log, name) }

fails(why) =
    throw why

// A generator that holds a resource across its `yield`s.
counted(log, name, n) =
    using r = made(log, name)

    for i in 0..<n
        yield i

// A generator whose release fails.
spoiled(why) =
    using r = { dispose: () -> fails(why) }

    yield 1
    yield 2

// An iterator that is not a generator: `next` and `return` written out, `return` writing itself down.
counter(log, n, closes) =
    var i = 0

    step() =
        i = i + 1
        return { value: i, done: i > n }

    if closes
        return { next: step, return: () -> push(log, "return") }

    { next: step }

@test
a_break_closes_the_generator_a_for_was_walking() =
    var log = []

    for x in counted(log, "g", 5)
        push(log, x)
        if x == 1 then break

    push(log, "after")
    assertEq(log, [0, 1, "g", "after"])

@test
running_out_closes_nothing_the_generator_ending_on_its_own() =
    var log = []

    for x in counted(log, "g", 2)
        push(log, x)

    push(log, "after")
    assertEq(log, [0, 1, "g", "after"])

@test
a_continue_of_the_same_loop_closes_nothing() =
    var log = []

    for x in counted(log, "g", 3)
        if x == 1 then continue
        push(log, x)

    assertEq(log, [0, 2, "g"])

@test
a_return_closes_before_the_function_answers() =
    var log = []

    first() =
        for x in counted(log, "g", 5)
            if x == 2 then return x

    assertEq(first(), 2)
    assertEq(log, ["g"])

@test
a_fault_closes_on_its_way_past_and_keeps_its_own_message() =
    var log = []

    walk() =
        for x in counted(log, "g", 5)
            if x == 1 then fails("boom")

    assertEq(walk() catch e -> e.message, "boom")
    assertEq(log, ["g"])

@test
a_labelled_continue_closes_the_inner_loop_only_and_a_labelled_break_closes_both() =
    var log = []

    'outer for i in counted(log, "outer", 3)
        for x in counted(log, s"inner ${i}", 3)
            if i == 0 then continue 'outer
            break 'outer

    assertEq(log, ["inner 0", "inner 1", "outer"])

@test
a_using_in_the_body_is_released_before_the_iterator_is_closed() =
    var log = []

    for x in counted(log, "g", 3)
        using b = made(log, "body")
        break

    assertEq(log, ["body", "g"])

@test
a_return_that_faults_on_a_break_is_the_fault_the_loop_raises() =
    walk() =
        for x in spoiled("closing failed")
            break

    assertEq(walk() catch e -> e.message, "closing failed")

@test
a_return_that_faults_while_a_fault_is_leaving_loses_to_the_first() =
    walk() =
        for x in spoiled("closing failed")
            fails("the first")

    assertEq(walk() catch e -> e.message, "the first")

@test
closing_a_pipeline_closes_every_generator_in_it() =
    var log = []

    doubled(source) =
        using r = made(log, "doubled")

        for x in source
            yield x * 2

    for x in doubled(counted(log, "counted", 9))
        if x == 4 then break

    assertEq(log, ["counted", "doubled"])

@test
return_leaves_a_generator_where_it_stands_and_answers_what_it_was_given() =
    var log = []
    val g = counted(log, "g", 5)

    assertEq(g.next(), { value: 0, done: false })
    assertEq(g.return(9), { value: 9, done: true })
    assertEq(log, ["g"])
    assertEq(g.next(), { value: null, done: true })
    assertEq(g.return(), { value: null, done: true })

@test
return_on_a_generator_never_started_runs_nothing() =
    var log = []
    val g = counted(log, "g", 5)

    assertEq(g.return(), { value: null, done: true })
    assertEq(g.next(), { value: null, done: true })
    assertEq(log, [])

@test
a_catch_around_the_yield_does_not_catch_a_return() =
    var log = []

    guarded() =
        try
            yield 1
            yield 2
        catch e
            push(log, "caught")

        push(log, "carried on")

    val g = guarded()

    g.next()
    assertEq(g.return(3), { value: 3, done: true })
    assertEq(log, [])

@test
async a_for_await_left_early_calls_return_and_running_out_does_not() =
    var log = []

    for await x in counter(log, 5, true)
        if x == 2 then break

    push(log, "broke")

    for await x in counter(log, 2, true)
        push(log, x)

    assertEq(log, ["return", "broke", 1, 2])

@test
async an_iterator_with_no_return_is_left_alone() =
    var seen = []

    for await x in counter([], 5, false)
        push(seen, x)
        if x == 2 then break

    assertEq(seen, [1, 2])

@test
async a_next_that_faults_closes_nothing() =
    var log = []
    val broken = { next: () -> fails("no next"), return: () -> push(log, "return") }

    async walk() =
        for await x in broken
            push(log, x)

    assertEq(await walk() catch e -> e.message, "no next")
    assertEq(log, [])

@test
async a_for_await_awaits_what_return_answers() =
    var log = []

    async closing() =
        await sleep(5)
        push(log, "closed")

    val source = { next: () -> { value: 1, done: false }, return: closing }

    for await x in source
        break

    push(log, "after")
    assertEq(log, ["closed", "after"])

@test
async a_for_await_closes_an_async_generator_and_releases_what_it_held() =
    var log = []

    async ticks() =
        using r = made(log, "ticks")

        for i in 0..<5
            await sleep(1)
            yield i

    for await x in ticks()
        using b = made(log, "body")
        if x == 1 then break

    assertEq(log, ["body", "body", "ticks"])

@test
async a_fault_in_a_for_await_body_closes_the_source() =
    var log = []

    async walk() =
        for await x in counter(log, 5, true)
            fails("boom")

    assertEq(await walk() catch e -> e.message, "boom")
    assertEq(log, ["return"])
