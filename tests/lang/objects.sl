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
the_optional_link_guards_its_own_link_and_not_the_rest_of_the_chain() =
    val o = { a: { b: 1 } }
    val nothing = { }

    assertEq(o.a?.b, 1)
    assertEq(nothing.a?.b ?? "none", "none")

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
