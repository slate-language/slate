// An object of up to three entries keeps them in its own cell, and the entry that does not fit moves
// the whole table out into a buffer. What these pin is that nothing a program can see depends on
// which side of that line an object is on: order, lookups, equality, hashing, `with`, `without`,
// removing and re-adding, JSON, a class, a data value, a weak map and a map keyed by one.

upTo(n) =
    val o = {}

    for i in 0..<n
        o[s"k${i}"] = i

    o

class Two
    var a
    var b

class Four
    var a
    var b
    var c
    var d

data Pair
    Both(left, right)
    Widened(a, b, c, d)

@test
EVERY_SIZE_FROM_EMPTY_TO_SEVEN_KEEPS_ITS_ORDER_AND_ANSWERS_EVERY_LOOKUP() =
    for n in 0..<8
        val o = upTo(n)

        assertEq(keys(o).length, n)

        for i in 0..<n
            assertEq(keys(o)[i], s"k${i}")
            assertEq(values(o)[i], i)
            assertEq(entries(o)[i], [s"k${i}", i])
            assertEq(o[s"k${i}"], i)

        assert(!has(o, s"k${n}"))

@test
A_WRITE_TO_AN_EXISTING_FIELD_LANDS_ON_EITHER_SIDE_OF_THE_LINE() =
    var small = upTo(3)
    var big = upTo(5)

    small.k2 = 20
    big.k2 = 20
    big.k4 = 40

    assertEq(values(small), [0, 1, 20])
    assertEq(values(big), [0, 1, 20, 3, 40])

@test
WITH_CROSSES_THE_LINE_AND_WITHOUT_BRINGS_IT_BACK() =
    val grown = upTo(3) with { k3: 3 }

    assertEq(grown, upTo(4))
    assertEq(keys(grown), ["k0", "k1", "k2", "k3"])

    val shrunk = without(grown, "k3")

    assertEq(shrunk, upTo(3))
    assertEq(keys(shrunk), keys(upTo(3)))
    assertEq(without(upTo(6), "k0"), { k1: 1, k2: 2, k3: 3, k4: 4, k5: 5 })

@test
A_FIELD_REMOVED_AND_WRITTEN_AGAIN_GOES_TO_THE_END_ON_BOTH_SIDES() =
    for n in [2, 3, 4, 9]
        var o = upTo(n)

        o = without(o, "k0")
        o = o with { k0: 0 }

        assertEq(keys(o)[n - 1], "k0")
        assertEq(keys(o).length, n)
        assertEq(o, upTo(n))

@test
EQUALITY_AND_HASHING_DO_NOT_SEE_THE_LINE() =
    assertEq(upTo(3), { k2: 2, k1: 1, k0: 0 })
    assertEq(upTo(4), { k3: 3, k2: 2, k1: 1, k0: 0 })
    assert(upTo(3) != upTo(4))
    assert(upTo(4) != upTo(3))

    val s = Set([upTo(3), upTo(4), upTo(6)])

    assert(s.has({ k2: 2, k1: 1, k0: 0 }))
    assert(s.has({ k3: 3, k0: 0, k1: 1, k2: 2 }))
    assert(s.has(upTo(6)))
    assert(!s.has(upTo(5)))

    val m = Map([[upTo(2), "two"], [upTo(5), "five"]])

    assertEq(m.get(upTo(2)), "two")
    assertEq(m.get(upTo(5)), "five")

@test
A_CLASS_INSTANCE_OF_EITHER_SIZE_READS_AND_WRITES_ITS_FIELDS() =
    val t = Two(1, 2)
    var f = Four(1, 2, 3, 4)

    assertEq([t.a, t.b], [1, 2])
    assertEq([f.a, f.b, f.c, f.d], [1, 2, 3, 4])

    f.d = 40

    assertEq(f.d, 40)
    assert(t is Two)
    assert(f is Four)
    assertEq(keys(f), ["a", "b", "c", "d"])

@test
A_DATA_VALUE_OF_EITHER_SIZE_COMPARES_AND_COPIES() =
    assertEq(Both(1, 2), Both(1, 2))
    assertEq(Widened(1, 2, 3, 4), Widened(1, 2, 3, 4))
    assert(Widened(1, 2, 3, 4) != Widened(1, 2, 3, 5))
    assertEq((Widened(1, 2, 3, 4) with { d: 5 }).d, 5)
    assertEq((Both(1, 2) with { right: 3 }).right, 3)

@test
A_WEAK_MAP_OUTGROWS_ITS_CELL_AND_FORGETS_A_KEY_ON_EITHER_SIDE() =
    val ks = [{ n: 0 }, { n: 1 }, { n: 2 }, { n: 3 }, { n: 4 }]
    val wm = WeakMap()

    for k in ks
        wm.set(k, k.n)

    for k in ks
        assertEq(wm.get(k), k.n)

    assert(wm.delete(ks[1]))
    assert(wm.delete(ks[4]))
    assert(!wm.has(ks[1]))
    assert(!wm.has(ks[4]))
    assertEq(wm.get(ks[3]), 3)

@test
EVERY_SIZE_COMES_BACK_FROM_JSON_AS_THE_SAME_OBJECT() =
    for n in 0..<7
        val back = parseJSON(toJSON(upTo(n)))

        assert(back.ok)
        assertEq(back.value, upTo(n))

said(f) = f() catch e -> e.message

@test
A_DATA_VALUE_REFUSES_A_FIELD_IT_DOES_NOT_HAVE_IN_ONE_SENTENCE_ON_EITHER_SIDE() =
    val small = said(() -> Both(1, 2) with { z: 1 })
    val big = said(() -> Widened(1, 2, 3, 4) with { z: 1 })

    val rest = " has no field `z` -- a data value's fields are the ones its declaration named, and `with` answers a copy that differs at one of them"

    assertEq(small, "`Both`" + rest)
    assertEq(big, "`Widened`" + rest)

@test
A_MISSING_FIELD_IS_ABSENT_ON_EITHER_SIDE_OF_THE_LINE() =
    assertEq(upTo(3).k3 ?? "none", "none")
    assertEq(upTo(5).k9 ?? "none", "none")

// The table moves when it spills and again each time it grows -- 6, 12, 24, 48 -- and every field
// written so far is read back after each write, so a read through a stale place would show.
@test
A_TABLE_READ_WHILE_IT_GROWS_ANSWERS_EVERY_FIELD_AT_EVERY_SIZE() =
    val o = {}

    for i in 0..<30
        o[s"k${i}"] = i * 10

        for j in 0..<(i + 1)
            assertEq(o[s"k${j}"], j * 10)

        assertEq(keys(o).length, i + 1)

// `without` answers a new, smaller object, which is back in its cell once it holds three.
@test
WITHOUT_SHRINKS_A_TABLE_BACK_INTO_ITS_CELL_AND_EVERY_FIELD_READS() =
    var o = upTo(8)

    for i in 0..<8
        o = without(o, s"k${i}")

        assertEq(keys(o).length, 7 - i)

        for j in (i + 1)..<8
            assertEq(o[s"k${j}"], j)

    assertEq(o, {})
