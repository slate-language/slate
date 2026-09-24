// What a FUSED PAIR of instructions must answer, which is exactly what the two answered apart.
//
// **The interpreter runs four superinstructions and the JavaScript back end runs none**, so every
// question here is asked of both hosts and the two have to agree. That is what makes this file the
// check on the fusion rather than a description of it: `slate js` compiles from the tree and knows
// nothing about `LoadSlot2`, `LoadSlotInt`, `AddStoreSlot` or `LessJumpIfFalse`.
//
// The four pairs, and what each one has to keep true:
//
// - `LoadSlot`+`LoadSlot` and `LoadSlot`+`PushInt` push two values in order and nothing else;
// - `Add`+`StoreSlot` writes a whole-number sum straight into the cell and still promotes an
//   overflow, still joins two strings, still runs a class's own `+`, and still refuses an absence;
// - `Less`+`JumpIfFalse` compares whole numbers in place and still orders strings, still promotes,
//   and still faults on a pair that has no order.
//
// **AND A JUMP MAY LAND ON THE SECOND INSTRUCTION OF A PAIR**, which is what the short-circuit tests
// at the foot of this file are for: `a || b` jumps over `b` to whatever follows the expression, and
// where that is a load the emitter has already folded the load before it, the target sits INSIDE a
// fused group. The emitter leaves that instruction standing for exactly this reason.

// -- two loads, and a load and a literal ----------------------------------------------------------

sum3(a, b, c) = a + b + c

scaled(a, b) = a * b + 1

// A class whose `+` is its own, so that the general arithmetic is reached from the very instruction
// that folded the store. A class belongs to a file's top level, its name being a type.
class Money
    var amount

    +(self, o) = Money(self.amount + o.amount)

@test
TWO_LOADS_RUN_AS_ONE_PUSH_THE_SAME_TWO_VALUES_IN_THE_SAME_ORDER()
    assertEq(sum3(1, 2, 3), 6)
    assertEq(sum3(10, 200, 3000), 3210)

    // Order matters and subtraction is what says so: a pair pushed the wrong way round is invisible
    // to an addition.
    minus(a, b) = a - b

    assertEq(minus(10, 3), 7)
    assertEq(minus(3, 10), -7)

    // Three in a row, where the scan folds the first two and leaves the third alone.
    three(a, b, c) = [a, b, c]

    assertEq(three(1, 2, 3), [1, 2, 3])

@test
A_LOAD_AND_A_LITERAL_RUN_AS_ONE_PUSH_THE_LOCAL_THEN_THE_LITERAL()
    assertEq(scaled(6, 7), 43)

    // The literal is the RIGHT operand, so a pair pushed the wrong way round changes the answer.
    less1(n) = n - 1
    from1(n) = 1 - n

    assertEq(less1(10), 9)
    assertEq(from1(10), -9)

// -- a sum written straight into a local ----------------------------------------------------------

counted(n)
    var t = 0
    var i = 0

    while i < n
        t = t + i
        i = i + 1

    t

@test
A_SUM_STORED_INTO_A_LOCAL_COUNTS_WHAT_THE_UNFUSED_PAIR_COUNTED()
    assertEq(counted(0), 0)
    assertEq(counted(1), 0)
    assertEq(counted(10), 45)
    assertEq(counted(100), 4950)

@test
A_SUM_STORED_INTO_A_LOCAL_STILL_PROMOTES_AN_OVERFLOW()
    // The fast path is two machine integers whose sum fits. This one does not, so the fused arm has
    // to hand the pair to the very arithmetic the unfused one handed it to.
    var n = 9223372036854775807

    n = n + 1
    assertEq(string(n), "9223372036854775808")

    var m = -9223372036854775807

    m = m + -2
    assertEq(string(m), "-9223372036854775809")

@test
A_SUM_STORED_INTO_A_LOCAL_STILL_JOINS_TWO_STRINGS_AND_ADDS_TWO_REALS()
    var s = "a"

    s = s + "b"
    s = s + "c"
    assertEq(s, "abc")

    var r = 0.5

    r = r + 0.25
    assertEq(r, 0.75)

@test
A_SUM_STORED_INTO_A_LOCAL_STILL_RUNS_A_CLASS_OWN_OPERATOR()
    var m = Money(3)

    m = m + Money(4)
    assertEq(m.amount, 7)

