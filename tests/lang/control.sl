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

// A head that is a row of bare names is the commonest shape a loop has, and the interpreter takes it
// apart without the pattern matcher. These ask what every shape ANSWERS, which is what says the two
// back ends still agree and that the short path binds what the long one did.

@test
a_head_of_bare_names_binds_each_element_in_order() =
    two(rows) =
        var out = []

        for [a, b] in rows
            push(out, a * 10 + b)

        out

    three(rows) =
        var out = []

        for [a, b, c] in rows
            push(out, a + b + c)

        out

    assertEq(two([[1, 2], [3, 4]]), [12, 34])
    assertEq(three([[1, 2, 3], [4, 5, 6]]), [6, 15])

@test
an_object_head_binds_the_fields_it_names() =
    named(rows) =
        var out = ""

        for { k, v } in rows
            out = out + k + string(v)

        out

    assertEq(named([{ k: "a", v: 1 }, { k: "b", v: 2 }]), "a1b2")

    // A field the head does not name is ignored, and one it reads through a proto counts.
    spare(rows) =
        var out = 0

        for { n } in rows
            out = out + n

        out

    assertEq(spare([{ n: 1, other: "x" }, { n: 2 }]), 3)
    assertEq(spare([{ proto: { n: 5 } }]), 5)

@test
a_head_whose_element_does_not_fit_is_a_fault() =
    assert(short([[1, 2], [3]]) catch e -> true)
    assert(short([[1, 2, 3]]) catch e -> true)
    assert(short([7]) catch e -> true)
    assert(missing([{ m: 1 }]) catch e -> true)
    assert(missing([7]) catch e -> true)

short(rows) =
    var n = 0

    for [a, b] in rows
        n = n + a + b

    n

missing(rows) =
    var n = 0

    for { k } in rows
        n = n + k

    n

@test
a_head_with_a_default_a_rest_or_a_nested_pattern_binds_as_it_always_did() =
    defaulted(rows) =
        var out = []

        for [a, b = 7] in rows
            push(out, a * 10 + b)

        out

    rested(rows) =
        var out = []

        for [a, ...more] in rows
            push(out, a + more.length)

        out

    nested(rows) =
        var out = []

        for [[a, b], c] in rows
            push(out, a + b + c)

        out

    assertEq(defaulted([[1], [2, 3]]), [17, 23])
    assertEq(rested([[1, 2, 3], [4]]), [3, 4])
    assertEq(nested([[[1, 2], 3], [[4, 5], 6]]), [6, 15])

@test
a_head_of_two_names_walks_a_maps_pairs() =
    summed(m) =
        var total = 0

        for [k, v] in m
            total = total + v

        total

    assertEq(summed(Map([["a", 1], ["b", 2]])), 3)

@test
a_head_shadows_and_gives_back_whatever_shape_it_has() =
    shadowed() =
        val a = "outer"
        var last = ""

        for { a, b } in [{ a: "x", b: "y" }]
            last = a + b

        last + " " + a

    assertEq(shadowed(), "xy outer")

// A block that closes ends the expression holding it, so the line under it is a statement of its own
// whatever it begins with. Each of these was read as an operator on the block's value: `-1` as a
// subtraction from the `if`, `[i, 1]` as an index on the loop's last line, `(` as a call.

@test
A_LINE_UNDER_AN_if_THAT_BEGINS_WITH_A_MINUS_IS_A_STATEMENT_AND_NOT_A_SUBTRACTION() =
    sign(x)
        if x > 0
            return 1

        -1

    assertEq(sign(0), -1)
    assertEq(sign(5), 1)

@test
A_LINE_UNDER_A_while_THAT_BEGINS_WITH_A_BRACKET_IS_AN_ARRAY_AND_NOT_AN_INDEX() =
    counted()
        var i = 0
        while i < 2
            i = i + 1
        [i, 1]

    assertEq(counted(), [2, 1])

@test
A_LINE_UNDER_A_for_THAT_BEGINS_WITH_A_BRACE_IS_AN_OBJECT() =
    total()
        var n = 0
        for x in [1, 2, 3]
            n = n + x
        { n: n }

    assertEq(total(), { n: 6 })

