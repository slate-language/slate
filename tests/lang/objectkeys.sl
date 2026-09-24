// An object literal builds its table from keys the compiler has already seen: each key is the
// literal's own string, hashed once when the program was compiled. What these pin is that the object
// that comes out is the same object the general write would have made -- the same order, the same
// winner for a key written twice, `proto` delegating, a big literal indexed, and every key found
// again by a lookup that hashes the key for itself.

class Pt
    var x
    var y

// A literal of more fields than a small table holds, so its table grows an index while it is built.
wide(v) = {
    k0: v, k1: v + 1, k2: v + 2, k3: v + 3, k4: v + 4, k5: v + 5, k6: v + 6, k7: v + 7,
    k8: v + 8, k9: v + 9, k10: v + 10, k11: v + 11
}

// A literal whose second value is an absence: the first key is already written when it is refused.
absentField(o) = { a: 1, b: o.nope }

@test
A_LITERAL_KEEPS_THE_ORDER_ITS_KEYS_WERE_WRITTEN_IN() =
    assertEq(keys({ z: 1, a: 2, m: 3 }), ["z", "a", "m"])

@test
A_KEY_WRITTEN_TWICE_KEEPS_ITS_FIRST_PLACE_AND_ITS_LAST_VALUE() =
    val o = { a: 1, b: 2, "a": 3 }

    assertEq(keys(o), ["a", "b"])
    assertEq(o.a, 3)
    assertEq(o.b, 2)

@test
EVERY_KEY_IS_FOUND_AGAIN_BY_A_LOOKUP_THAT_HASHES_IT() =
    val o = { alpha: 1, "two words": 2, proto: null, "": 3 }
    val names = ["alpha", "two words", "proto", ""]

    for n in names
        assert(has(o, n))

    assertEq(o["alpha"], 1)
    assertEq(o["two words"], 2)
    assertEq(o[""], 3)

@test
A_LITERAL_WITH_PROTO_DELEGATES_TO_IT() =
    val base = { greet: (self) -> "hi " + self.name }
    val o = { proto: base, name: "ann" }

    assertEq(o.greet(), "hi ann")
    assertEq(keys(o), ["proto", "name"])

@test
A_LITERAL_TOO_BIG_FOR_A_SMALL_TABLE_IS_BUILT_WHOLE() =
    for i in 0..<20
        val o = wide(i)

        assertEq(keys(o).length, 12)
        assertEq(o.k0, i)
        assertEq(o.k11, i + 11)
        assertEq(o["k7"], i + 7)

@test
A_LITERAL_BUILT_IN_A_LOOP_IS_A_FRESH_OBJECT_EACH_TURN() =
    var made = []

    for i in 0..<300
        push(made, { n: i, tag: "t" })

    made[0].n = 99

    assertEq(made[0].n, 99)
    assertEq(made[1].n, 1)
    assertEq(made[299].n, 299)
    assertEq(made[299].tag, "t")

@test
A_CLASS_INSTANCE_AND_A_LITERAL_OF_THE_SAME_FIELDS_ARE_EQUAL() =
    assertEq(keys(Pt(1, 2)), keys(Pt(3, 4)))
    assertEq({ x: 1, y: 2 }, { y: 2, x: 1 })

@test
A_VALUE_THAT_CANNOT_BE_KEPT_IS_STILL_REFUSED() =
    assert(contains(absentField({}) catch e -> e.message, "cannot be put in an object"))
