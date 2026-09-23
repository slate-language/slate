// Objects: insertion order, any value as a key, `proto`, and the receiver rule.

@test
an_object_keeps_the_order_its_keys_were_written_in() =
    val o = { b: 1, a: 2, c: 3 }

    assertEq(keys(o), ["b", "a", "c"])
    assertEq(values(o), [1, 2, 3])
    assertEq(entries(o), [["b", 1], ["a", 2], ["c", 3]])
    assertEq(keys(o).length, 3)

@test
a_key_may_be_any_value_at_all() =
    var t = {}

    t[[1, 2]] = "array key"
    t[{ a: 1 }] = "object key"
    t[1] = "one"
    t["s"] = "string"
    t[true] = "bool"
    t[null] = "null"

    assertEq(t[[1, 2]], "array key")
    assertEq(t[{ a: 1 }], "object key")
    assertEq(t[1], "one")
    assertEq(t["s"], "string")
    assertEq(t[true], "bool")
    assertEq(t[null], "null")
    assertEq(keys(t).length, 6)

@test
an_integral_real_and_the_integer_share_a_key_because_they_are_equal() =
    var t = {}

    t[1] = "one"
    t[1.0] = "one again"

    assertEq(keys(t).length, 1)
    assertEq(t[1], "one again")

@test
a_missing_field_is_undefined_and_undefined_may_not_be_stored() =
    val o = { a: 1 }

    assert(!has(o, "b"))
    assertEq(o.b ?? "fallback", "fallback")

    // `undefined` exists only as the answer to a read that found nothing, so it may not be passed
    // to a function either.
    assert(keeps(o.b) catch e -> true)

keeps(v) = v

@test
the_two_absences_compare_equal_and_has_is_what_tells_them_apart() =
    val o = { x: null }

    // `x == null` and `x == undefined` are one question: is this absent, either way.
    assert(o.nope == null)
    assert(o.nope == undefined)
    assert(o.x == null)
    assert(o.x == undefined)
    assert(null == undefined)

    // `!=` is the negation of that one question and nothing else.
    assert(!(o.nope != null))
    assert(!(null != undefined))

    // They are still two values, and `has` is what asks which one is there.
    assert(has(o, "x"))
    assert(!has(o, "nope"))

@test
THE_ABSENCE_RULE_IS_THE_ONLY_LOOSENESS_IN_EQUALITY() =
    // Nothing else of JavaScript's loose equality is taken, which is why there is no `===` here:
    // there is nothing to escape back to.
    assert(!(null == 0))
    assert(!(null == ""))
    assert(!(null == false))
    assert(!(null == []))
    assert(null != 0)

    val o = {}

    assert(!(o.nope == 0))
    assert(!(o.nope == ""))
    assert(!(o.nope == false))

@test
a_pattern_still_tells_a_null_from_an_absent_read() =
    // `==` treats the two alike and a pattern does not -- a literal pattern is a shape test.
    val o = { x: null }

    val here = o.x match
        null -> "null"
        _ -> "neither"

    val gone = o.nope match
        null -> "null"
        _ -> "neither"

    assertEq(here, "null")
    assertEq(gone, "neither")

@test
NO_CONTAINER_CAN_HOLD_AN_ABSENCE_SO_EQUALITY_MEETS_ONE_ONLY_AT_THE_TOP() =
    // The comparison is one function all the way down, so the rule would hold inside an array or an
    // object as well -- and no program can build the case, an absence being keepable nowhere.
    val o = {}

    assert(contains(inArray(o) catch e -> e.message, "cannot be put in an array"))
    assert(contains(inObject(o) catch e -> e.message, "cannot be put in an object"))

    // What a container CAN hold is `null`, and that compares as it always did.
    assert([null] == [null])
    assert({ a: null } == { a: null })
    assert(!([null] == [0]))

inArray(o) = [o.nope]
inObject(o) = { a: o.nope }

@test
a_quoted_key_is_the_only_spelling_for_one_that_is_not_a_name() =
    val o = { "a.b": 1, "if": 2, end: 3 }

    assertEq(o["a.b"], 1)
    assertEq(o["if"], 2)

    // `end` is a SOFT word and arrives as an ordinary name, so it is written bare and prints bare;
    // `if` is hard and can only be quoted. That is what the printing below is saying.
    assertEq(o.end, 3)
    assertEq(string(o), "{\"a.b\": 1, \"if\": 2, end: 3}")

    // A quoted key that IS a name is the same key as the bare one.
    assertEq(keys({ a: 1, "a": 2 }).length, 1)

