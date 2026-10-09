// `...rest` in an object pattern: the fields the pattern did not name, gathered into a NEW object.
//
// **Every site a pattern can stand in is here** -- a `val`, a `var`, a `for` head, a parameter, a
// `match` arm and an `is` -- because each reaches the matcher by its own path, and on the
// interpreter a binding site lays its names into cells in `pattern_names`' order, which is the order
// the rest has to be counted in. What the rest holds of a class or data value is what `keys` walks.

class Pt
    var x
    var y

data Shape
    Circle(r)
    Rect(w, h)

@test
A_REST_HOLDS_THE_FIELDS_THE_PATTERN_DID_NOT_NAME() =
    val o = { a: 1, b: 2, c: 3 }
    val { b, ...rest } = o

    assertEq(b, 2)
    assertEq(rest, { a: 1, c: 3 })
    assertEq(keys(rest), ["a", "c"])

@test
A_REST_IS_A_NEW_OBJECT_AND_THE_SUBJECT_IS_UNTOUCHED() =
    val o = { a: 1, b: 2 }
    var { a, ...rest } = o

    rest.b = 20

    assertEq(o, { a: 1, b: 2 })
    assertEq(rest, { b: 20 })

    rest = { gone: true }

    assertEq(rest, { gone: true })

@test
A_REST_WITH_NOTHING_LEFT_OVER_IS_AN_EMPTY_OBJECT() =
    val { a, b, ...rest } = { a: 1, b: 2 }

    assertEq(rest, {})
    assertEq(keys(rest).length, 0)

    val { ...all } = { a: 1 }

    assertEq(all, { a: 1 })

@test
A_DEFAULT_BESIDE_A_REST_IS_LEFT_OUT_OF_IT_WHETHER_OR_NOT_IT_WAS_USED() =
    val { a = 5, ...rest } = { b: 2 }

    assertEq(a, 5)
    assertEq(rest, { b: 2 })

    val { c = 5, ...more } = { c: 1, d: 2 }

    assertEq(c, 1)
    assertEq(more, { d: 2 })

@test
A_REST_OF_A_CLASS_INSTANCE_IS_A_PLAIN_OBJECT_OF_ITS_OWN_FIELDS() =
    val { x, ...rest } = Pt(1, 2)

    assertEq(x, 1)
    assertEq(rest, { y: 2 })
    assertEq(keys(rest), ["y"])
    assert(!(rest is Pt))

@test
A_REST_OF_A_DATA_VALUE_IS_A_PLAIN_OBJECT_OF_ITS_FIELDS() =
    val { w, ...rest } = Rect(3, 4)

    assertEq(w, 3)
    assertEq(rest, { h: 4 })
    assert(!(rest is Shape))

    val { ...all } = Circle(2)

    assertEq(all, { r: 2 })

@test
A_PROTO_A_PROGRAM_WROTE_IS_A_FIELD_AND_COMES_ALONG_AS_KEYS_SAYS() =
    val base = { m: 1 }
    val { n, ...rest } = { proto: base, n: 2 }

    assertEq(n, 2)
    assertEq(keys(rest), ["proto"])

@test
A_FIELD_A_PROTO_SUPPLIES_IS_MATCHED_BUT_NOT_GATHERED() =
    val base = { m: 1 }
    val { m, ...rest } = { proto: base, n: 2 }

    assertEq(m, 1)
    assertEq(keys(rest), ["proto", "n"])

@test
NESTED_RESTS_EACH_TAKE_THEIR_OWN_LEFTOVERS_IN_ORDER() =
    val { p: { a, ...inner }, q, ...outer } = { p: { a: 1, b: 2 }, q: 3, r: 4 }

    assertEq(a, 1)
    assertEq(inner, { b: 2 })
    assertEq(q, 3)
    assertEq(outer, { r: 4 })

    val [{ k, ...first }, second] = [{ k: 1, v: 2 }, 3]

    assertEq([k, first, second], [1, { v: 2 }, 3])

taken({ id, ...more }) = [id, more]

@test
A_PARAMETER_TAKES_A_REST() =
    assertEq(taken({ id: 7, name: "ada", age: 36 }), [7, { name: "ada", age: 36 }])

    val f = ({ a, ...r }) -> r

    assertEq(f({ a: 1, z: 26 }), { z: 26 })

@test
A_FOR_HEAD_TAKES_A_REST() =
    var seen = []

    for { id, ...more } in [{ id: 1, x: 2 }, { id: 2 }]
        seen.push([id, more])

    assertEq(seen, [[1, { x: 2 }], [2, {}]])

@test
A_MATCH_ARM_TAKES_A_REST_AND_STILL_MATCHES_PARTIALLY() =
    val classify = (op) -> op match
        { kind: "sub", ...r } -> ["sub", r]
        { kind: "add", ...r } -> ["add", r]
        _ -> ["other"]

    assertEq(classify({ kind: "add", a: 1, b: 2 }), ["add", { a: 1, b: 2 }])
    assertEq(classify({ kind: "sub" }), ["sub", {}])
    assertEq(classify(5), ["other"])

@test
AN_is_TEST_TAKES_A_REST() =
    val o = { a: 1, b: 2 }

    if o is { a, ...rest }
        assertEq(rest, { b: 2 })
    else
        assert(false)

    assert(!(5 is { a, ...nothing }))

@test
A_REST_CAPTURED_BY_A_CLOSURE_IS_THE_ONE_THAT_WAS_BOUND() =
    val keep = (o) ->
        val { a, ...r } = o
        () -> [a, r]

    assertEq(keep({ a: 1, b: 2 })(), [1, { b: 2 }])
