// `freeze` and `isFrozen`: what a closed value refuses, what it still answers, and where the copy is.
//
// **A lambda's one-line body is an EXPRESSION, so an assignment cannot be one** -- which is why the
// writes a test is about are written once here, in definitions with block bodies, and handed to
// `assertFaults` by name.

frozenPutAt(t, k, v) =
    t[k] = v

frozenSetA(t) =
    t.a = 2

frozenSetFresh(t) =
    t.fresh = 2

@test
freeze_answers_the_very_value_it_was_given() =
    val o = { a: 1 }
    val same = freeze(o)

    assert(same == o)
    assert(isFrozen(o))

@test
a_frozen_object_reads_exactly_as_it_did() =
    val o = freeze({ a: 1, b: "two", c: [3] })

    assertEq(o.a, 1)
    assertEq(o["b"], "two")
    assertEq(keys(o), ["a", "b", "c"])
    assertEq(values(o), [1, "two", [3]])
    assert(has(o, "a"))

@test
writing_a_field_of_a_frozen_object_names_the_field_and_the_way_out() =
    val o = freeze({ a: 1 })

    assertFaults(() -> frozenSetA(o),
        "`a` belongs to a frozen value, and `freeze` is what closed it -- a copy made with `with` or a spread is a new value that is free to change")
    // **The bracketed form names the key without backticks around it**, which is what the dotted and
    // the bracketed write have always differed in and is not this feature's to change.
    assertFaults(() -> frozenPutAt(o, "a", 2), "a belongs to a frozen value")
    assertFaults(() -> frozenSetFresh(o), "`fresh` belongs to a frozen value")
    assertEq(o.a, 1)

@test
a_frozen_object_is_NOT_a_data_value_and_the_two_sentences_differ() =
    val o = freeze({ a: 1 })

    // A data value's sentence points at `with` as what to write INSTEAD, and answers another sealed
    // value. This one points at `with` as the way BACK to something writable.
    assertFaults(() -> frozenSetA(o), "`freeze` is what closed it")

@test
with_and_a_spread_answer_a_copy_that_is_free_to_change() =
    val o = freeze({ a: 1, b: 2 })
    val copy = o with { a: 9 }

    assert(!isFrozen(copy))
    assertEq(copy.a, 9)
    assertEq(copy.b, 2)

    copy.a = 10
    assertEq(copy.a, 10)

    var spread = { ...o }

    assert(!isFrozen(spread))
    spread.b = 7
    assertEq(spread.b, 7)

    val dropped = without(o, "a")

    assert(!isFrozen(dropped))
    assertEq(keys(dropped), ["b"])

@test
every_mutator_of_a_frozen_array_is_refused_by_name() =
    val xs = freeze([1, 2, 3])

    assertFaults(() -> push(xs, 4),
        "this array is frozen, and `push` would change it -- `freeze` is what closed it, and `[...xs]` answers a copy that is free to change")
    assertFaults(() -> pop(xs), "`pop` would change it")
    assertFaults(() -> shift(xs), "`shift` would change it")
    assertFaults(() -> unshift(xs, 0), "`unshift` would change it")
    assertFaults(() -> insert(xs, 0, 0), "`insert` would change it")
    assertFaults(() -> removeAt(xs, 0), "`removeAt` would change it")
    assertFaults(() -> clear(xs), "`clear` would change it")
    assertFaults(() -> sort(xs), "`sort` would change it")
    assertFaults(() -> reverse(xs), "`reverse` would change it")
    assertFaults(() -> frozenPutAt(xs, 0, 9), "`xs[i] = v` would change it")
    assertEq(xs, [1, 2, 3])

@test
a_frozen_array_still_reads_and_still_answers_the_builtins_that_copy() =
    val xs = freeze([3, 1, 2])

    assertEq(xs[0], 3)
    assertEq(xs.length, 3)
    assertEq(sorted(xs), [1, 2, 3])
    assertEq(reversed(xs), [2, 1, 3])
    assertEq(map(xs, n -> n * 2), [6, 2, 4])

    val copy = [...xs]

    assert(!isFrozen(copy))
    push(copy, 4)
    assertEq(copy.length, 4)

