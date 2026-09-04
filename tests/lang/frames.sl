// What a call's own frame holds: its parameters, and the fact that they are its and nobody else's.
//
// **These are ordinary questions about a running program and they were all true before slots.** They
// are written down because a parameter is a numbered cell of the frame in the interpreter now rather
// than a name in a scope object, and every one of them is a way that arrangement could be wrong
// while an ordinary program still looked right.
//
// **THERE ARE FOUR PATHS INTO A CHUNK AND EACH ONE HAS TO LAY THE ARGUMENTS DOWN**: an ordinary
// call, a call reached from a builtin such as `map`, an `async` function being started, and a
// generator being prepared. Three of those are somewhere else in this directory for other reasons;
// they are all here as well, because what they share is exactly the thing under test.

counter(n)
    n = n + 1
    n

var evaluated = 0

bump()
    evaluated = evaluated + 1
    evaluated

down(n)
    if n == 0 then return []

    val rest = down(n - 1)

    push(rest, n)
    rest

@test
A_PARAMETER_IS_THE_CALLS_OWN_CELL_AND_NOT_THE_LAST_CALLS()
    // A parameter written to inside the function. Were the cell shared, the second call would start
    // from what the first left.
    assertEq(counter(1), 2)
    assertEq(counter(1), 2)
    assertEq(counter(41), 42)

@test
RECURSION_GIVES_EVERY_FRAME_ITS_OWN_PARAMETER()
    // Each frame reads its own `n` after the call it made has returned and truncated the stack back.
    assertEq(down(4), [1, 2, 3, 4])
    assertEq(down(0), [])

@test
A_val_MAY_SHADOW_A_PARAMETER_AND_THE_PARAMETER_IS_GONE_FROM_THERE_ON()
    shadowed(x) =
        val y = x + 1
        val x = y * 10

        x

    assertEq(shadowed(2), 30)

@test
A_DEFAULT_IS_WORKED_OUT_AT_THE_CALL_AND_READS_THE_PARAMETERS_TO_ITS_LEFT()
    f(a, b = a + 1) = [a, b]

    assertEq(f(1), [1, 2])
    assertEq(f(1, 9), [1, 9])
    assertEq(f(5), [5, 6])

@test
A_DEFAULT_IS_NOT_WORKED_OUT_WHERE_THE_ARGUMENT_WAS_GIVEN()
    // **The one a sentinel design gets wrong quietly.** A parameter filled with an "unset" marker and
    // tested for it would run the default anyway where a program passed something that compared
    // equal to the marker; here the question is whether an argument arrived at all.
    g(x = bump()) = x

    evaluated = 0

    assertEq(g(100), 100)
    assertEq(evaluated, 0, "the default never ran")

    assertEq(g(), 1)
    assertEq(evaluated, 1)

@test
A_REST_PARAMETER_GATHERS_WHATEVER_IS_LEFT_INCLUDING_NOTHING()
    f(a, ...rest) = [a, rest]

    assertEq(f(1), [1, []])
    assertEq(f(1, 2), [1, [2]])
    assertEq(f(1, 2, 3, 4, 5), [1, [2, 3, 4, 5]])

@test
A_DEFAULT_BEFORE_A_REST_PARAMETER_STILL_LEAVES_THE_GATHERED_ARRAY_LAST()
    // **The case that decides where a gathered array goes**, and the reason it is not simply the
    // position it arrived in: `h(1)` gives one argument and one gathered array, and the array
    // belongs to `rest` rather than to the defaulted `b` it happens to sit beside.
    h(a, b = 9, ...rest) = [a, b, rest]

    assertEq(h(1), [1, 9, []])
    assertEq(h(1, 2), [1, 2, []])
    assertEq(h(1, 2, 3, 4), [1, 2, [3, 4]])

@test
A_DESTRUCTURING_PARAMETER_IS_A_PARAMETER_PLUS_AN_UNPACK()
    area({ w, h }) = w * h

    assertEq(area({ w: 3, h: 4 }), 12)
    assertEq(area({ w: 3, h: 4, colour: "red" }), 12)

@test
A_FUNCTION_REACHED_FROM_A_BUILTIN_GETS_ITS_PARAMETERS_THE_SAME_WAY()
    // `map` calls this from inside the runtime rather than from a call instruction, which is a
    // second way into the chunk.
    twice(n, by = 2) = n * by

    assertEq(map([1, 2, 3], twice), [2, 4, 6])

@test
async AN_async_FUNCTION_IS_STARTED_WITH_ITS_ARGUMENTS_AND_ITS_DEFAULTS()
    // A third way in: an `async` function is not called, it is started on a line of execution of its
    // own -- and the arguments have to reach that one.
    sum(a, b = 10) = a + b

    async both(a, b = 10)
        val first = sum(a, b)

        first + a

    assertEq(await both(1), 12)
    assertEq(await both(1, 1), 3)

@test
A_GENERATOR_IS_PREPARED_WITH_ITS_ARGUMENTS_LONG_BEFORE_IT_RUNS()
    // The fourth way in, and the one where the arguments have to survive the longest: calling a
    // generator runs nothing at all, so what it was given has to still be there when something first
    // asks it for a value.
    counting(from, step = 1)
        var n = from

        yield n
        n = n + step
        yield n
        n = n + step
        yield n

    val g = counting(10)

    assertEq(next(g).value, 10)
    assertEq(next(g).value, 11)
    assertEq(next(g).value, 12)
    assertEq(next(g).done, true)

    val h = counting(0, 5)

    assertEq(next(h).value, 0)
    assertEq(next(h).value, 5)
    assertEq(next(h).value, 10)
