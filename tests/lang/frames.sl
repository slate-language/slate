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
    scaled(n, by, all) = n * by * all.length

    assertEq(map([1, 2, 3], scaled), [0, 6, 18])

    // **A DEFAULTED PARAMETER STANDING WHERE THE WALK SUPPLIES SOMETHING IS GIVEN THAT**, which is
    // what JavaScript does and is worth writing down: `map` hands over the element, its position and
    // the array, so `by` is the index here and not `2`. The default is still what a shorter call
    // leaves it.
    twice(n, by = 2) = n * by

    assertEq(map([1, 2, 3], twice), [0, 2, 6])
    assertEq(twice(4), 8)

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

        name + string(count) + string(head) + string(rest.length)

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

@test
AN_INNER_SCOPE_BINDING_SHADOWS_AN_OUTER_CELL()
    // **A chunk can hold both kinds of binding now**, and the two have to obey one shadowing rule.
    // The loop head binds `a` and `b`; `b` is read by a closure so the pair goes into the scope,
    // while the outer `a` is a cell. A lookup that stopped only at cells would walk past the loop's
    // `a` and read `100` on every turn -- and every assertion here would still be about a number.
    count(pairs) =
        var seen = 0
        val a = 100

        for [a, b] in pairs
            val note = () -> b

            seen = seen + a + note()

        seen + a

    assertEq(count([[1, 2], [3, 4]]), 110)
    assertEq(count([]), 100)

@test
A_CLOSURE_STILL_SEES_A_NAME_ITS_NEIGHBOURS_KEPT_IN_CELLS()
    // The name a closure reads stays in the scope and the ones it cannot reach move into the frame,
    // so this is the case where a wrong analysis reads one binding out of the other's home.
    tally(n) =
        var total = 0
        var turns = 0
        val scale = n
        val weigh = (v) -> v * scale

        while turns < 4
            total = total + weigh(turns)
            turns = turns + 1

        total

    assertEq(tally(3), 18)
    assertEq(tally(0), 0)

    // Two calls, so a cell that outlived its frame would show up as the first call's total.
    assertEq(tally(1), 6)

@test
A_CLOSURE_MADE_IN_A_LOOP_SEES_THE_TURN_IT_WAS_MADE_ON()
    // Each turn's block is its own scope, so the closure a turn made reads that turn's binding --
    // which is what `let` means in JavaScript and what slate has always answered.
    made(xs) =
        var out = []
        var kept = 0

        for x in xs
            push(out, () -> x + kept)

        kept = 10
        map(out, (f) -> f())

    assertEq(made([1, 2, 3]), [11, 12, 13])

// -- where a call's arguments actually go ----------------------------------------------------------
//
// **An ordinary positional call leaves its arguments standing on the operand stack**, at the very
// cells the callee's frame begins at, so nothing is copied out of the stack and nothing is copied
// back onto it. Each shape below is a way that could be wrong while an ordinary call still looked
// right: a receiver that is parameter zero, a receiver that is not one at all, a surplus with nowhere
// to go, an argument list the names rearrange, and a fault that has to leave the caller's stack where
// the caller left it.

// A value whose type nobody wrote down, so a call through it reaches the machine rather than the
// checker.
loosely(v) = v

shared(a, b) = a * 10 + b

class Tally
    var n = 0

    // Reached through the class, which is a proto of the instance -- so the object is handed over as
    // parameter zero.
    add(self, by, again = 0) = self.n + by + again

class Holder
    // A function stored on the instance itself, which takes no receiver: it has already captured
    // whatever it needs, there being one of it per instance.
    var run = shared

@test
A_METHOD_REACHED_THROUGH_ITS_CLASS_IS_HANDED_THE_OBJECT_AS_PARAMETER_ZERO()
    val t = Tally.new(5)

    assertEq(t.add(1), 6)
    assertEq(t.add(1, 2), 8)

    // A surplus through a method is dropped exactly as it is through a plain call, and the receiver
    // is still where the callee expects it afterwards.
    assertEq(loosely(t).add(1, 2, 99), 8)
    assertEq(t.add(1), 6)