@test
A_LINE_UNDER_A_match_THAT_BEGINS_WITH_A_PARENTHESIS_IS_A_GROUP_AND_NOT_A_CALL() =
    named(x)
        val word = x match
            1 -> "one"
            _ -> "many"
        (word + "!")

    assertEq(named(1), "one!")
    assertEq(named(2), "many!")

@test
A_LINE_UNDER_A_BLOCK_LAMBDA_IS_A_STATEMENT_OF_ITS_OWN() =
    tripled()
        val triple = x ->
            val y = x * 3
            y
        -triple(2)

    assertEq(tripled(), -6)

@test
A_LINE_UNDER_A_try_AND_ITS_catch_IS_A_STATEMENT_OF_ITS_OWN() =
    recovered()
        val v = try
            1 \ 0
        catch e
            10
        -v

    assertEq(recovered(), -10)

@test
A_LINE_THAT_CLOSES_TWO_BLOCKS_AT_ONCE_BEGINS_A_STATEMENT_TOO() =
    summed(xs)
        var n = 0
        for x in xs
            if x > 1
                n = n + x
        [n, -n]

    assertEq(summed([1, 2, 3]), [5, -5])

@test
A_STRING_UNDER_AN_if_AND_ITS_else_IS_THE_ANSWER() =
    said(x)
        var s = ""
        if x
            s = "yes"
        else
            s = "no"
        "said"

    assertEq(said(true), "said")

@test
A_LINE_UNDER_A_WRAPPED_CONDITIONAL_IS_A_STATEMENT_OF_ITS_OWN() =
    shape(xs)
        val kind = if xs.length == 0
            then "empty"
            else "carrying"
        [kind, -xs.length]

    assertEq(shape([]), ["empty", 0])
    assertEq(shape([7]), ["carrying", -1])

// What a closing block must NOT end: a line continued inside brackets, and a chain written after the
// bracket that closes a block lambda, are each still one expression.

@test
A_LINE_WRAPPED_INSIDE_BRACKETS_IS_STILL_ONE_EXPRESSION() =
    val sum = (1 +
        2 -
        [10][0])

    assertEq(sum, -7)

@test
A_BRACKET_THAT_CLOSES_A_BLOCK_LAMBDA_CAN_STILL_BE_CHAINED() =
    val out = [1, 2].map(x ->
        val y = x * 2
        y).map(x -> x + 1)

    assertEq(out, [3, 5])

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

// Every loop form is written round a place both its own back edge and a `continue` are aimed at, and
// the two are not always the same instruction -- a `do` loop repeats from the top and continues at
// the test. This says all four agree about which turns a `continue` skips.
@test
continue_skips_the_rest_of_the_turn_in_every_loop_form() =
    var whiled = []
    var i = 0

    while i < 6
        i = i + 1

        if i == 3 then continue

        push(whiled, i)

    assertEq(whiled, [1, 2, 4, 5, 6])

    var looped = []
    var j = 0

    loop
        j = j + 1

        if j > 6 then break
        if j == 3 then continue

        push(looped, j)

    assertEq(looped, [1, 2, 4, 5, 6])

    var repeated = []
    var k = 0

    do
        k = k + 1

        if k == 3 then continue

        push(repeated, k)
    while k < 6

    assertEq(repeated, [1, 2, 4, 5, 6])

@test
an_if_is_an_expression() =
    assertEq(if true then 1 else 2, 1)
    assertEq(if false then 1 else 2, 2)

@test
truthiness_follows_javascripts_rule() =
    // false, null, an absent value, 0 (and -0), NaN and "" are falsy; everything else is truthy --
    // see tests/lang/values.sl for the full table over every value kind.
    assert(!boolean(0))
    assert(!boolean(""))
    assert(!boolean(null))
    assert(!boolean(false))
    assert(boolean([]))
    assert(boolean({}))

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
    val e = (1 \ 0) catch e -> e

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
        1 \ 0
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

    // A finished one goes on answering, and its value is `null`.
    val after = next(g)

    assertEq(after.value, null)
    assert(after.done)