@test
with_answers_a_copy_and_leaves_the_original_alone() =
    val a = { x: 1, y: 2 }
    val b = a with { y: 3, z: 4 }

    assertEq(a, { x: 1, y: 2 })
    assertEq(b, { x: 1, y: 3, z: 4 })

@test
with_takes_a_value_on_the_right_as_well_as_a_literal() =
    val a = { x: 1 }
    val more = { y: 2 }

    assertEq(a with more, { x: 1, y: 2 })

@test
A_with_TAKES_THE_SHORTHAND_AN_OBJECT_LITERAL_TAKES() =
    val x = 1
    val y = 2
    val base = { a: 9, x: 0 }

    assertEq(base with { x }, { a: 9, x: 1 })
    assertEq(base with { x, y }, { a: 9, x: 1, y: 2 })
    assertEq(base with { x, y: 7 }, { a: 9, x: 1, y: 7 })

    // The original is untouched, a shorthand being an ordinary way of saying what a field's value is.
    assertEq(base, { a: 9, x: 0 })

@test
a_shorthand_in_a_with_reads_the_name_at_whatever_depth_it_is_written() =
    val y = 2
    val base = { a: 9 }

    assertEq({ p: base with { y } }, { p: { a: 9, y: 2 } })
    assertEq(base with { q: base with { y } }, { a: 9, q: { a: 9, y: 2 } })

@test
a_method_reached_through_a_proto_is_handed_the_object() =
    val Base = { twice: (self) -> self.n * 2 }
    val o = { n: 21, proto: Base }

    assertEq(o.twice(), 42)

@test
a_method_stored_on_the_object_is_not_handed_the_object() =
    val o = { n: 21 }

    o.twice = () -> o.n * 2

    assertEq(o.twice(), 42)

@test
a_proto_chain_is_walked_for_a_field() =
    val top = { a: "top" }
    val mid = { b: "mid", proto: top }
    val o = { proto: mid }

    assertEq(o.a, "top")
    assertEq(o.b, "mid")

@test
proto_is_an_ordinary_field_and_is_not_hidden() =
    // A proto is a well-known field NAME rather than a slot on the object, which is what makes
    // `with` work on one and what let protos cost no syntax. So it is walked and printed like any
    // other field -- what a declaration writes and hides is the unspellable `(class)` tag instead.
    val o = { n: 1, proto: { m: 2 } }

    assertEq(keys(o), ["n", "proto"])
    assertEq(keys(o).length, 2)
    assertEq(string(o), "{n: 1, proto: {m: 2}}")

@test
an_optional_link_guards_the_whole_chain_after_it() =
    val o = { a: { b: { c: 1 } } }
    val nothing = { }

    assertEq(o.a?.b.c, 1)
    assertEq(nothing.a?.b ?? "none", "none")

    // The whole run of links after the guard is skipped, however long it is, and the answer is null.
    assertEq(nothing.a?.b.c.d ?? "none", "none")

@test
a_chain_guards_the_ABSENCE_IT_WAS_WRITTEN_ABOUT_and_no_other() =
    // A link AFTER the guard that finds a nullish value of its own faults there, exactly as it would
    // with no `?.` in the line. `a?.b?.c` is what says both may be missing.
    opaque(v) = v

    val a = opaque({ b: null })

    assertFaults(() -> a?.b.c, "there is nothing here to read `c` from")
    assertEq(a?.b?.c ?? "none", "none")

@test
a_guarded_index_and_a_guarded_call_answer_for_an_absent_left() =
    val o = { xs: [10, 20], go: n -> n * 2 }
    val nothing = { }

    assertEq(o.xs?.[1], 20)
    assertEq(nothing.xs?.[1] ?? "none", "none")
    assertEq(o.go?.(21), 42)
    assertEq(nothing.go?.(21) ?? "none", "none")

