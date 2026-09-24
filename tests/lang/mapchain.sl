// Integer keys in a map and a set, and calls whose answer a statement throws away -- the three
// places the interpreter now answers by a shorter road than it used to.
//
// **Each test asks the short road for the long road's answer**: a real key among the integers,
// keys a power of two apart, a call to each kind of callee as a statement.

@test
AN_INTEGER_FINDS_THE_REAL_KEY_OF_THE_SAME_VALUE() =
    val m = Map()
    val s = Set()

    m.set(2.0, "real")
    m.set(2, "int")
    s.add(5.0)
    s.add(5)

    assertEq([m.size, m.get(2), m.get(2.0), s.size, s.has(5), s.has(5.0)], [1, "int", "int", 1, true, true])

@test
KEYS_A_POWER_OF_TWO_APART_ARE_EACH_FOUND() =
    val m = Map()
    val s = Set()
    var i = 0

    while i < 500
        m.set(i * 4096, i)
        s.add(i * 65536)
        i = i + 1

    var found = 0
    var k = 0

    while k < 500
        if m.get(k * 4096) == k && s.has(k * 65536) then found = found + 1
        k = k + 1

    assertEq([found, m.size, s.size, m.has(4095), m.get(1)], [500, 500, 500, false, null])

@test
NEGATIVE_KEYS_AND_THE_ENDS_OF_AN_INTEGER_ARE_KEPT_APART() =
    val m = Map()
    var i = -10

    while i < 10
        m.set(i, i * 3)
        i = i + 1

    m.set(9223372036854775807, "top")

    assertEq([m.size, m.get(-10), m.get(-1), m.get(9), m.get(9223372036854775807), m.get(10)], [21, -30, -3, 27, "top", null])

class Counter
    var n

    bump(self) = self.n + 1

twice(x) = x * 2

@test
A_CALL_WHOSE_ANSWER_IS_THROWN_AWAY_LEAVES_NOTHING_BEHIND() =
    val m = Map()
    val o = { pick: max }
    val c = Counter(1)
    var total = 0
    var i = 0

    while i < 200
        m.set(i % 50, i)
        o.pick(i, 3)
        twice(i)
        c.bump()
        abs(i)
        total = total + i
        i = i + 1

    assertEq([total, m.size, m.get(49), m.get(0)], [19900, 50, 199, 150])

@test
A_REFUSED_CALL_AS_A_STATEMENT_IS_CAUGHT_WHERE_IT_WAS_WRITTEN() =
    val m = freeze(Map())
    var said = "nothing"

    try
        m.set(1, 2)
    catch e
        said = "refused"

    assertEq([said, m.size], ["refused", 0])
