// Sorting integers with no comparator, and integer keys in a map and a set -- the two places the
// interpreter answers an integer without the general `<` and `==`.
//
// **Each test asks the short road for the long road's answer**, beside the neighbouring case that
// still takes the long one: a real among the integers, a comparator, a class key.

class Key
    var n

    ==(self, o) = o is Key && o.n % 10 == self.n % 10
    hash(self) = self.n % 10

@test
INTEGERS_SORT_AT_THE_EDGES() =
    assertEq(sorted([]), [])
    assertEq(sorted([7]), [7])
    assertEq(sorted([3, 3, 3]), [3, 3, 3])
    assertEq(sorted([5, -2, 0, 5, -40]), [-40, -2, 0, 5, 5])

@test
MANY_INTEGERS_SORT_AND_NONE_IS_LOST() =
    val xs = []
    var i = 0

    while i < 100
        push(xs, (i * 37) % 101)
        i = i + 1

    val ys = sorted(xs)
    var ok = ys.length == 100
    var j = 1

    while j < 100
        if ys[j - 1] >= ys[j] then ok = false
        j = j + 1

    assertEq([ok, ys[0], ys[99]], [true, 0, 100])

@test
SORT_CHANGES_THE_ARRAY_AND_SORTED_DOES_NOT() =
    val xs = [3, 1, 2]
    val ys = sorted(xs)

    assertEq([xs, ys], [[3, 1, 2], [1, 2, 3]])
    xs.sort()
    assertEq(xs, [1, 2, 3])

@test
A_REAL_OR_A_COMPARATOR_STILL_TAKES_THE_GENERAL_ROAD() =
    assertEq(sorted([3, 1.5, 2]), [1.5, 2, 3])
    assertEq(sorted([1, 3, 2], (a, b) -> a > b), [3, 2, 1])

@test
INTEGER_KEYS_ARE_FOUND_IN_A_BIG_MAP() =
    val m = Map()
    var k = 0

    while k < 50
        m.set(k, k * 2)
        k = k + 1

    assertEq([m.get(10), m.has(49), m.has(50), m.get(99), m.size], [20, true, false, null, 50])
    m.set(10, 7)
    assertEq([m.get(10), m.size], [7, 50])

@test
A_SET_OF_INTEGERS_HOLDS_EACH_ONCE() =
    val s = Set()

    s.add(2)
    s.add(1)
    s.add(2)
    assertEq([s.values(), s.has(1), s.has(3)], [[2, 1], true, false])

@test
A_CLASS_KEY_STILL_DECIDES_ITS_OWN_EQUALITY_BESIDE_INTEGER_KEYS() =
    val m = Map()
    var i = 0

    while i < 30
        m.set(Key(i), i)
        i = i + 1

    m.set(3, "three")
    assertEq([m.size, m.get(Key(3)), m.has(Key(13)), m.get(3)], [11, 23, true, "three"])
