// What `xs[i]` with a local index, `.length` off a builtin kind, and a `for` over one name must
// answer, which is exactly what the general paths answer.
//
// **The interpreter reads an array at a whole number in place (`LoadSlotIndex`), answers `.length`
// off an array, a string or bytes without calling the builtin, and writes a `for`'s element straight
// into its cell (`IterNextSlot`); the JavaScript back end does none of that**, so every question here
// is asked of both hosts and the two have to agree. Each fast path has a general path behind it for
// everything it does not take, and the cases that fall through are the ones below: an index out of
// range either side, a real, a string and a range; a string and bytes as the receiver; a range's
// length, which can fault; and every kind a `for` walks.

anything(v) = v

at(xs, i) = xs[i]

// -- an index in a local ---------------------------------------------------------------------------

@test
AN_ARRAY_AT_A_WHOLE_NUMBER_INSIDE_IT_IS_THE_ELEMENT_THERE()
    val xs = [10, 20, 30]

    assertEq(at(xs, 0), 10)
    assertEq(at(xs, 2), 30)
    assertEq(at([[1, 2], [3]], 1), [3])

    // The element read over the container is a value like any other, and the sum reads both.
    sum(ys) =
        var total = 0
        var i = 0

        while i < ys.length
            total = total + ys[i]
            i = i + 1

        total

    assertEq(sum([1, 2, 3, 4]), 10)
    assertEq(sum([]), 0)

@test
AN_INDEX_OUTSIDE_AN_ARRAY_IS_REFUSED_EITHER_SIDE_OF_IT()
    assertFaults(() -> at([10, 20, 30], anything(3)), "the index 3 is outside an array of 3")
    assertFaults(() -> at([10, 20, 30], anything(-1)), "the index -1 is outside an array of 3")
    assertFaults(() -> at([], anything(0)), "the index 0 is outside an array of 0")

@test
AN_ARRAY_INDEXED_BY_SOMETHING_THAT_IS_NOT_A_WHOLE_NUMBER_TAKES_THE_GENERAL_PATH()
    assertFaults(() -> at([10, 20], anything(1.0)), "an array is indexed by an integer, and this is a real")
    assertFaults(() -> at([10, 20], anything("a")), "an array is indexed by an integer, and this is a string")

    // A range is a slice, and it is read the general way.
    assertEq(at([10, 20, 30, 40], 1..<3), [20, 30])
    assertEq(at([10, 20, 30, 40], 2..), [30, 40])

@test
A_STRING_AND_BYTES_INDEXED_BY_A_LOCAL_ANSWER_WHAT_THEY_ALWAYS_DID()
    assertEq(at("añb", 1), "ñ")
    assertEq(at("añb", 2), "b")
    assertEq(at(toBytes("hi"), 1), 105)

// -- `.length` ---------------------------------------------------------------------------------------

@test
LENGTH_OFF_AN_ARRAY_A_STRING_AND_BYTES_IS_THE_NUMBER_THE_VALUE_CARRIES()
    assertEq(anything([1, 2, 3]).length, 3)
    assertEq(anything([]).length, 0)

    // Characters for a string, bytes for bytes.
    assertEq(anything("日本語").length, 3)
    assertEq(anything(toBytes("日本")).length, 6)

    // A range takes the general path, and one with an end left out has no length.
    assertEq(anything(0..<4).length, 4)
    assertFaults(() -> anything(0..).length, "has no length until it is used on something")

@test
A_NAME_OTHER_THAN_LENGTH_OFF_AN_ARRAY_IS_STILL_WHAT_IT_WAS()
    assertFaults(() -> anything([1]).nope, "`nope` is not something an array can do")
    assertFaults(() -> anything("s").nope, "`nope` is not something a string can do")

    // A method read off one is the function, and called it does what it always did.
    val xs = [1]
    val push = xs.push

    push(xs, 2)
    assertEq(xs, [1, 2])

// -- a `for` over one name ------------------------------------------------------------------------

walk(v) =
    val got = []

    for x in v
        got.push(x)

    got

@test
A_FOR_OVER_ONE_NAME_WALKS_EVERY_KIND_IT_ALWAYS_WALKED()
    assertEq(walk([1, 2, 3]), [1, 2, 3])
    assertEq(walk([]), [])
    assertEq(walk(0..<3), [0, 1, 2])
    assertEq(walk(3..1 by -1), [3, 2, 1])
    assertEq(walk("añ"), ["a", "ñ"])
    assertEq(walk(toBytes("hi")), [104, 105])
    assertEq(walk(Set([1, 2])), [1, 2])
    assertEq(walk(Map([["a", 1]])), [["a", 1]])

    counting() =
        yield 1
        yield 2

    assertEq(walk(counting()), [1, 2])

@test
A_FOR_THAT_TAKES_THE_ELEMENT_APART_STILL_WALKS_IT()
    pairs(v) =
        val got = []

        for [a, b] in v
            got.push(a + b)

        got

    assertEq(pairs([[1, 2], [3, 4]]), [3, 7])

// **Both hosts refuse in ONE sentence**, each at the head of the walk.
@test
A_FOR_OVER_SOMETHING_THAT_CANNOT_BE_WALKED_IS_REFUSED()
    assertFaults(() -> walk(anything(42)), "`for` walks an array, bytes, a string, a range, a generator, a set or a map, and this is an integer")
    assertFaults(() -> walk(anything(0..)), "`for` needs a range with both ends, since one left out would never finish")

@test
A_BREAK_AND_A_NESTED_FOR_LEAVE_THE_WALK_WHERE_IT_WAS()
    firstOver(v, n) =
        for x in v
            if x > n then return x

        null

    assertEq(firstOver([1, 5, 9], 4), 5)
    assertEq(firstOver([1, 2], 4), null)

    grid() =
        val got = []

        for row in [[1, 2], [3]]
            for x in row
                got.push(x * 10)

        got

    assertEq(grid(), [10, 20, 30])