@test
A_BARE_next_SENDS_undefined_AND_next_v_SENDS_v() =
    // **Nothing passed is absence, which slate spells `undefined`** -- JavaScript's own answer -- so
    // the `yield` says what it means by nothing with `??`.
    echoer() =
        val got = (yield 1) ?? "nothing"

        yield got

    val bare = echoer()

    bare.next()
    assertEq(bare.next().value, "nothing")

    val sent = echoer()

    sent.next()
    assertEq(sent.next("v").value, "v")

    // A `for` sends nothing in, exactly as a bare `next()` does.
    var seen = []

    for x in echoer()
        seen.push(x)

    assertEq(seen, [1, "nothing"])

@test
A_BARE_next_INTO_A_KEPT_yield_FAULTS_IN_WORDS_ABOUT_THE_GENERATOR() =
    // `undefined` may not be kept, but "this field is not there" would be false of a `yield`, so
    // the sentence names the generator -- the same words on both back ends.
    val said = "this generator was resumed with nothing, and `undefined` cannot be kept -- give the `yield` a value with `??`, or call `next(v)`"

    bound() =
        val got = yield 1

        yield got

    val b = bound()

    b.next()
    assertEq(b.next() catch e -> e.message, said)
    assert(b.next().done)

    // A write to a `var` is refused the same way.
    written() =
        var got = 0

        got = yield 1
        yield got

    val w = written()

    w.next()
    assertEq(w.next() catch e -> e.message, said)

    // And so is a write to a local a closure holds.
    captured() =
        var got = 0
        val f = () -> got

        got = yield 1
        yield f()

    val c = captured()

    c.next()
    assertEq(c.next() catch e -> e.message, said)

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
async AN_ASYNC_LAMBDA_TAKES_ITS_PARAMETERS_IN_BRACKETS_AS_WELL_AS_BARE() =
    val none = async () -> 7
    val one = async (x) -> x + 1
    val two = async (a, b) -> a + b
    val bare = async x -> x + 1

    assertEq(await none(), 7)
    assertEq(await one(1), 2)
    assertEq(await two(1, 2), 3)
    assertEq(await bare(1), 2)

@test
async AN_ASYNC_LAMBDAS_BRACKETS_TAKE_EVERY_PARAMETER_FORM_A_WRITTEN_LAMBDA_TAKES() =
    val defaulted = async (a, b = 5) -> a + b
    val rested = async (a, ...rest) -> a + rest.length
    val fromObject = async ({ a, b }) -> a + b
    val fromArray = async ([a, b]) -> a + b

    assertEq(await defaulted(1), 6)
    assertEq(await defaulted(1, 2), 3)
    assertEq(await rested(1, 2, 3), 3)
    assertEq(await fromObject({ a: 1, b: 2 }), 3)
    assertEq(await fromArray([1, 2]), 3)

@test
async AN_ASYNC_LAMBDA_IN_BRACKETS_READS_THE_SAME_WHEREVER_IT_STANDS() =
    doubled(x) =
        async (y) -> y * x

    // As an argument, immediately invoked, nested one inside another, and awaiting in its own body.
    val promises = [1, 2, 3].map(async (x) -> await resolve(x * 2))
    val twice = doubled(2)

    assertEq(await promises[0], 2)
    assertEq(await promises[2], 6)
    assertEq(await (async (x) -> x + 1)(41), 42)
    assertEq(await twice(21), 42)

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
async AN_ASYNC_BODY_THAT_YIELDS_IS_A_GENERATOR_WHOSE_STEPS_ANSWER_PROMISES() =
    // A body that is both `async` and holds a `yield` produces a source: calling it runs nothing
    // and answers a generator, and `next()` on that answers a promise of `{ value, done }` --
    // which is the shape `for await` was already written against.
    async ticks(n)
        var i = 0

        while i < n
            await sleep(1)

            yield i * 10

            i = i + 1

    var seen = []

    for await v in ticks(3)
        push(seen, v)

    assertEq(seen, [0, 10, 20])

