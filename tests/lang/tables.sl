// What a `Map`, a `Set` and an object answer as they grow, shrink and are grown again.
//
// The interpreter keeps a small table as a flat list of entries and builds a hash index only once
// the table outgrows it, so every question here is asked on BOTH sides of that line -- with a
// handful of keys, and with enough to have crossed it several times. Nothing about it is visible to
// a program, which is what these say.

@test
a_map_holds_every_kind_of_key_at_once() =
    val m = Map()

    m.set(1, "int")
    m.set("1", "str")
    m.set(true, "bool")
    m.set(null, "null")
    m.set([1, 2], "array")
    m.set({ a: 1 }, "object")

    assertEq(m.size, 6)
    assertEq(m.get(1), "int")
    assertEq(m.get("1"), "str")
    assertEq(m.get(true), "bool")
    assertEq(m.get(null), "null")
    assertEq(m.get([1, 2]), "array")
    assertEq(m.get({ a: 1 }), "object")

@test
an_integer_and_the_real_beside_it_are_one_key_and_the_string_is_another() =
    val m = Map()

    m.set(1, "one")
    assertEq(m.get(1.0), "one")

    m.set(1.0, "one again")
    assertEq(m.size, 1)
    assertEq(m.get(1), "one again")

    m.set("1", "text")
    assertEq(m.size, 2)
    assertEq(m.get("1"), "text")
    assertEq(m.get(1), "one again")

@test
a_very_large_and_a_very_negative_integer_are_keys_like_any_other() =
    val m = Map()

    m.set(9223372036854775807, "max")
    m.set(-9223372036854775807, "min")
    m.set(0, "zero")

    assertEq(m.get(9223372036854775807), "max")
    assertEq(m.get(-9223372036854775807), "min")
    assertEq(m.get(0), "zero")
    assertEq(m.size, 3)

// Negative zero is the same key as zero, because `-0.0 == 0` is true and a key follows `==`.
//
// **A `NaN` key is NOT here and the reason is a disagreement between the back ends rather than a
// choice**: `nan == nan` is false on both, so the interpreter can never find a key stored under one
// and answers `null`, while `slate js` finds it. Pinning either would pin one host's answer.
@test
negative_zero_and_zero_are_one_key() =
    val m = Map()

    m.set(-0.0, "zero")

    assertEq(m.size, 1)
    assertEq(m.get(0), "zero")
    assertEq(m.get(0.0), "zero")
    assertEq(m.get(-0.0), "zero")

@test
long_strings_that_differ_only_at_their_end_are_different_keys() =
    val head = "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"
    val m = Map()

    m.set(head + "A", 1)
    m.set(head + "B", 2)
    m.set(head, 3)

    assertEq(m.size, 3)
    assertEq(m.get(head + "A"), 1)
    assertEq(m.get(head + "B"), 2)
    assertEq(m.get(head), 3)

@test
a_key_deleted_and_written_again_goes_to_the_end() =
    val m = Map()

    m.set("a", 1)
    m.set("b", 2)
    m.set("c", 3)
    m.delete("b")

    assertEq(m.size, 2)
    assertEq(m.get("b"), null)

    m.set("b", 9)

    assertEq(m.size, 3)
    assertEq(m.get("b"), 9)
    assertEq(toJSON(m), "[[\"a\",1],[\"c\",3],[\"b\",9]]")

@test
A_MAP_GROWN_PAST_SEVERAL_REGROWS_KEEPS_EVERY_KEY_IN_ORDER() =
    val m = Map()
    var i = 0

    while i < 200
        m.set(i, i * 3)
        i = i + 1

    assertEq(m.size, 200)

    var seen = 0
    var k = 0

    while k < 200
        if m.get(k) == k * 3 then seen = seen + 1

        k = k + 1

    assertEq(seen, 200)
    assertEq(m.get(200), null)

    // The order is the order they were written, across every regrow.
    val pairs = m.entries()

    assertEq(pairs.length, 200)
    assertEq(pairs[0], [0, 0])
    assertEq(pairs[7], [7, 21])
    assertEq(pairs[8], [8, 24])
    assertEq(pairs[199], [199, 597])

@test
A_SET_GROWN_PAST_SEVERAL_REGROWS_KEEPS_EVERY_MEMBER_IN_ORDER() =
    val s = Set()
    var i = 0

    while i < 200
        s.add(i)
        i = i + 1

    assertEq(s.size, 200)
    assertEq(s.has(0), true)
    assertEq(s.has(7), true)
    assertEq(s.has(8), true)
    assertEq(s.has(199), true)
    assertEq(s.has(200), false)

    val members = s.values()

    assertEq(members[0], 0)
    assertEq(members[8], 8)
    assertEq(members[199], 199)

@test
a_map_emptied_by_deletion_and_filled_again_answers_as_a_new_one_does() =
    val m = Map()
    var i = 0

    while i < 40
        m.set(i, i)
        i = i + 1

    var j = 0

    while j < 40
        m.delete(j)
        j = j + 1

    assertEq(m.size, 0)

    m.set("after", 1)
    m.set("more", 2)

    assertEq(m.size, 2)
    assertEq(m.get("after"), 1)
    assertEq(m.get("more"), 2)
    assertEq(m.keys(), ["after", "more"])

@test
an_object_answers_the_same_with_two_fields_and_with_twenty() =
    val small = { a: 1, b: 2 }

    small.c = 3

    assertEq(keys(small), ["a", "b", "c"])
    assertEq(small.a + small.b + small.c, 6)

    var wide = {}
    var i = 0

    while i < 20
        wide["f" + string(i)] = i
        i = i + 1

    assertEq(keys(wide).length, 20)
    assertEq(wide.f0, 0)
    assertEq(wide.f7, 7)
    assertEq(wide.f8, 8)
    assertEq(wide.f19, 19)
    assertEq(keys(wide)[0], "f0")
    assertEq(keys(wide)[19], "f19")

    // A field written again keeps its place rather than moving to the end.
    wide.f0 = 100

    assertEq(keys(wide)[0], "f0")
    assertEq(wide.f0, 100)

    assertEq(keys(without(wide, "f8")).length, 19)
    assertEq(has(without(wide, "f8"), "f8"), false)

class Money
    var amount

    ==(self, o) = o is Money && o.amount == self.amount
    hash(self) = self.amount
end Money

@test
a_class_that_decides_its_own_equality_still_decides_which_keys_are_one() =
    val m = Map()

    m.set(Money.new(5), "five")
    m.set(Money.new(7), "seven")

    assertEq(m.get(Money.new(5)), "five")
    assertEq(m.get(Money.new(7)), "seven")
    assertEq(m.get(Money.new(6)), null)

    m.set(Money.new(5), "five again")

    assertEq(m.size, 2)
    assertEq(m.get(Money.new(5)), "five again")

    // And it goes on deciding once the table has outgrown its small case.
    var i = 0

    while i < 30
        m.set(Money.new(100 + i), i)
        i = i + 1

    assertEq(m.size, 32)
    assertEq(m.get(Money.new(5)), "five again")
    assertEq(m.get(Money.new(115)), 15)
