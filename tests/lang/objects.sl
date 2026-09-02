// Objects: insertion order, any value as a key, `proto`, and the receiver rule.

@test
an_object_keeps_the_order_its_keys_were_written_in() =
    val o = { b: 1, a: 2, c: 3 }

    assertEq(keys(o), ["b", "a", "c"])
    assertEq(values(o), [1, 2, 3])
    assertEq(entries(o), [["b", 1], ["a", 2], ["c", 3]])
    assertEq(len(o), 3)

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
    assertEq(len(t), 6)

@test
an_integral_real_and_the_integer_share_a_key_because_they_are_equal() =
    var t = {}

    t[1] = "one"
    t[1.0] = "one again"

    assertEq(len(t), 1)
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
a_quoted_key_is_the_only_spelling_for_one_that_is_not_a_name() =
    val o = { "a.b": 1, "if": 2, end: 3 }

    assertEq(o["a.b"], 1)
    assertEq(o["if"], 2)

    // `end` is a SOFT word and arrives as an ordinary name, so it is written bare and prints bare;
    // `if` is hard and can only be quoted. That is what the printing below is saying.
    assertEq(o.end, 3)
    assertEq(string(o), "{\"a.b\": 1, \"if\": 2, end: 3}")

    // A quoted key that IS a name is the same key as the bare one.
    assertEq(len({ a: 1, "a": 2 }), 1)

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
    assertEq(len(o), 2)
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
