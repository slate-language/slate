// Arrays: the five places slate decided against JavaScript on purpose, and the operations either
// way round.

@test
the_bare_verb_changes_the_array_and_the_participle_answers_a_new_one() =
    var xs = [3, 1, 2]
    val ys = sorted(xs)

    assertEq(xs, [3, 1, 2])
    assertEq(ys, [1, 2, 3])

    sort(xs)

    assertEq(xs, [1, 2, 3])

    var zs = [1, 2, 3]
    val ws = reversed(zs)

    assertEq(zs, [1, 2, 3])
    assertEq(ws, [3, 2, 1])

    reverse(zs)

    assertEq(zs, [3, 2, 1])

@test
numbers_sort_as_numbers_and_not_as_text() =
    assertEq(sorted([10, 9, 100]), [9, 10, 100])

@test
a_comparator_answers_a_boolean_because_zero_is_true_in_slate() =
    val people = [{ age: 30 }, { age: 20 }]
    val byAge = sorted(people, (a, b) -> a.age < b.age)

    assertEq(byAge[0].age, 20)

@test
the_sort_is_stable_which_is_why_a_program_sorts_twice() =
    val xs = [{ k: "b", n: 1 }, { k: "a", n: 2 }, { k: "a", n: 1 }]
    val byK = sorted(sorted(xs, (a, b) -> a.n < b.n), (a, b) -> a.k < b.k)

    assertEq(byK[0].n, 1)
    assertEq(byK[1].n, 2)
    assertEq(byK[2].k, "b")

@test
a_callback_is_handed_the_value_and_nothing_else() =
    assertEq(map([1, 2, 3], (x) -> x * 2), [2, 4, 6])
    assertEq(filter([1, 2, 3, 4], (x) -> x % 2 == 0), [2, 4])
    assertEq(reduce([1, 2, 3], (a, b) -> a + b, 0), 6)
    assertEq(find([1, 2, 3], (x) -> x > 1), 2)

@test
searching_answers_null_for_a_miss() =
    assertEq(indexOf([1, 2, 1], 1), 0)
    assertEq(indexOf([1, 2], 9), null)
    assertEq(lastIndexOf([1, 2, 1], 1), 2)
    assertEq(lastIndexOf([1, 2], 9), null)
    assertEq(findIndex([1, 2, 3], (x) -> x > 5), null)
    assertEq(findIndex([1, 2, 3], (x) -> x > 1), 1)
    assertEq(find([1, 2], (x) -> x > 5), null)

@test
the_operations_that_change_an_array_answer_nothing() =
    var xs = [1]

    assertEq(push(xs, 2), null)
    assertEq(xs, [1, 2])
    assertEq(pop(xs), 2)
    assertEq(xs, [1])

    insert(xs, 0, 9)

    assertEq(xs, [9, 1])
    assertEq(removeAt(xs, 0), 9)

    clear(xs)

    assertEq(xs, [])
    assertEq(len(xs), 0)

@test
clear_takes_an_array_and_not_an_object() =
    // An object's names belong to the program, so the array operations are not in its table at all
    // — `clear` is one of them, and the JavaScript back end accepted an object where the
    // interpreter refuses one.
    val said = (anything({ a: 1 }).clear()) catch e -> e.message

    assert(contains(said, "clear"))
    assert(contains(said, "object"))
    assert(clear(anything({ a: 1 })) catch e -> true)

@test
popping_an_empty_array_is_a_fault_rather_than_an_absence() =
    var xs = []

    assert(pop(xs) catch e -> true)

@test
the_operations_that_answer_a_new_array() =
    assertEq(concat([1], [2], [3]), [1, 2, 3])
    assertEq(flat([[1, 2], [3]]), [1, 2, 3])
    assertEq(sum([1, 2, 3]), 6)
    assert(every([2, 4], (x) -> x % 2 == 0))
    assert(some([1, 4], (x) -> x % 2 == 0))
    assert(contains([1, 2], 2))

@test
an_array_is_equal_to_one_holding_the_same_things() =
    assert([1, [2, { a: 3 }]] == [1, [2, { a: 3 }]])
    assert(!([1, 2] == [2, 1]))

@test
slicing_and_indexing() =
    val xs = [1, 2, 3, 4]

    assertEq(xs[1], 2)
    assertEq(xs[1..<3], [2, 3])
    assertEq(xs[1..2], [2, 3])