@test
async AN_ASYNC_GENERATOR_STEPPED_BY_HAND_HANDS_BACK_A_PROMISE_EACH_TIME() =
    async two()
        await sleep(1)

        yield "a"

        yield "b"

        "end"

    val g = two()
    val first = g.next()

    assert(first is promise)

    assertEq((await first).value, "a")
    assertEq((await g.next()).value, "b")

    // **What the body answered is the value on the last step**, exactly as a plain generator's is.
    val last = await g.next()

    assertEq(last.value, "end")
    assert(last.done)

    // And a finished one goes on answering, in the same shape.
    val after = await g.next()

    assertEq(after.value, null)
    assert(after.done)

@test
async A_VALUE_SENT_INTO_AN_ASYNC_GENERATOR_IS_WHAT_ITS_yield_ANSWERS() =
    async echoer()
        val got = yield 1

        await sleep(1)

        yield got * 10

    val e = echoer()

    assertEq((await e.next()).value, 1)
    assertEq((await e.next(5)).value, 50)

@test
async A_BARE_next_SENDS_undefined_INTO_AN_ASYNC_GENERATOR_TOO() =
    async echoer()
        val got = (yield 1) ?? "nothing"

        await sleep(1)

        yield got

    val bare = echoer()

    await bare.next()
    assertEq((await bare.next()).value, "nothing")

    val sent = echoer()

    await sent.next()
    assertEq((await sent.next("v")).value, "v")

    // `for await` sends nothing in either.
    var seen = []

    for await x in echoer()
        seen.push(x)

    assertEq(seen, [1, "nothing"])

@test
async A_FAULT_INSIDE_AN_ASYNC_GENERATOR_REJECTS_THE_next_THAT_IS_WAITING() =
    async breaks()
        yield 1

        await sleep(1)

        throw "gone wrong"

    val g = breaks()

    assertEq((await g.next()).value, 1)
    assertEq((await g.next()) catch e -> e.message, "gone wrong")

    // **A faulted generator is finished**, so the step after it says so rather than faulting again.
    assert((await g.next()).done)

@test
async AN_ASYNC_GENERATOR_IS_NOT_SOMETHING_A_PLAIN_for_CAN_WALK() =
    async ticks()
        await sleep(1)

        yield 1

    val said = try
        for x in ticks()
            print(x)

        "walked"
    catch e
        e.message

    assertEq(said, "an `async` generator's values arrive one promise at a time -- `for await` is the only way to walk one")

    // The same sentence for a walk that materialises rather than steps.
    val spread = try
        [...ticks()]
    catch e
        e.message

    assertEq(spread, "an `async` generator's values arrive one promise at a time -- `for await` is the only way to walk one")

@test
A_PLAIN_GENERATOR_IS_UNTOUCHED_BY_ANY_OF_IT() =
    // **The control.** Nothing about a generator with no `async` on it changed: it is driven on the
    // caller's own turn, answers the pair outright rather than a promise, and a `for` walks it.
    twoOf()
        yield 1
        yield 2

    val g = twoOf()
    val step = g.next()

    assert(!(step is promise))
    assertEq(step.value, 1)
    assertEq(array(twoOf()), [1, 2])

    var seen = []

    for x in twoOf()
        push(seen, x)

    assertEq(seen, [1, 2])

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