@test
a_frozen_buffer_refuses_the_two_ways_of_writing_through_it() =
    val b = freeze(toBytes("ab"))

    assertFaults(() -> push(b, 99),
        "this buffer is frozen, and `push` would change it -- `freeze` is what closed it, and `bytes(b.toArray())` answers a copy that is free to change")
    assertFaults(() -> clear(b), "`clear` would change it")
    assertFaults(() -> frozenPutAt(b, 0, 99), "`b[i] = v` would change it")
    assertEq(b.length, 2)
    assertEq(b[0], 97)

@test
a_frozen_set_refuses_add_delete_and_clear_and_still_answers_has() =
    val s = freeze(Set([1, 2]))

    assertFaults(() -> s.add(3),
        "this set is frozen, and `add` would change it -- `freeze` is what closed it, and `Set(s)` answers a copy that is free to change")
    assertFaults(() -> s.delete(1), "`delete` would change it")
    assertFaults(() -> s.clear(), "`clear` would change it")
    assert(s.has(1))
    assertEq(s.size, 2)

    val copy = Set(s)

    assert(!isFrozen(copy))
    copy.add(3)
    assertEq(copy.size, 3)

@test
a_frozen_map_refuses_set_delete_and_clear_and_still_answers_get() =
    val m = freeze(Map([["k", 1]]))

    assertFaults(() -> m.set("j", 2),
        "this map is frozen, and `set` would change it -- `freeze` is what closed it, and `Map(m)` answers a copy that is free to change")
    assertFaults(() -> m.delete("k"), "`delete` would change it")
    assertFaults(() -> m.clear(), "`clear` would change it")
    assertEq(m.get("k"), 1)
    assertEq(m.size, 1)

    val copy = Map(m)

    assert(!isFrozen(copy))
    copy.set("j", 2)
    assertEq(copy.size, 2)

@test
a_frozen_weak_map_refuses_its_two_writes_and_has_no_copy_to_point_at() =
    val key = { id: 1 }
    val wm = WeakMap()

    wm.set(key, "held")
    freeze(wm)

    assert(isFrozen(wm))
    assertFaults(() -> wm.set(key, "again"),
        "this weak map is frozen, and `set` would change it -- `freeze` is what closed it")
    assertFaults(() -> wm.delete(key), "`delete` would change it")
    assertEq(wm.get(key), "held")

@test
freeze_is_SHALLOW_which_is_JavaScripts_rule() =
    val inner = { n: 1 }
    val o = freeze({ inner: inner, xs: [1] })

    assert(!isFrozen(o.inner))
    o.inner.n = 2
    assertEq(o.inner.n, 2)

    push(o.xs, 2)
    assertEq(o.xs.length, 2)

@test
freezing_twice_is_a_no_op() =
    val o = { a: 1 }

    freeze(o)
    freeze(freeze(o))

    assert(isFrozen(o))
    assertFaults(() -> frozenSetA(o), "belongs to a frozen value")

@test
a_value_with_nothing_to_write_through_answers_itself_and_is_already_frozen() =
    assertEq(freeze(7), 7)
    assertEq(freeze("hi"), "hi")
    assertEq(freeze(true), true)
    assertEq(freeze(null), null)
    assert(isFrozen(7))
    assert(isFrozen("hi"))
    assert(isFrozen(true))
    assert(isFrozen(null))
    assert(isFrozen(n -> n))

@test
isFrozen_is_false_for_a_container_nobody_closed() =
    assert(!isFrozen({ a: 1 }))
    assert(!isFrozen([1]))
    assert(!isFrozen(Set([1])))
    assert(!isFrozen(Map([["k", 1]])))
    assert(!isFrozen(toBytes("ab")))
    assert(!isFrozen(WeakMap()))

@test
a_DATA_VALUE_IS_FROZEN_WITHOUT_ANYBODY_HAVING_CALLED_freeze() =
    val c = FreezeCircle(2)

    assert(isFrozen(c))
    assertFaults(() -> frozenPutAt(c, "r", 3), "belongs to a data value")

    // A `with` copy of a data value is a data value and stays closed, which is the other half of the
    // rule a frozen plain object reads the other way.
    val bigger = c with { r: 3 }

    assert(isFrozen(bigger))
    assert(bigger is FreezeCircle)

data FreezeShape
    FreezeCircle(r)

@test
freezing_a_value_a_program_already_holds_closes_every_name_for_it() =
    val o = { a: 1 }
    val other = o

    freeze(other)

    assertFaults(() -> frozenSetA(o), "belongs to a frozen value")
    assert(isFrozen(o))