@test
an_index_past_the_end_is_a_fault() =
    val xs = [1]

    assert(xs[3] catch e -> true)

@test
changing_an_array_while_it_is_being_walked_is_refused() =
    var xs = [1, 2, 3]

    assert(map(xs, (v) -> pop(xs)) catch e -> true)

@test
a_method_is_the_free_function_with_the_receiver_in_front() =
    assertEq([1, 2].map((x) -> x + 1), map([1, 2], (x) -> x + 1))
    assertEq("a,b".split(","), split("a,b", ","))

@test
asking_an_array_for_something_only_a_string_can_do_names_the_kind() =
    val said = (anything([1]).upper()) catch e -> e.message

    assert(contains(said, "upper"))
    assert(contains(said, "array"))

anything(v) = v

// -- the eight an array answers that it did not before ---------------------------------------------

@test
slice_asks_for_whatever_part_of_the_array_is_there() =
    val xs = [1, 2, 3, 4]

    assertEq(xs.slice(1), [2, 3, 4])
    assertEq(xs.slice(1, 3), [2, 3])

    // **Both ends clamp**, which is what makes a slice a question rather than a claim: asking for
    // more than is there gives what is there, and crossed ends give nothing rather than a reversed
    // array.
    assertEq(xs.slice(0, 100), [1, 2, 3, 4])
    assertEq(xs.slice(3, 1), [])
    assertEq(xs.slice(100), [])

    // A negative position counts back from the end.
    assertEq(xs.slice(-2), [3, 4])
    assertEq(xs.slice(-3, -1), [2, 3])

    // The array it was asked about is untouched.
    assertEq(xs, [1, 2, 3, 4])

@test
at_is_the_negative_index_that_the_brackets_have_no_room_for() =
    val xs = [1, 2, 3]

    assertEq(xs.at(0), 1)
    assertEq(xs.at(-1), 3)
    assertEq(xs.at(2), 3)

    // **Out of range is a fault and not an absent value**, which is `xs[i]`'s rule and `pop`'s:
    // JavaScript answers `undefined`, which travels, and slate's `undefined` may not.
    assert((xs.at(5) catch e -> e.message).contains("this array has 3 of them"))
    assert((xs.at(-5) catch e -> e.message).contains("this array has 3 of them"))

@test
shift_is_pops_twin_and_unshift_is_pushs() =
    var xs = [1, 2, 3]

    assertEq(xs.shift(), 1)
    assertEq(xs, [2, 3])

    // **Nothing is handed back from `unshift`**, which is `push`'s rule rather than JavaScript's:
    // there it answers the new length, a number nobody reads.
    assertEq(xs.unshift(0), null)
    assertEq(xs, [0, 2, 3])

    var empty = []

    assert((empty.shift() catch e -> e.message).contains("nothing to shift off an empty array"))

@test
flatMap_is_map_and_flat_in_one_walk() =
    assertEq([1, 2].flatMap(n -> [n, n]), [1, 1, 2, 2])

    // The case neither handles alone: nothing for some elements and several for others.
    assertEq([1, 2, 3].flatMap(n -> if n == 2 then [] else [n]), [1, 3])

    // One level and not all of them, which is `flat`'s rule.
    assertEq([1].flatMap(n -> [[n]]), [[1]])

@test
forEach_is_for_what_it_does_rather_than_what_it_answers() =
    var seen = []

    assertEq([1, 2, 3].forEach(n -> push(seen, n * 2)), null)
    assertEq(seen, [2, 4, 6])

@test
findLast_walks_from_the_other_end() =
    val xs = [1, 2, 3, 2]

    assertEq(xs.findLast(n -> n == 2), 2)
    assertEq(xs.findLastIndex(n -> n == 2), 3)
    assertEq(xs.findIndex(n -> n == 2), 1)

    // Absent is `null` and not -1, which is `find`'s answer and `indexOf`'s.
    assertEq(xs.findLast(n -> n > 5), null)
    assertEq(xs.findLastIndex(n -> n > 5), null)

@test
the_new_eight_chain_with_the_ones_that_were_already_there() =
    assertEq([4, 1, 3, 2].sorted().slice(1, 3).flatMap(n -> [n, n]).at(-1), 3)