@test
a_range_steps_by_what_by_says() =
    var up = []

    for x in 0..<10 by 2
        push(up, x)

    var down = []

    for x in 10..0 by -1
        push(down, x)

    assertEq(up, [0, 2, 4, 6, 8])
    assertEq(down, [10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    assertEq(string(Set(1..9 by 3)), "[1, 4, 7]")

@test
a_step_that_runs_away_from_its_end_covers_nothing() =
    // The answer `10..0` already gave before there were steps: a range that cannot reach its ceiling
    // is empty rather than a mistake.
    assertEq((0..10 by -1).length, 0)
    assertEq((10..0 by 2).length, 0)

    var seen = []

    for x in 0..10 by -1
        push(seen, x)

    assertEq(seen, [])

@test
a_stepped_range_counts_prints_and_compares_by_the_numbers_it_covers() =
    assertEq((0..<10 by 2).length, 5)
    assertEq((10..0 by -1).length, 11)
    assertEq((1..9 by 3).length, 3)
    assertEq(string(0..<10 by 2), "0..<10 by 2")
    assertEq(string(0..3), "0..3")

    // `0..<10 by 2` and `0..8 by 2` are the same five numbers, exactly as `1..3` and `1..<4` are the
    // same three -- so they are equal and therefore find each other in a table.
    assert(0..<10 by 2 == 0..8 by 2)
    assert(!(0..<10 by 2 == 0..<10))

    val o = {}

    o[0..<10 by 2] = "evens"

    assertEq(o[0..8 by 2], "evens")

@test
a_stepped_range_slices_by_the_positions_it_covers() =
    assertEq([10, 20, 30, 40, 50, 60][0..<6 by 2], [10, 30, 50])
    assertEq("abcdef"[0..<6 by 2], "ace")
    assertEq([1, 2, 3][2..0 by -1], [3, 2, 1])

@test
a_stepped_range_is_a_pattern_as_an_ordinary_one_is() =
    assert(6 is 0..<10 by 2)
    assert(!(7 is 0..<10 by 2))

    grade(n) = n match
        0..<10 by 3 -> "on"
        _           -> "off"

    assertEq(grade(9), "on")
    assertEq(grade(8), "off")

@test
by_IS_A_SOFT_WORD_AND_STAYS_AN_ORDINARY_NAME() =
    // Taking `by` as a keyword would take the name away from every program that wanted it. It means a
    // step only where a range has just been read, which is the one place it can mean anything.
    var by = 3

    by = by + 1

    assertEq(by, 4)
    assertEq({ by: 7 }.by, 7)
    assertEq((0..<12 by by).length, 3)

    double(by) = by * 2

    assertEq(double(5), 10)

// Every statement here stands where its value goes unread, which is the one position the compiler
// no longer produces a value for. What each of them ANSWERS where somebody does read it is the half
// these pin, on both back ends.

@test
an_assignment_answers_null_where_a_block_ends_with_one() =
    counted()
        var x = 1

        x = 2

    swapped()
        var a = 1
        var b = 2

        a, b = b, a

    assertEq(counted(), null)
    assertEq(swapped(), null)

@test
A_LOOP_AS_A_FUNCTIONS_LAST_STATEMENT_ANSWERS_WHAT_THE_LOOP_ANSWERS() =
    // A loop is an expression, so the value of a function ending in one is the loop's -- null where
    // it ran out, the `break`'s value where one was taken, and the `else`'s where there was one.
    counted()
        var i = 0

        while i < 3
            i = i + 1

    searched(xs)
        for x in xs
            if x > 1 then break x
        else
            "none"

    assertEq(counted(), null)
    assertEq(searched([1, 2]), 2)
    assertEq(searched([1]), "none")

@test
break_and_continue_and_return_stand_in_statement_position() =
    var seen = []

    for x in [1, 2, 3, 4]
        if x == 2 then continue
        if x == 4 then break

        push(seen, x)

    find(xs, want)
        for x in xs
            if x == want
                return "found"

        "missing"

    assertEq(seen, [1, 3])
    assertEq(find([1, 2], 2), "found")
    assertEq(find([1, 2], 3), "missing")

@test
a_match_a_try_and_an_if_read_alike_as_statements_and_as_expressions() =
    var side = ""

    tell(n)
        n match
            0 -> side = "zero"
            _ -> side = "other"

        side

    named(n) = n match
        0 -> "zero"
        _ -> "other"

    handled()
        var seen = ""

        try
            throw "boom"
        catch e
            seen = "caught"

        seen

    assertEq(tell(0), "zero")
    assertEq(tell(5), "other")
    assertEq(named(0), "zero")
    assertEq(handled(), "caught")

    val said = try
        throw "boom"
    catch e
        "caught"

    assertEq(said, "caught")

@test
a_generator_called_as_a_statement_still_runs_nothing() =
    var steps = 0

    counting()
        steps = steps + 1

        yield 1

    counting()

    assertEq(steps, 0)

@test
async an_async_call_whose_promise_nobody_reads_still_runs() =
    var ran = false

    async go()
        ran = true

    go()

    await null

    assertEq(ran, true)