@test
A_FUNCTION_AN_OBJECT_CARRIES_ITSELF_IS_CALLED_WITHOUT_THE_OBJECT()
    val h = Holder.new()

    assertEq(h.run(1, 2), 12)

    // The same function reached as a plain name answers the same, which is what says the object was
    // not quietly pushed in front of the arguments.
    assertEq(shared(1, 2), 12)

@test
A_CONSTRUCTOR_CALL_IS_AN_ORDINARY_CALL_OF_THE_GENERATED_new()
    assertEq(Tally.new(7).n, 7)
    assertEq(Tally(7).n, 7)
    assertEq(Tally().n, 0)

@test
A_CONTRACT_READS_THE_ARGUMENTS_THE_CALL_ACTUALLY_PUT_DOWN()
    stepped(n, by = 1)
        require n > 0
        ensure result >= 0

        n - by

    assertEq(stepped(5), 4)
    assertEq(stepped(5, 2), 3)
    assertEq((stepped(0)) catch e -> e.message, "`stepped` requires `n > 0`, and this call does not meet it")
    assertEq((stepped(1, 9)) catch e -> e.message, "`stepped` ensures `result >= 0`, and gave back -8")

    // The frame still works after a clause refused one, which is what says the stack was cut back to
    // the right cell.
    assertEq(stepped(5), 4)

@test
NAMED_POSITIONAL_AND_SPREAD_CALLS_OF_ONE_FUNCTION_ALL_AGREE()
    three(a, b = 2, c = 3) = [a, b, c]

    assertEq(three(1), [1, 2, 3])
    assertEq(three(1, 9), [1, 9, 3])
    assertEq(three(1, c = 9), [1, 2, 9])
    assertEq(three(...[1, 9, 8]), [1, 9, 8])
    assertEq(three(...[4]), [4, 2, 3])

    // Interleaved, so a path that left the stack one cell out would show up on the call after it
    // rather than on its own.
    assertEq([three(1), three(1, c = 9), three(...[4]), three(5, 6)], [[1, 2, 3], [1, 2, 9], [4, 2, 3], [5, 6, 3]])

@test
A_FAULT_INSIDE_A_CALLEE_LEAVES_THE_CALLERS_STACK_WHERE_IT_WAS()
    // The caller is part way through an expression when the callee fails, so what it has already
    // computed is standing on the stack and the `catch` has to cut back past all of it.
    blows(n)
        if n > 2
            throw "too big"

        n

    tryish(n)
        var seen = 0

        try
            seen = 1 + blows(n) + blows(n + 1) + blows(n + 2)
        catch e
            seen = -1

        seen

    assertEq(tryish(0), 4)
    assertEq(tryish(1), -1)
    assertEq(tryish(5), -1)

    // And the frame still answers afterwards, which is what says the cut landed on the right cell.
    assertEq(tryish(0), 4)

@test
A_DEEP_RECURSION_UNWINDS_TO_EXACTLY_WHERE_IT_STARTED()
    descend(n, acc = 0) = if n == 0 then acc else descend(n - 1, acc + n)

    assertEq(descend(500), 125250)
    assertEq(descend(1), 1)
    assertEq(descend(500), 125250)

// -- a construction is a call, and its callee is not the thing that runs ---------------------------
//
// **`Boxed(3)` is an object carrying a `new`**, so a construction is the one call whose callee is not
// what runs: the hook is looked up first and then called with the arguments exactly as they were
// written, being handed no receiver -- the object it is about to make does not exist yet. Every shape
// a `new` comes in is below, because what a construction MEANS may not depend on how its arguments
// reached the frame.

class Boxed
    var w
    var h = w + 1
    var label = "box"

