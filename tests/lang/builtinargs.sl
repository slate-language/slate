// What a builtin sees of its arguments while it is running, and what is left on the stack after it.
//
// **The interpreter no longer copies a builtin's arguments anywhere.** They stay on the operand stack
// for the length of the call and are cut off once it has answered, which is what makes every question
// below worth asking: the arguments of a builtin that runs slate code are standing underneath
// whatever that code pushes, so a callback that allocates hard, recurses deep or faults is the case
// that decides whether they are still there afterwards.
//
// **Both back ends have to agree**, and the JavaScript one has no operand stack at all -- which is
// exactly why these are here rather than only in sysl: what is pinned is the ANSWER, and an answer
// that depended on where the arguments were kept would be a defect either way.

// A value whose type nobody wrote down, so a call through it reaches the run time rather than the
// checker. It is how a builtin is called with the wrong number of arguments on purpose.
anything(v) = v

// Something to burn heap with, deep enough that the collector runs inside a callback.
allocating(n) = if n == 0 then { a: 1, b: [1, 2, 3], c: "x" } else allocating(n - 1)

@test
map_SURVIVES_A_CALLBACK_THAT_ALLOCATES_AND_RECURSES() =
    // The receiver and the callback are the builtin's own arguments, standing under everything the
    // callback pushes. A recursion 400 deep grows the stack, which is what would move them if they
    // were reached through a pointer rather than an index.
    assertEq(map([1, 2, 3], x -> allocating(400).a + x), [2, 3, 4])
    assertEq(filter([1, 2, 3, 4], x -> allocating(400).a > 0 && x > 2), [3, 4])
    assertEq(reduce([1, 2, 3, 4], (a, b) -> allocating(400).a - 1 + a + b, 0), 10)

@test
sort_WITH_A_COMPARATOR_THAT_ALLOCATES_KEEPS_ITS_RECEIVER() =
    val xs = [5, 3, 4, 1, 2]

    sort(xs, (a, b) -> allocating(300).a > 0 && a < b)
    assertEq(xs, [1, 2, 3, 4, 5])

@test
A_CALLBACK_MAY_CALL_THE_SAME_BUILTIN() =
    // Re-entrancy: the outer `map`'s arguments are standing while the inner one's are pushed above
    // them, and each has to come off exactly its own.
    assertEq(map([1, 2], x -> map([x, x + 1], y -> y * 10)), [[10, 20], [20, 30]])
    assertEq(map([1, 2, 3], x -> reduce(map([x, x], y -> y + 1), (a, b) -> a + b, 0)), [4, 6, 8])

@test
A_CALLBACK_THAT_FAULTS_LEAVES_THE_STACK_BALANCED() =
    // **A one-cell drift would show up here and nowhere else.** Each turn either adds `i` or is caught
    // and adds nothing, so the total is a sum a leak of one operand per turn could not reach -- and a
    // hundred thousand turns is enough that a drift would exhaust the stack rather than be absorbed.
    var total = 0
    var caught = 0
    var i = 0

    while i < 100000
        total = total + ((map([i], x -> if x % 7 == 0 then throw "no" else x)[0]) catch e -> 0)

        if i % 7 == 0 then caught = caught + 1

        i = i + 1

    assertEq(caught, 14286)
    assertEq(total, 4285685715)

@test
A_BUILTIN_GIVEN_TOO_MANY_OR_TOO_FEW_ANSWERS_AS_IT_ALWAYS_DID() =
    // The surplus is dropped and a count that was not reached is refused, which is the call rule
    // everywhere -- and both are read off a window rather than off a list now.
    assertEq(anything(abs)(0 - 3, 99, 100), 3)
    assertEq(anything(min)(4, 2, 9, 7), 2)

    // **What the two back ends say about a builtin given too few differs and always has** -- the
    // interpreter counts the arguments and the JavaScript host reads an absent one -- so what is
    // pinned here is that it is a fault naming the builtin, and the interpreter's own sentence is
    // pinned in sysl where only one of them is running.
    val short = (anything(push)()) catch e -> e.message

    assert(short.contains("push"))

@test
A_SPREAD_CALL_OF_A_BUILTIN_ANSWERS_THE_SAME() =
    assertEq(abs(...[0 - 9]), 9)
    assertEq(min(...[5, 2, 8]), 2)
    assertEq(map(...[[1, 2], x -> x + 1]), [2, 3])

@test
A_GENERATOR_STEP_IS_A_BUILTIN_WITH_STANDING_ARGUMENTS() =
    // **`next` swaps the running machine for the generator's and back**, so its own arguments are on
    // a stack that is set aside while the body runs. Everything it needs is read before the swap.
    counting() =
        val a = yield 1
        val b = yield a + 1

        a + b

    val g = counting()

    assertEq(g.next().value, 1)
    assertEq(g.next(10).value, 11)

    val last = g.next(5)

    assertEq(last.value, 15)
    assertEq(last.done, true)

    // A finished generator answers rather than faulting, whatever it is sent.
    assertEq(g.next(99).done, true)

@test
A_PROPERTY_IS_A_BUILTIN_CALL_ON_THE_VALUE_IT_IS_READ_FROM() =
    // `length` and `size` are builtins whose only argument is the receiver, and a property read hands
    // one the value the field read is being made on. Every kind that answers either is read here,
    // inside a loop that allocates under them, so a receiver that went missing between the read and
    // the call would come back as a wrong number rather than as nothing at all.
    var total = 0
    var i = 0

    while i < 200
        val xs = [allocating(50).a, 2, 3]
        val text = "abc"
        val raw = toBytes("abcd")
        val span = 0..<5
        val members = Set([1, 2])
        val table = Map([[1, 1], [2, 2], [3, 3]])

        total = total + xs.length + text.length + raw.length + span.length + members.size + table.size
        i = i + 1

    assertEq(total, 4000)

    // A read on an expression rather than on a name, where the receiver is a value nothing else holds
    // and the answer goes back where it stood.
    assertEq([allocating(50).a, 2, 3].length + "ab".length, 5)

@test
A_PROPERTY_CALLED_AS_A_METHOD_IS_STILL_TOLD_WHICH_IT_IS() =
    // The sentence beside the read, which does not go through it: a property reached as a method is
    // named as a property rather than as something the kind cannot do.
    assertFaults(() -> anything("abc").length(), "is a property")
    assertFaults(() -> anything([1, 2]).length(), "is a property")

@test
async A_TIMER_IS_A_BUILTIN_THAT_ANSWERS_A_PROMISE() =
    // A native that arms something and hands back a handle still reads its arguments where they
    // stand, and a surplus is dropped there as anywhere else.
    val seen = []

    setTimeout(() -> push(seen, "fired"), 0)
    await sleep(5)
    assertEq(seen, ["fired"])

@test
async A_PROMISE_AWAITED_ACROSS_A_BUILTIN_CALL_KEEPS_ITS_ANSWER() =
    // `resolve` and `settle` are builtins whose argument is the value the promise carries, and the
    // await parks the machine the argument was standing on.
    val p = pending()

    settle(p, allocating(300))
    assertEq((await p).a, 1)
    assertEq(await resolve(7), 7)
