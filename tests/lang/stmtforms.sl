// `if`, `match` and `try` standing where nobody reads their value.
//
// **EVERY TEST HERE ASSERTS AN ANSWER, WHICH IS THE ONLY THING A DRIFTING STACK GETS WRONG.** Written
// as a statement, each of these constructs is compiled to produce no value at all — so every branch,
// every arm and both ways out of a `try` have to reach the join at one depth. A branch that left one
// value too many or too few would put something else's value where the next read expects its own,
// and nothing about the shape of the program would say so. `tests_bookkeeping.sysl` counts the
// instructions; this says the answers did not move.
//
// The value of one of these where somebody DOES read it — the last expression of a function, the
// value of a binding — is the case most likely to be broken by teaching the statement form to leave
// nothing, so it is asserted beside every statement form below.

// At the top of a file every statement is unread, a module answering with its exports rather than
// with its last line.

var topWord = "none"

if 1 > 0
    topWord = "top"
else
    topWord = "bottom"

var topPick = "none"

"b" match
    "a" -> topPick = "first"
    _ -> topPick = "second"

var topCaught = "none"

try
    throw "up"
catch e
    topCaught = e.message

@test
A_STATEMENT_AT_THE_TOP_OF_A_FILE_IS_UNREAD_AND_STILL_RUNS() =
    assertEq(topWord, "top")
    assertEq(topPick, "second")
    assertEq(topCaught, "up")

@test
AN_if_AS_A_STATEMENT_LEAVES_THE_VALUES_AROUND_IT_ALONE() =
    grade(n)
        val before = "kept"
        var word = "?"

        if n > 90
            word = "high"
        elif n > 50
            word = "middle"
        else
            word = "low"

        before + ":" + word

    assertEq(grade(95), "kept:high")
    assertEq(grade(70), "kept:middle")
    assertEq(grade(10), "kept:low")

@test
AN_if_WITH_NO_else_RUNS_NOTHING_AND_STILL_ANSWERS_null_WHERE_IT_IS_READ() =
    bumped(n)
        val before = "kept"
        var v = n

        if n > 0
            v = n + 1

        string(v) + ":" + before

    // The same `if` as the body's last statement, where its value IS the answer: the branch nobody
    // wrote still has to produce the null it always produced.
    taken(n)
        if n > 0
            "yes"

    assertEq(bumped(1), "2:kept")
    assertEq(bumped(-1), "-1:kept")
    assertEq(taken(1), "yes")
    assertEq(taken(-1), null)

@test
AN_if_A_match_AND_A_try_ARE_STILL_EXPRESSIONS_WHERE_THEIR_VALUE_IS_READ() =
    val chosen = if 1 > 0 then "up" else "down"

    picked(n) = n match
        0 -> "zero"
        _ -> "other"

    val caught = try
        throw "boom"
    catch e
        "caught " + e.message

    val quiet = try
        "fine"
    catch e
        "never"

    tail(n)
        val extra = "kept"

        if n > 0
            extra + ":up"
        else
            extra + ":down"

    assertEq(chosen, "up")
    assertEq(picked(0), "zero")
    assertEq(picked(1), "other")
    assertEq(caught, "caught boom")
    assertEq(quiet, "fine")
    assertEq(tail(1), "kept:up")
    assertEq(tail(-1), "kept:down")

@test
A_match_AS_A_STATEMENT_BINDS_AND_GUARDS_AND_LEAVES_NOTHING() =
    said(v)
        val fence = "|"
        var out = "?"

        v match
            n @ number if n > 10 -> out = "big"
            n @ number -> out = "small"
            [a, b] -> out = a + b
            { name } -> out = name
            _ -> out = "other"

        fence + out + fence

    assertEq(said(50), "|big|")
    assertEq(said(2), "|small|")
    assertEq(said(["l", "r"]), "|lr|")
    assertEq(said({ name: "given" }), "|given|")
    assertEq(said("s"), "|other|")

@test
A_match_AS_A_STATEMENT_WITH_NO_ARM_TAKEN_FAULTS_AS_IT_ALWAYS_DID() =
    // **A subject no arm applies to is a fault wherever the `match` stands**, and the statement form
    // has to fault on the same values the expression form faults on — the subject is still standing
    // on the stack for the complaint to name.
    fussy(v)
        v match
            0 -> "taken"

        "after"

    assertEq(fussy(0), "after")
    assertFaults(() -> fussy(9), "no arm of this match applies")

@test
A_try_AS_A_STATEMENT_HANDLES_A_FAULT_AND_LEAVES_NOTHING() =
    // The `throw` sits inside an unread `if` inside the unread `try`, so the fault is raised at a
    // depth the handler has to cut back from correctly.
    run(go)
        val fence = "|"
        var seen = "none"

        try
            if go
                throw "boom"

            seen = "ran"
        catch e
            seen = "caught " + e.message

        fence + seen + fence

    assertEq(run(false), "|ran|")
    assertEq(run(true), "|caught boom|")

@test
A_try_AS_A_STATEMENT_MAY_THROW_AGAIN_FROM_ITS_HANDLER() =
    inner()
        try
            throw "first"
        catch e
            throw "second"

        "unreached"

    outer()
        val fence = "|"
        var seen = "none"

        try
            inner()
        catch e
            seen = e.message

        fence + seen + fence

    assertEq(outer(), "|second|")

@test
AN_UNREAD_CONSTRUCT_INSIDE_AN_UNREAD_CONSTRUCT_LEAVES_NOTHING_EITHER() =
    deep(a, b)
        val fence = "|"
        var out = "?"

        if a
            b match
                0 ->
                    try
                        if true
                            out = "zero"
                    catch e
                        out = "never"
                _ ->
                    if b > 5
                        out = "big"
                    else
                        out = "small"
        else
            out = "off"

        fence + out + fence

    assertEq(deep(true, 0), "|zero|")
    assertEq(deep(true, 9), "|big|")
    assertEq(deep(true, 2), "|small|")
    assertEq(deep(false, 0), "|off|")