@test
A_SUM_STORED_INTO_A_LOCAL_STILL_REFUSES_WHAT_IS_NOT_A_NUMBER()
    var n = 1
    var said = ""

    try
        n = n + {}
    catch e
        said = e.message

    assert(said != "", "adding an object to a number was allowed")
    assertEq(n, 1)

// -- a comparison that decides a jump -------------------------------------------------------------

@test
A_COMPARISON_THAT_DECIDES_A_JUMP_STILL_ORDERS_WHOLE_NUMBERS()
    upTo(n)
        var seen = []
        var i = 0

        while i < n
            push(seen, i)
            i = i + 1

        seen

    assertEq(upTo(0), [])
    assertEq(upTo(3), [0, 1, 2])

    // The boundary the fused arm computes itself: `i < n` is false exactly at `n`.
    atMost(a, b) = if a < b then "less" else "not less"

    assertEq(atMost(1, 2), "less")
    assertEq(atMost(2, 2), "not less")
    assertEq(atMost(3, 2), "not less")
    assertEq(atMost(-1, 0), "less")

@test
A_COMPARISON_THAT_DECIDES_A_JUMP_STILL_ORDERS_STRINGS_AND_REALS()
    atMost(a, b) = if a < b then "less" else "not less"

    assertEq(atMost("a", "b"), "less")
    assertEq(atMost("b", "a"), "not less")
    assertEq(atMost(1.5, 2), "less")
    assertEq(atMost(2, 1.5), "not less")

@test
A_COMPARISON_THAT_DECIDES_A_JUMP_STILL_FAULTS_ON_A_PAIR_WITH_NO_ORDER()
    var answer = "not reached"
    var message = ""

    try
        if {} < 1
            answer = "took"
        else
            answer = "missed"
    catch e
        message = e.message

    assert(message != "", "comparing an object with a number was allowed")
    assertEq(answer, "not reached")

// -- a jump that lands inside a fused pair ---------------------------------------------------------

// `a || b` leaves `a` where `a` is truthy and jumps over `b` to whatever follows -- and what follows
// here is a load of `d`, which the emitter has already folded onto the load of `c` before it. So the
// jump's target is the SECOND instruction of a fused pair, and the only reason it still works is
// that the emitter left that instruction where it was.
shortCircuit(a, c, d) = (a || c) + d

@test
A_JUMP_MAY_LAND_ON_THE_SECOND_INSTRUCTION_OF_A_FUSED_PAIR()
    // The jump is TAKEN: `a` is truthy, so `c` is skipped and execution resumes inside the group.
    assertEq(shortCircuit(1, 99, 5), 6)
    assertEq(shortCircuit(7, 99, 5), 12)

    // And not taken, which is the ordinary fall-through through the whole group.
    assertEq(shortCircuit(0, 4, 5), 9)
    assertEq(shortCircuit(false, 4, 5), 9)

@test
A_GUARD_THAT_SKIPS_A_LOAD_LEAVES_THE_STACK_WHERE_THE_UNFUSED_CODE_LEFT_IT()
    // `??` is the other jump that keeps its operand, and a stack left one value deep or one value
    // short by a fused pair shows up as a wrong answer here rather than as a fault.
    pick(o, d) = (o.missing ?? d) + 1

    assertEq(pick({ a: 1 }, 10), 11)
    assertEq(pick({ missing: 4 }, 10), 5)

// -- a second line of execution, stepped from inside a folded loop ---------------------------------

// **A GENERATOR IS A SECOND OPERAND STACK, AND THE DRIVER'S FOLDED LOOP RUNS ON THE FIRST.** Stepping
// one sets the generator's line of execution running and then puts the driver's back, so every turn
// of the loop below crosses that boundary twice with fused instructions on both sides of it. A value
// taken off the wrong stack is a wrong answer rather than a fault, which is why these assert sums and
// orders rather than merely that nothing went wrong.

countingUp(limit) =
    var i = 0

    while i < limit
        yield i * 2
        i = i + 1

@test
A_GENERATOR_STEPPED_FROM_A_FOLDED_LOOP_ANSWERS_EVERY_VALUE_IN_ORDER()
    val g = countingUp(8)

    var total = 0
    var k = 0

    val seen = []

    while k < 8
        val step = g.next()

        total = total + step.value
        seen.push(step.value)
        k = k + 1

    assertEq(total, 56)
    assertEq(seen, [0, 2, 4, 6, 8, 10, 12, 14])
    assertEq(g.next().done, true)

