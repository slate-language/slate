// Calling a class, reading a builtin, and running a string literal -- three things a loop does on
// every turn, each of which the interpreter now answers from something it remembered.
//
// **What is remembered is never believed without a check, or cannot change**, so every test here asks
// the case where it WOULD have changed: a `new` written over, a class with its `new` somewhere else,
// a builtin's spelling bound further down the file, a literal reused after the program has made a
// great deal of garbage.

class Point
    var x
    var y

class Tagged
    var tag
    var n

    describe(self) = self.tag + string(self.n)

// An object with a `new` of its own is a constructor too, and its `new` may be written over.
makeMaker() =
    var m = { new: (v) -> { made: v } }

    m

// A table whose `new` stands at a different position from a class's.
makeLateMaker() = { a: 1, b: 2, c: 3, new: (v) -> { late: v } }

@test
A_CLASS_CONSTRUCTS_THE_SAME_WAY_EVERY_TIME() =
    var total = 0

    for i in 0..<50
        total = total + Point(i, 1).x

    assertEq(total, 1225)

@test
TWO_CLASSES_ALTERNATING_EACH_GET_THEIR_OWN_NEW() =
    var said = []

    for i in 0..<4
        if i % 2 == 0
            push(said, string(Point(i, 0).x))
        else
            push(said, Tagged("t", i).describe())

    assertEq(said, ["0", "t1", "2", "t3"])

@test
A_NEW_WRITTEN_OVER_IS_THE_ONE_THAT_ANSWERS() =
    val m = makeMaker()

    assertEq(m(1).made, 1)
    assertEq(m(2).made, 2)

    m.new = (v) -> { made: v * 10 }

    assertEq(m(3).made, 30)

@test
A_NEW_AT_ANOTHER_POSITION_IS_FOUND_THERE() =
    val early = makeMaker()
    val late = makeLateMaker()

    assertEq(early(1).made, 1)
    assertEq(late(2).late, 2)
    assertEq(early(3).made, 3)
    assertEq(late(4).late, 4)

// -- a builtin read by a file that never binds its spelling ------------------------------------------

readsNumber(s) = number(s)

// Read ABOVE the local of the same spelling below, so the read was compiled while the spelling still
// looked free and has to be put back once the local is reached.
readsString() = string(7)

bindsString() =
    val string = (v) -> "mine"

    string(1)

// And through a parameter.
readsFloor(x) = floor(x)

takesFloor(floor) = floor(2.5)

@test
A_BUILTIN_READ_IN_A_LOOP_ANSWERS_EVERY_TIME() =
    var total = 0

    for i in 0..<20
        total = total + readsNumber(string(i))

    assertEq(total, 190)

@test
A_BUILTIN_SPELLING_BOUND_ELSEWHERE_IN_THE_FILE_IS_THE_BINDING() =
    assertEq(readsString(), "7")
    assertEq(bindsString(), "mine")
    assertEq(readsFloor(2.5), 2)
    assertEq(takesFloor((x) -> "given"), "given")

@test
A_BUILTIN_TAKEN_AS_A_VALUE_IS_THE_BUILTIN() =
    val f = string

    assertEq(f(3), "3")
    assertEq([1, 2].map(string), ["1", "2"])

// -- a string literal is one cell ----------------------------------------------------------------------

@test
A_LITERAL_IN_A_LOOP_IS_THE_SAME_TEXT_EVERY_TIME() =
    var seen = []

    for i in 0..<5
        push(seen, "key")

    assertEq(seen, ["key", "key", "key", "key", "key"])
    assertEq(seen[0] == seen[4], true)

@test
BUILDING_ON_A_LITERAL_LEAVES_THE_LITERAL_AS_IT_WAS() =
    var grown = ""

    for i in 0..<3
        val base = "ab"

        grown = grown + base + "c"
        assertEq(base, "ab")
        assertEq(base.length, 2)

    assertEq(grown, "abcabcabc")

@test
A_LITERAL_SURVIVES_A_GREAT_DEAL_OF_GARBAGE() =
    var last = ""

    for i in 0..<20000
        val junk = { n: i, s: string(i) + "!" }

        last = "survivor" + junk.s[0]

    assertEq("survivor".length, 8)
    assertEq(last, "survivor1")

@test
A_LITERAL_INDEXED_FROM_TWO_PLACES_ANSWERS_BOTH() =
    var got = ""

    for i in 0..<3
        val s = "héllo"

        got = got + s[4 - i] + s[i]

    assertEq(got, "ohléll")