@test
break_AND_continue_AND_return_INSIDE_AN_UNREAD_CONSTRUCT_LEAVE_THE_LOOP_AS_THEY_FOUND_IT() =
    walk(xs)
        var seen = []

        for x in xs
            x match
                0 -> continue
                9 -> break
                _ -> push(seen, x)

        seen

    hunt(xs)
        for x in xs
            if x > 1
                return "found"

        "missing"

    // A `break` and a `continue` out of a `try` unwind its handler as well as its scopes.
    guarded(xs)
        var seen = []

        for x in xs
            try
                if x == 2 then continue
                if x == 4 then break

                push(seen, x)
            catch e
                push(seen, "caught")

        seen

    assertEq(walk([1, 0, 2, 9, 3]), [1, 2])
    assertEq(hunt([1, 2]), "found")
    assertEq(hunt([1]), "missing")
    assertEq(guarded([1, 2, 3, 4, 5]), [1, 3])

@test
A_LOOP_BODY_THAT_IS_ONE_UNREAD_CONSTRUCT_RUNS_FOR_EFFECT() =
    // A body written as a bare expression is one statement standing where a block would have stood,
    // so it is asked for no value either.
    counted(xs)
        var seen = []
        var i = 0

        while i < xs.length
            if xs[i] > 1 then push(seen, xs[i])

            i = i + 1

        seen

    assertEq(counted([1, 2, 3]), [2, 3])

@test
AN_UNREAD_CONSTRUCT_INSIDE_A_GENERATOR_YIELDS_WHAT_IT_ALWAYS_DID() =
    picks(n) =
        var i = 0

        while i < n
            if i % 2 == 0
                yield i

            i match
                _ -> i = i + 1

    var seen = []

    for x in picks(5)
        push(seen, x)

    assertEq(seen, [0, 2, 4])

@test
async AN_UNREAD_CONSTRUCT_INSIDE_AN_ASYNC_FUNCTION_ANSWERS_WHAT_IT_ALWAYS_DID() =
    var out = "none"

    if 1 > 0
        out = await resolve("up")
    else
        out = await resolve("down")

    try
        out = out + await resolve("!")
    catch e
        out = "never"

    val said = (await reject("no")) catch e -> e.message

    assertEq(out, "up!")
    assertEq(said, "no")

@test
A_HUNDRED_THOUSAND_TURNS_OVER_AN_UNREAD_if_AND_AN_UNREAD_match_DO_NOT_MOVE_THE_STACK() =
    // **A DEPTH THAT DRIFTED BY ONE PER TURN WOULD OVERFLOW OR UNDERFLOW LONG BEFORE THE END**, and
    // a shorter loop would not notice a slow drift at all. The totals are what say it did not: every
    // turn reads the values the turn before it left.
    var total = 0
    var hits = 0
    var i = 0

    while i < 100000
        if i % 2 == 0
            total = total + 1
        elif i % 3 == 0
            total = total + 2

        i % 4 match
            0 -> hits = hits + 1
            1 -> hits = hits + 10
            _ -> hits = hits + 100

        try
            i = i + 1
        catch e
            i = 100000

    assertEq(i, 100000)
    assertEq(total, 83334)
    assertEq(hits, 5275000)

@test
A_catch_TAKES_A_PATTERN_AND_A_BARE_NAME_STILL_BINDS_EVERYTHING() =
    boom(m)
        throw m

    val plain = try
        boom("no")
    catch e
        e.message

    val picked = try
        boom("no")
    catch { message: "yes" }
        "wrong one"
    catch { message: "no" }
        "right one"

    assertEq(plain, "no")
    assertEq(picked, "right one")

@test
THE_catch_CLAUSES_ARE_TRIED_IN_THE_ORDER_THEY_ARE_WRITTEN() =
    boom(m)
        throw m

    look(m)
        try
            boom(m)
        catch { message: "a" }
            "first"
        catch { message: "b" }
            "second"
        catch e
            "last " + e.message

    assertEq(look("a"), "first")
    assertEq(look("b"), "second")
    assertEq(look("c"), "last c")

@test
A_catch_CLAUSE_TAKES_A_GUARD_AND_A_REFUSED_GUARD_LETS_THE_NEXT_ONE_TRY() =
    boom(m)
        throw m

    look(m)
        try
            boom(m)
        catch e if e.message == "big"
            "guarded"
        catch e
            "plain " + e.message

    assertEq(look("big"), "guarded")
    assertEq(look("small"), "plain small")

@test
A_FAULT_NO_catch_CLAUSE_WANTED_IS_THROWN_AGAIN_AND_AN_ENCLOSING_ONE_GETS_IT() =
    boom()
        throw "inner"

    val said = try
        try
            boom()
        catch { message: "other" }
            "swallowed"
    catch e
        "outer saw " + e.message

    assertEq(said, "outer saw inner")

    // And with nothing around it, it is the program's fault again -- the words kept.
    unwanted()
        try
            boom()
        catch { message: "other" }
            "swallowed"

    assertFaults(unwanted)

@test
THE_POSTFIX_catch_TAKES_A_PATTERN_AND_ONE_CLAUSE() =
    boom()
        throw "gone"

    assertEq(boom() catch { message: "gone" } -> 0, 0)
    assertEq(boom() catch e if e.message == "gone" -> 1, 1)
    assertFaults(() -> boom() catch { message: "other" } -> 0)