@test
a_guarded_link_works_out_nothing_to_its_right_where_it_short_circuits() =
    var keys = 0
    var args = 0

    which() =
        keys += 1
        0

    one() =
        args += 1
        1

    val gone = { }

    assertEq(gone.xs?.[which()] ?? "none", "none")
    assertEq(gone.go?.(one()) ?? "none", "none")
    assertEq(keys, 0)
    assertEq(args, 0)

    val here = { xs: [7], go: n -> n + 1 }

    assertEq(here.xs?.[which()], 7)
    assertEq(here.go?.(one()), 2)
    assertEq(keys, 1)
    assertEq(args, 1)

@test
a_guarded_left_is_worked_out_exactly_once() =
    var calls = 0

    pick() =
        calls += 1
        [4]

    assertEq(pick()?.[0], 4)
    assertEq(calls, 1)

@test
the_three_guarded_links_chain_when_each_one_says_so() =
    val a = { b: [{ c: 7, go: () -> 5 }] }
    val gone = { }

    assertEq(a?.b?.[0]?.c, 7)
    assertEq(a?.b?.[0]?.go?.(), 5)
    assertEq(gone.b?.[0]?.c ?? "none", "none")

@test
ONE_guard_carries_every_kind_of_link_that_follows_it() =
    val a = { b: [{ c: 7, go: () -> 5 }], f: () -> ({ g: 9 }), m: (self) -> 11 }
    val gone = null

    // A field, an index, a call and a method call all join the chain the first `?.` opened.
    assertEq(a?.b[0].c, 7)
    assertEq(a?.f().g, 9)
    assertEq(a?.b[0].go(), 5)
    assertEq(a?.m(), 11)

    assertEq(gone?.b[0].c ?? "none", "none")
    assertEq(gone?.f().g ?? "none", "none")
    assertEq(gone?.[0].x ?? "none", "none")
    assertEq(gone?.().y ?? "none", "none")

@test
a_chain_that_short_circuits_works_out_NOTHING_further_along_it() =
    var calls = 0

    bump() =
        calls += 1
        0

    val gone = null

    // Neither the key nor the argument nor the call is reached.
    assertEq(gone?.b[bump()].c(bump()) ?? "none", "none")
    assertEq(calls, 0)

    val here = { b: [{ c: n -> n + 1 }] }

    assertEq(here?.b[bump()].c(bump()), 1)
    assertEq(calls, 2)

@test
BRACKETS_END_A_CHAIN_and_the_link_after_them_asks_the_guarded_answer() =
    // `(a?.b)` is a chain that is over, so `.c` is asked of the null it answered -- which is
    // JavaScript's rule, and the reason the brackets have to be written down at all.
    opaque(v) = v

    val gone = opaque(null)

    assertFaults(() -> (gone?.b).c, "there is nothing here to read `c` from")

    val a = opaque({ b: { c: 3 } })

    assertEq((a?.b).c, 3)

@test
a_chain_inside_a_chains_KEY_is_a_chain_of_its_own() =
    val gone = null
    val keys = { at: 0 }
    val a = { rows: [10, 20] }

    assertEq(a?.rows[gone?.n ?? 1], 20)
    assertEq(a?.rows[keys?.at], 10)

@test
a_chain_may_be_the_receiver_of_a_method_and_the_left_of_an_operator() =
    val P = { twice: (self, x) -> x * 2 }
    val a = { o: { n: 1, proto: P } }
    val gone = null

    assertEq(a?.o.twice(4), 8)
    assertEq(gone?.o.twice(4) ?? "none", "none")

    // `with` and `is` read what the chain answered.
    assertEq((a?.o.proto with { }) == { twice: P.twice }, true)
    assert(a?.o is object)
    assert(!(gone?.o is object))

@test
a_guarded_receiver_makes_the_method_call_or_answers_nothing() =
    val P = { twice: (self, x) -> x * 2 }
    val o = { n: 1, proto: P }
    val gone = { }
    var args = 0

    one() =
        args += 1
        1

    assertEq(o?.twice(3), 6)
    assertEq(gone.nope?.twice(one()) ?? "none", "none")
    assertEq(args, 0)

    // The arguments are worked out where the call happens and nowhere else, which is what the guard
    // buys over a test written after the call.
    assertEq(o?.twice(one()), 2)
    assertEq(args, 1)

    // A builtin method is reached the same way, the guard being about the receiver and not about
    // where the method came from.
    assertEq([1, 2]?.map(x -> x + 1), [2, 3])
    assertEq(gone.nope?.map(one()) ?? "none", "none")
    assertEq(args, 1)