@test
TWO_GENERATORS_INTERLEAVED_IN_ONE_FOLDED_LOOP_KEEP_THEIR_OWN_COUNTERS()
    // Three lines of execution, two of them parked at any moment. A driver that read a value off
    // whichever stack happened to be installed would answer the same number twice here.
    val a = countingUp(5)
    val b = countingUp(5)

    var k = 0

    val mixed = []

    while k < 5
        mixed.push(a.next().value)
        mixed.push(b.next().value + 1)
        k = k + 1

    assertEq(mixed, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

// -- a difference stored into a local, and a loop's whole head and tail --------------------------
//
// **`Sub`+`StoreSlot` is `Add`+`StoreSlot`'s twin**, and the two RUNS fold a counted loop: its head
// `Tick; LoadSlot; PushInt; Less; JumpIfFalse`, and its tail `LoadSlot; PushInt; Add; StoreSlot;
// Jump` where the slot read and written is the same one. Each has a whole-number path and hands
// everything else to the arithmetic the unfused run used.

countedDown(n)
    var t = 100
    var i = 0

    while i < n
        t = t - i
        i = i + 1

    t

@test
A_DIFFERENCE_STORED_INTO_A_LOCAL_COUNTS_WHAT_THE_UNFUSED_PAIR_COUNTED()
    assertEq(countedDown(0), 100)
    assertEq(countedDown(5), 90)

    // The minuend is the LEFT operand, which a pair popped the wrong way round would swap.
    var d = 3

    d = d - 10
    assertEq(d, -7)

@test
A_DIFFERENCE_STORED_INTO_A_LOCAL_STILL_PROMOTES_AN_OVERFLOW_AND_SUBTRACTS_REALS()
    var n = -9223372036854775807

    n = n - 2
    assertEq(string(n), "-9223372036854775809")

    var r = 1.0

    r = r - 0.25
    assertEq(r, 0.75)

@test
A_DIFFERENCE_STORED_INTO_A_LOCAL_STILL_REFUSES_WHAT_IS_NOT_A_NUMBER()
    var n = 1
    var said = ""

    try
        n = n - {}
    catch e
        said = e.message

    assert(said != "", "subtracting an object from a number was allowed")
    assertEq(n, 1)

@test
A_COUNTED_LOOP_RUNS_EXACTLY_ITS_TURNS_WHATEVER_ITS_STEP()
    var turns = 0
    var i = 0

    while i < 10
        turns = turns + 1
        i = i + 3

    assertEq(turns, 4)
    assertEq(i, 12)

    // A loop that never turns leaves its counter where it was.
    var j = 5

    while j < 5
        j = j + 1

    assertEq(j, 5)

    // A negative step and a negative bound.
    var k = 0
    var down = 0

    while k < -1
        down = down + 1

    assertEq(down, 0)

@test
A_LOOP_OVER_A_REAL_COUNTER_TAKES_THE_ORDINARY_ARITHMETIC()
    // Neither half of the loop holds a whole number here, so both runs take their slow paths.
    var x = 0.5
    var turns = 0

    while x < 3
        turns = turns + 1
        x = x + 1

    assertEq(turns, 3)
    assertEq(x, 3.5)

@test
A_LOOP_WHOSE_COUNTER_OVERFLOWS_PROMOTES_IT()
    var i = 9223372036854775806
    var turns = 0

    while turns < 3
        turns = turns + 1
        i = i + 1

    assertEq(string(i), "9223372036854775809")

@test
A_LOOP_HEAD_OVER_SOMETHING_WITH_NO_ORDER_STILL_FAULTS()
    var i = {}
    var said = ""

    try
        while i < 3
            i = 4
    catch e
        said = e.message

    assert(said != "", "comparing an object with a number was allowed")

@test
A_LOOP_TAIL_OVER_A_STRING_STILL_REFUSES_AN_INTEGER()
    // The tail's slow path is the ordinary addition, so it says what the ordinary addition says.
    var s = "a"
    var said = ""

    try
        while s != "done"
            s = s + 1
    catch e
        said = e.message

    assertEq(said, "`+` does not apply to a string and an integer")
    assertEq(s, "a")

@test
A_BREAK_AND_A_CONTINUE_LEAVE_A_FOLDED_LOOP_WHERE_THE_UNFUSED_ONE_LEFT_IT()
    var seen = []
    var i = 0

    while i < 10
        i = i + 1

        if i % 2 == 0 then continue
        if i > 7 then break

        seen.push(i)

    assertEq(seen, [1, 3, 5, 7])

// -- a local's field, a product summed, an arm's test, a module variable and a remainder, each
// -- folded; and an equality before a jump and a walk's head, each left as it was --

class Point
    var x
    var y

    dot(self, o) = self.x * o.x + self.y * o.y

var ticked = 0

bumped(k) =
    ticked = ticked + 1
    ticked + k

shape(v) = v match
    [a, b] -> a + b
    { name } -> name
    _ -> "other"

negated(v) = -v

down(n, z) = if n == z then 0 else down(n - 1, z) + 1

@test
A_LOCALS_FIELD_READ_AS_ONE_ANSWERS_AND_REFUSES_AS_TWO()
    val p = Point(2, 3)
    val q = Point(5, 7)

    assertEq(p.dot(q), 31)
    assertEq(p.x + q.y, 9)

    var said = ""

    try
        val n = anything(4)
        said = string(n.nope)
    catch e
        said = e.message

    assert(said != "" && said != "undefined", "a missing field on a number was read")

@test
A_PRODUCT_SUMMED_AS_ONE_PROMOTES_AND_MIXES_AS_TWO()
    val a = 4611686018427387904
    val b = 2
    val c = 1

    assertEq(string(c + a * b), "9223372036854775809")
    assertEq(c + 3 * 4, 13)

    val r = 0.5

    assertEq(r + 2 * 3, 6.5)
    assertEq(1 + r * 4, 3.0)

    val big = 9223372036854775807

    assertEq(string(big + 1 * 1), "9223372036854775808")

@test
A_MATCH_ARM_TESTED_AS_ONE_PICKS_THE_SAME_ARM()
    assertEq(shape([1, 2]), 3)
    assertEq(shape({ name: "n" }), "n")
    assertEq(shape([1, 2, 3]), "other")
    assertEq(shape(5), "other")

@test
A_MODULE_VARIABLE_AND_A_LITERAL_READ_AS_ONE_SEE_EVERY_WRITE()
    ticked = 0

    assertEq(bumped(10), 11)
    assertEq(bumped(10), 12)
    assertEq(ticked + 100, 102)

@test
A_REMAINDER_BY_A_LITERAL_AS_ONE_TRUNCATES_PROMOTES_AND_REFUSES_AS_TWO()
    var odd = 0

    for i in 0..<9
        if i % 2 == 1
            odd = odd + 1

    assertEq(odd, 4)

    val n = -7
    val r = 7.5

    assertEq(n % 3, -1)

    var real_said = ""

    try
        real_said = string(r % 3)
    catch e
        real_said = e.message

    assertEq(real_said, "a remainder is taken of integers")

    var said = ""

    try
        val m = 7
        said = string(m % 0)
    catch e
        said = e.message

    assert(said != "", "a remainder by zero was answered")

@test
AN_EQUALITY_BEFORE_A_JUMP_ANSWERS_FOR_EVERY_KIND()
    val pairs = [[1, 1], [1, 1.0], ["x", "x"], [[1], [1]], [1, "1"], [null, null]]
    var same = []

    for [a, b] in pairs
        if a == b
            same.push(true)
        else
            same.push(false)

    assertEq(same, [true, true, true, true, false, true])

@test
A_WALK_OVER_EVERY_KIND_AND_A_RECURSION_ANSWER_ON_BOTH_HOSTS()
    var t = 0

    for x in [1, 2, 3]
        t = t + x

    for x in 0..<4
        t = t + x

    var chars = ""

    for c in "abc"
        chars = chars + c

    var keys = 0

    for [k, v] in Map([["a", 1], ["b", 2]])
        keys = keys + v

    assertEq(t, 12)
    assertEq(chars, "abc")
    assertEq(keys, 3)
    assertEq(negated(4), -4)
    assertEq(down(200, 0), 200)

    var said = ""

    try
        val five = anything(5)

        for x in five
            t = t + 1
    catch e
        said = e.message

    // The two hosts word it differently; what both owe is the refusal.
    assert(said != "", "a `for` over a number walked")

anything(v) = v
