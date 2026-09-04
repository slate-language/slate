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

@test
AN_is_THAT_BINDS_A_NAME_DOES_NOT_LEAVE_IT_BEHIND_AFTER_THE_CALL()
    // **A bare name in pattern position binds**, so `v is n` names the subject -- and the binding is
    // the call's, not the module's. A function whose parameters and locals are numbered cells has no
    // scope object of its own to write it into, so this pins that such a function is not given one
    // and the name is left alone outside it.
    var n = 0

    named(v) = v is n

    assert(named(7))
    assertEq(n, 0)

    named(9)
    assertEq(n, 0)

@test
A_for_HEAD_THAT_TAKES_ITS_ELEMENT_APART_BINDS_A_TURN_AT_A_TIME()
    // Each turn writes the head's names again, so what the last turn left is what is read after it
    // and nothing carries over from the turn before.
    seen(pairs) =
        var out = []

        for [a, b] in pairs
            push(out, a * 10 + b)

        out

    assertEq(seen([[1, 2], [3, 4], [5, 6]]), [12, 34, 56])

@test
A_for_HEAD_SHADOWS_AN_OUTER_NAME_AND_GIVES_IT_BACK()
    shadowed() =
        val a = "outer"
        var last = ""

        for [a, b] in [["x", "y"]]
            last = a + b

        last + " " + a

    assertEq(shadowed(), "xy outer")

@test
A_DESTRUCTURING_BINDING_IS_READ_AFTER_THE_STATEMENT_THAT_MADE_IT()
    taken(o) =
        val { name, count } = o
        val [head, ...rest] = [1, 2, 3]

        name + string(count) + string(head) + string(len(rest))

    assertEq(taken({ name: "n", count: 7 }), "n712")

@test
A_DESTRUCTURING_BINDING_SHADOWS_AN_OUTER_NAME_OF_THE_SAME_SPELLING()
    shadowed() =
        val name = "outer"
        var inner = ""

        if true
            val { name } = { name: "inner" }

            inner = name

        inner + " " + name

    assertEq(shadowed(), "inner outer")

@test
ONE_NAME_BOUND_BY_TWO_ARMS_OF_A_match_IS_TWO_BINDINGS_AND_NOT_ONE()
    // **Two cells rather than one written twice**, which is what makes the second arm's value its
    // own however the first arm went -- and the arm that misses must leave nothing behind.
    read(v) = v match
        [n] -> "one " + string(n)
        [n, m] -> "two " + string(n + m)
        { n } -> "field " + string(n)
        _ -> "none"

    assertEq(read([5]), "one 5")
    assertEq(read([5, 6]), "two 11")
    assertEq(read({ n: 9 }), "field 9")
    assertEq(read("x"), "none")

@test
A_match_ARM_SHADOWS_AN_OUTER_NAME_AND_GIVES_IT_BACK()
    shadowed(v) =
        val n = "outer"

        val said = v match
            [n] -> string(n)
            _ -> "no arm"

        said + " " + n

    assertEq(shadowed([3]), "3 outer")
    assertEq(shadowed(4), "no arm outer")

@test
AN_ARM_THAT_MISSED_LEAVES_NOTHING_FOR_THE_NEXT_ONE_TO_READ()
    // The first arm binds `a` and then its guard turns it down, so the arm that takes has to answer
    // with what IT bound rather than with what the arm before it left standing.
    read(v) = v match
        [a] if a > 10 -> "big " + string(a)
        [a] -> "small " + string(a)
        _ -> "none"

    assertEq(read([3]), "small 3")
    assertEq(read([30]), "big 30")

@test
A_NAME_A_PATTERN_BINDS_IS_THE_ONE_A_NESTED_BLOCK_READS()
    // A `for` inside a `match` arm inside a `for`: three binding sites, three sets of cells, and the
    // innermost is what a read finds.
    walk(rows) =
        var out = []

        for [tag, items] in rows
            val said = tag match
                "sum" ->
                    var total = 0

                    for n in items
                        total = total + n

                    total
                _ -> 0

            push(out, said)

        out

    assertEq(walk([["sum", [1, 2, 3]], ["other", [9]]]), [6, 0])

@test
A_PATTERN_DEFAULT_IS_TAKEN_WHERE_THE_SUBJECT_SUPPLIED_NOTHING()
    read(o) =
        val { title = "Untitled", tag } = o

        title + " " + tag

    assertEq(read({ tag: "a" }), "Untitled a")
    assertEq(read({ title: "Given", tag: "b" }), "Given b")

@test
TWO_DEFAULTS_WITH_A_HOLE_BETWEEN_THEM_ARE_ANSWERED_ONE_AT_A_TIME()
    // **The case a COUNT gets wrong and a per-name record gets right.** The subject supplied the
    // second of two defaulted names and not the first, so "how many arrived" says nothing useful --
    // it is the same question a call with named arguments poses, and it is answered the same way.
    read(o) =
        val { title = "Untitled", count = 0, tag } = o

        title + " " + string(count) + " " + tag

    assertEq(read({ tag: "a" }), "Untitled 0 a")
    assertEq(read({ title: "T", tag: "b" }), "T 0 b")
    assertEq(read({ count: 9, tag: "c" }), "Untitled 9 c")
    assertEq(read({ title: "T", count: 9, tag: "d" }), "T 9 d")

@test
AN_ARRAY_PATTERN_DEFAULT_FILLS_AN_ELEMENT_THE_ARRAY_NEVER_REACHED()
    read(xs) =
        val [first, second = 20, third = 30] = xs

        first + second + third

    assertEq(read([1]), 51)
    assertEq(read([1, 2]), 33)
    assertEq(read([1, 2, 3]), 6)

@test
A_DEFAULT_MAY_READ_A_NAME_BOUND_TO_ITS_LEFT()
    // A default is worked out where the binding is, so the names before it are already in their
    // cells by the time it runs.
    read(o) =
        val { width, height = width * 2 } = o

        string(width) + "x" + string(height)

    assertEq(read({ width: 3 }), "3x6")
    assertEq(read({ width: 3, height: 4 }), "3x4")

@test
A_DEFAULT_IS_NOT_WORKED_OUT_WHERE_THE_SUBJECT_SUPPLIED_THE_NAME()
    // **A design that filled the cell first and overwrote it would pass every test above and fail
    // this one**, the default's own work being the only thing that can tell the two apart.
    var ran = 0

    counted() =
        ran = ran + 1
        99

    read(o) =
        val { n = counted() } = o

        n

    assertEq(read({ n: 1 }), 1)
    assertEq(ran, 0)
    assertEq(read({}), 99)
    assertEq(ran, 1)

@test
A_QUESTION_MARK_IN_A_match_ARM_LEAVES_ITS_NAME_UNBOUND()
    // `?` says a field may be missing and says nothing about what to bind, so there is nothing to
    // fill a cell with -- which is why a chunk holding one keeps its scope. A binding position
    // refuses `?` outright and tells the reader to write a default instead.
    read(o) = o match
        { a?, b } -> "took " + string(b)
        _ -> "no arm"

    assertEq(read({ b: 1 }), "took 1")
    assertEq(read({ a: 5, b: 1 }), "took 1")
    assertEq(read({ c: 1 }), "no arm")
