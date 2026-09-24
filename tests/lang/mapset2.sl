// A method call answered from what its site remembers, and a local in front of a remainder taken in
// one step -- the two shorter roads `bench/mapset.sl` runs, each asked for the long road's answer.

hasIt(x, k) = x.has(k)

@test
ONE_SITE_ANSWERS_A_MAP_A_SET_AN_OBJECT_AND_A_MAP_AGAIN() =
    val m = Map()
    val s = Set()
    val o = { has: k -> "own" }

    m.set(1, 2)
    s.add(3)

    assertEq([hasIt(m, 1), hasIt(s, 1), hasIt(o, 1), hasIt(m, 5), hasIt(s, 3), hasIt(m, 1)], [true, false, "own", false, true, true])

@test
EVERY_KIND_OF_KEY_THROUGH_ONE_SITE() =
    val m = Map()
    val keys = [1, 1.0, "a", { x: 1 }, { x: 1 }, [1, 2], -1]
    var i = 0

    while i < keys.length
        m.set(keys[i], i)
        i = i + 1

    assertEq([m.size, m.get(1), m.get("a"), m.get({ x: 1 }), m.get([1, 2]), m.get(-1), m.get(2)], [5, 1, 2, 4, 5, 6, null])

@test
A_MAP_THAT_GROWS_MID_LOOP_KEEPS_EVERY_KEY() =
    val m = Map()
    val s = Set()
    var i = 0

    while i < 9000
        m.set(i % 3000, i)
        s.add(i % 3000)
        i = i + 1

    assertEq([m.size, s.size, m.get(0), m.get(2999), s.has(2999), s.has(3000)], [3000, 3000, 6000, 8999, true, false])

pairAt(c, a, i) = [c && a, i % 3]

@test
A_JUMP_INTO_A_REMAINDER_RUN_ANSWERS_AS_IF_UNFOLDED() =
    assertEq([pairAt(false, 9, 7), pairAt(true, 9, 8)], [[false, 1], [9, 2]])

halfOf(m, x) = [m, x % 2]

@test
A_FOLDED_REMAINDER_OF_A_NEGATIVE_TRUNCATES_TOWARD_ZERO() =
    assertEq([halfOf(0, -7), halfOf("m", 9)], [[0, -1], ["m", 1]])