class Crate
    // A hand-written `new` of the plain form: the body's value is the object, and the class becomes
    // its proto on the way out.
    new(v, extra = 2) = { v: v, extra: extra }

class Warmth
    // The other hand-written form, which declares its field in the head and runs its body with `self`
    // bound to what is being made.
    new(var degrees) =
        self.warm = degrees > 20

class Parent
    var kind = "parent"

class Child from Parent
    var side = 1

data Tint
    Solid(r)
    Duo(a, b)
    Plain

@test
A_GENERATED_new_TAKES_EVERY_FIELD_AND_FILLS_THE_REST_FROM_THEIR_INITIALISERS()
    assertEq([Boxed(3).w, Boxed(3).h, Boxed(3).label], [3, 4, "box"])
    assertEq([Boxed(3, 9).h, Boxed(3, 9, "hat").label], [9, "hat"])

@test
A_FIELDS_INITIALISER_IS_A_DEFAULT_AND_READS_THE_FIELDS_TO_ITS_LEFT()
    // `h = w + 1` is `new`'s default for `h`, so it is worked out at the construction and reads
    // whatever arrived for `w` -- once per object, and not at all where `h` was given.
    assertEq([Boxed(1).h, Boxed(10).h, Boxed(10, 0).h], [2, 11, 0])

@test
A_CONSTRUCTION_DROPS_A_SURPLUS_AND_LEAVES_WHAT_NOBODY_GAVE_ABSENT()
    // Through a value the checker cannot see into, so both ends of the count reach the machine.
    assertEq(loosely(Boxed)(3, 9, "hat", 77).label, "hat")
    assertEq((loosely(Boxed)()) catch e -> e.message, "`+` does not apply to undefined and an integer")

    // And the construction after the refused one still answers, which is what says the stack was cut
    // back to the right cell.
    assertEq(Boxed(3).h, 4)

@test
A_HAND_WRITTEN_new_IS_ENTERED_THE_WAY_THE_GENERATED_ONE_IS()
    assertEq([Crate(1).v, Crate(1).extra, Crate(1, 5).extra], [1, 2, 5])
    assertEq(Crate(1) is Crate, true)
    assertEq([Warmth(30).degrees, Warmth(30).warm, Warmth(3).warm], [30, true, false])

@test
A_DATA_VARIANTS_MAKER_IS_A_CONSTRUCTION_TOO()
    assertEq([Solid(2).r, Duo(1, 2).a, Duo(1, 2).b], [2, 1, 2])
    assertEq([Solid(2) is Tint, Plain is Tint], [true, true])

@test
A_SUBCLASS_IS_MADE_BY_ITS_OWN_new_AND_IS_STILL_THE_PARENT()
    val c = Child(4)

    assertEq(c.side, 4)
    assertEq([c is Child, c is Parent], [true, true])

@test
NAMED_POSITIONAL_AND_SPREAD_CONSTRUCTIONS_OF_ONE_CLASS_ALL_AGREE()
    // A name leaves a hole in the MIDDLE, so `h` is filled by its initialiser while `label` is filled
    // by the call -- which is the case a count of how many arrived could not answer.
    assertEq([Boxed(1).label, Boxed(1, label = "hat").label], ["box", "hat"])
    assertEq([Boxed(1).h, Boxed(1, label = "hat").h, Boxed(...[1, 5]).h, Boxed(2, 7).h], [2, 2, 5, 7])
    assertEq(Boxed(...[1, 5, "hat"]).label, "hat")

@test
A_CONSTRUCTION_DEEP_IN_A_RECURSION_IS_STILL_A_CONSTRUCTION()
    // How deep a call has got is read where the frame is made, so a construction has to be counted
    // exactly as the calls around it are.
    deep(n) = if n == 0 then Boxed(1).h else deep(n - 1)

    assertEq(deep(1), 2)
    assertEq(deep(2000), 2)
