// A literal of up to eight distinct keys writes its table without looking anything up, and one of
// nine, or one naming a key twice, takes the general write. What these pin is that the two make the
// same object: the same order, the same lookups, the same equality, and the same answers from `with`,
// `without` and JSON on either side of the line.

eight(v) = { a: v, b: v + 1, c: v + 2, d: v + 3, e: v + 4, f: v + 5, g: v + 6, h: v + 7 }

nine(v) = { a: v, b: v + 1, c: v + 2, d: v + 3, e: v + 4, f: v + 5, g: v + 6, h: v + 7, i: v + 8 }

class Money
    val currency = "EUR"
    var cents = 0

writesCurrency(o)
    o.currency = "USD"

@test
EIGHT_KEYS_AND_NINE_KEEP_THEIR_ORDER_AND_ANSWER_EVERY_LOOKUP() =
    val small = eight(10)
    val big = nine(10)

    assertEq(keys(small), ["a", "b", "c", "d", "e", "f", "g", "h"])
    assertEq(keys(big), ["a", "b", "c", "d", "e", "f", "g", "h", "i"])

    for k in keys(small)
        assertEq(small[k], big[k])

    assertEq(big.i, 18)
    assert(!has(small, "i"))

@test
A_LITERAL_EQUALS_THE_SAME_FIELDS_WRITTEN_IN_ANOTHER_ORDER_ON_BOTH_SIDES_OF_THE_LINE() =
    assertEq(eight(1), { h: 8, g: 7, f: 6, e: 5, d: 4, c: 3, b: 2, a: 1 })
    assertEq(nine(1), { i: 9, h: 8, g: 7, f: 6, e: 5, d: 4, c: 3, b: 2, a: 1 })
    assert(eight(1) != eight(2))

@test
WITH_CARRIES_A_SMALL_LITERAL_ACROSS_THE_LINE_AND_WITHOUT_BRINGS_IT_BACK() =
    val grown = eight(0) with { i: 8 }

    assertEq(grown, nine(0))
    assertEq(keys(grown).length, 9)

    val shrunk = without(grown, "i")

    assertEq(shrunk, eight(0))
    assertEq(keys(shrunk), keys(eight(0)))

@test
A_SMALL_LITERAL_COMES_BACK_FROM_JSON_AS_THE_SAME_OBJECT() =
    val back = parseJSON(toJSON(eight(3)))

    assert(back.ok)
    assertEq(back.value, eight(3))

// A class's `val` is a mark in the class object's own table, and noting that mark is the one question
// the fresh write still asks of each key.
@test
A_CLASS_BUILT_BY_THE_FRESH_WRITE_STILL_REFUSES_A_WRITE_TO_ITS_val() =
    val m = Money(5)

    assertEq(m.cents, 5)
    m.cents = 6
    assertEq(m.cents, 6)
    assertFaults(() -> writesCurrency(m), "`currency` is a `val` of `Money`")
    assertFaults(() -> writesCurrency(Money), "`currency` is a `val` of `Money`")
    assertEq(m.currency, "EUR")
