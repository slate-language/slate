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

// -- set algebra ---------------------------------------------------------------------------------
//
// The seven operations two sets answer, written both ways. Every one of these is a statement about
// the LANGUAGE rather than about either implementation of it, which is why they are here: the four
// that combine answer a new set, the three that ask answer a boolean, and the operators mean exactly
// what the words mean.

@test
the_four_combining_operations_answer_a_new_set_and_leave_both_sides_alone() =
    val a = Set([1, 2, 3])
    val b = Set([3, 4])

    assertEq(a.union(b).values(), [1, 2, 3, 4])
    assertEq(a.intersection(b).values(), [3])
    assertEq(a.difference(b).values(), [1, 2])
    assertEq(a.symmetricDifference(b).values(), [1, 2, 4])

    assertEq(a.values(), [1, 2, 3])
    assertEq(b.values(), [3, 4])

// The answer walks the receiver's members and then the argument's, which is the only order a reader
// can predict -- a set walking in the order things went into it.
@test
a_combined_set_walks_the_receiver_first_and_the_argument_after_it() =
    assertEq(Set([3, 1]).union(Set([2, 1])).values(), [3, 1, 2])
    assertEq(Set([9, 5, 7]).intersection(Set([7, 9])).values(), [9, 7])
    assertEq(Set([3, 1]).symmetricDifference(Set([4, 1, 2])).values(), [3, 4, 2])

@test
an_empty_set_and_a_set_with_itself_are_the_two_edges_of_the_algebra() =
    val e = Set()
    val a = Set([1, 2])

    assertEq(e.union(a).values(), [1, 2])
    assertEq(a.union(e).values(), [1, 2])
    assertEq(e.intersection(a).size, 0)
    assertEq(a.difference(a).size, 0)
    assertEq(a.symmetricDifference(a).size, 0)
    assertEq(a.intersection(a).values(), [1, 2])

// A set is a subset and a superset of itself, which is what those words mean, and the empty set is
// a subset of everything.
@test
the_three_predicates_answer_a_boolean_and_a_set_contains_itself() =
    val a = Set([1, 2])
    val b = Set([1, 2, 3])

    assertEq(a.isSubsetOf(b), true)
    assertEq(b.isSubsetOf(a), false)
    assertEq(a.isSubsetOf(a), true)

    assertEq(b.isSupersetOf(a), true)
    assertEq(a.isSupersetOf(b), false)

    assertEq(a.isDisjointFrom(Set([7, 8])), true)
    assertEq(a.isDisjointFrom(b), false)

    assertEq(Set().isSubsetOf(a), true)
    assertEq(a.isSubsetOf(Set()), false)
    assertEq(Set().isDisjointFrom(Set()), true)

// The operators are the same seven operations under Python's spelling, so a program written either
// way has to mean one thing.
@test
the_operators_between_two_sets_are_the_same_seven_operations() =
    val a = Set([1, 2, 3])
    val b = Set([3, 4])

    assertEq((a | b).values(), a.union(b).values())
    assertEq((a & b).values(), a.intersection(b).values())
    assertEq((a - b).values(), a.difference(b).values())
    assertEq((a ^ b).values(), a.symmetricDifference(b).values())

    assertEq(Set([1, 2]) <= a, true)
    assertEq(a <= a, true)
    assertEq(a >= Set([1, 2]), true)
    assertEq(a >= a, true)

// A strict containment is the plain one and not the same set, so `<` is false of a set and itself.
@test
a_strict_containment_is_false_of_a_set_and_itself() =
    val a = Set([1, 2, 3])

    assertEq(Set([1, 2]) < a, true)
    assertEq(a < a, false)
    assertEq(a > Set([1, 2]), true)
    assertEq(a > a, false)

// Two sets that each hold something the other does not order no way at all, so all four comparisons
// are false of them.
@test
two_sets_neither_of_which_contains_the_other_order_no_way_at_all() =
    val a = Set([1, 2])
    val b = Set([2, 3])

    assertEq(a < b, false)
    assertEq(a <= b, false)
    assertEq(a > b, false)
    assertEq(a >= b, false)

// `==` is identity for a set, as it is for every container whose contents can change -- so two sets
// holding the same members are not equal, and containment both ways is the question a program means.
@test
two_sets_holding_the_same_members_are_not_equal_and_contain_each_other() =
    val a = Set([1, 2])
    val b = Set([2, 1])

    assertEq(a == b, false)
    assertEq(a <= b && b <= a, true)
    assertEq(a < b, false)

// A class deciding its own equality decides what two sets share, the members being compared by the
// very `==` and `hash` the class wrote.
@test
a_class_that_decides_its_own_equality_decides_what_two_sets_share() =
    val a = Set([Money.new(5), Money.new(7)])
    val b = Set([Money.new(7), Money.new(9)])

    assertEq(a.intersection(b).size, 1)
    assertEq(a.difference(b).size, 1)
    assertEq(a.union(b).size, 3)
    assertEq(b.isSupersetOf(Set([Money.new(7)])), true)
    assertEq(a.isDisjointFrom(Set([Money.new(1)])), true)
