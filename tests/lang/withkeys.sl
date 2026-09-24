// A `with { ... }` writes its keys the way an object literal does: each key is the program's own
// string, hashed once when the program was compiled. What these pin is that the copy that comes out
// is the one the general write would have made -- the base's order kept, the winner for a key written
// twice, `proto` delegating, a data value still refusing a field its type does not have, and every
// key found again by a lookup that hashes it for itself.

data WithShape
    WithRect(w, h)

@test
A_WITH_CHANGES_A_FIELD_IN_THE_PLACE_THE_BASE_HAD_IT() =
    val base = { a: 1, b: 2, c: 3 }
    val o = base with { b: 20, d: 4 }

    assertEq(keys(o), ["a", "b", "c", "d"])
    assertEq(o.b, 20)
    assertEq(o["d"], 4)
    assertEq(base.b, 2)

@test
A_KEY_WRITTEN_TWICE_IN_A_WITH_KEEPS_ITS_LAST_VALUE() =
    val o = { a: 1 } with { x: 1, "x": 2, a: 3 }

    assertEq(keys(o), ["a", "x"])
    assertEq(o.x, 2)
    assertEq(o.a, 3)

@test
A_WITH_THAT_WRITES_PROTO_DELEGATES_TO_IT() =
    val greeter = { greet: (self) -> "hi " + self.name }
    val o = { name: "ann" } with { proto: greeter }

    assertEq(o.greet(), "hi ann")
    assertEq(keys(o), ["name", "proto"])

@test
AN_EMPTY_WITH_IS_A_COPY() =
    val base = { a: 1 }
    val o = base with { }

    assertEq(o, base)
    o.a = 2
    assertEq(base.a, 1)

@test
A_WITH_OVER_A_BIG_OBJECT_FINDS_EVERY_KEY() =
    var base = {}

    for i in 0..<20
        base[s"k${i}"] = i

    val o = base with { k3: 30, k19: 190, k20: 200 }

    assertEq(keys(o).length, 21)
    assertEq(o.k3, 30)
    assertEq(o["k19"], 190)
    assertEq(o.k20, 200)
    assertEq(o.k0, 0)

@test
A_DATA_VALUE_TAKES_EVERY_FIELD_IT_HAS_EVEN_TWICE() =
    val r = WithRect(1, 2) with { w: 3, h: 4, w: 5 }

    assertEq(r.w, 5)
    assertEq(r.h, 4)
    assert(r is WithRect)

@test
A_DATA_VALUE_REFUSES_A_FIELD_ITS_TYPE_DOES_NOT_HAVE_AFTER_ONE_IT_HAS() =
    val said = try
        WithRect(1, 2) with { w: 3, depth: 4 }
        ""
    catch e
        e.message

    assert(contains(said, "has no field `depth`"), said)

@test
A_WITH_OVER_A_VALUE_THAT_IS_NOT_AN_OBJECT_IS_REFUSED() =
    val n = [1, 2]
    val said = try
        n with { a: 1 }
        ""
    catch e
        e.message

    assert(contains(said, "`with`"), said)
    assert(contains(said, "an object, and this is an array"), said)