@test
a_guarded_receiver_that_is_there_and_cannot_do_it_still_faults() =
    // `?.` guards the LINK and not the call: a receiver that is present is asked for the method, and
    // a kind that has no such method says so exactly as it does without the guard.
    opaque(v) = v

    val three = opaque(3)

    assertFaults(() -> three?.nope(), "`nope` is not something an integer can do")

@test
a_guarded_call_still_faults_on_a_callee_that_is_there_and_is_not_a_function() =
    // **An unannotated function answers `any` by design**, which is how a value whose type the
    // checker cannot see is handed over -- so what this pins is the machine's own refusal.
    opaque(v) = v

    val three = opaque(3)

    assertFaults(() -> three?.())

@test
equality_is_content_based_for_a_plain_object() =
    assert({ a: 1, b: [2] } == { a: 1, b: [2] })
    assert(!({ a: 1 } == { a: 2 }))

    // The key ORDER does not decide equality.
    assert({ a: 1, b: 2 } == { b: 2, a: 1 })

@test
an_object_prints_its_contents() =
    assertEq(string({ a: 1, b: "x" }), "{a: 1, b: \"x\"}")
    assertEq(string({}), "{}")

@test
a_table_keyed_by_something_other_than_a_string_PRINTS() =
    var t = {}

    t[{ v: 1 }] = "object key"
    t[[1, 2]] = "array key"
    t[1] = "one"

    // **Storing and reading back was never the problem, and printing was.** The suite already
    // checked that any value is a key, so the JavaScript back end looked right -- its `SObj` hashes
    // a key through `hashValue` and compares it with `eq`, both of which take anything. Its PRINTER
    // assumed a string, so `print(t)` died inside the escaper with node's own `s is not iterable`
    // and no line of slate anywhere in it. Nothing here had ever printed one.
    assertEq(string(t), "{{v: 1}: \"object key\", [1, 2]: \"array key\", 1: \"one\"}")

@test
a_key_that_is_not_a_plain_name_is_quoted_where_a_name_is_bare() =
    var t = {}

    t["a b"] = 1
    t["ok"] = 2

    assertEq(string(t), "{\"a b\": 1, ok: 2}")

@test
a_shorthand_field_names_its_key_and_reads_the_name() =
    val x = 1
    val y = 2

    assertEq({ x }, { x: 1 })
    assertEq({ x, y }, { x: 1, y: 2 })

    // The key is the name as written, and the order is the order the fields were written in --
    // a shorthand being an ordinary field with its value left to be read off the name.
    assertEq(keys({ x, y }), ["x", "y"])
    assertEq(string({ x, y }), "{x: 1, y: 2}")

@test
a_shorthand_MIXES_WITH_EVERY_OTHER_KIND_OF_FIELD() =
    val x = 1
    val o = { z: 9 }

    assertEq({ x, y: 2 }, { x: 1, y: 2 })
    assertEq({ y: 2, x }, { y: 2, x: 1 })
    assertEq({ "a b": 3, x }, { "a b": 3, x: 1 })

    // **A spread and a shorthand meet in the same literal**, and the later entry still wins --
    // the shorthand is desugared before `object_so_far` sees it, so the merge rule is untouched.
    assertEq(string({ ...o, x }), "{z: 9, x: 1}")
    assertEq(string({ x, ...o }), "{x: 1, z: 9}")

    val z = 5

    assertEq(string({ ...o, z }), "{z: 5}")
    assertEq(string({ z, ...o }), "{z: 9}")

@test
a_shorthand_READS_THE_NAME_WHERE_IT_IS_WRITTEN() =
    val x = "outer"

    // A nested literal reads the name in scope at that point, the shorthand being an ordinary
    // read of a name rather than anything the literal does.
    assertEq(string({ p: { x } }), "{p: {x: \"outer\"}}")

    f(x) = { x }

    assertEq(f(7), { x: 7 })

    // **And it is the same spelling an object pattern uses, read the other way round.**
    val { x: got } = { x }

    assertEq(got, "outer")
