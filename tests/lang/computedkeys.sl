// What `o[k]` reads, which is what `o.k` reads for the same name -- JavaScript's rule.
//
// **A computed name finds an inherited member exactly as the written one does**: a method a class
// shares through `proto`, a `get`, a field up a hand-built chain, and the universal methods. A key
// that is not a string walks the same chain by the key itself. **Everything that reports what an
// object HOLDS stays its own**, as in JavaScript: `has` is `Object.hasOwn`, `keys` and `entries`
// list the object's own fields, and `o[k] = v` writes the object's own entry. A string key on a
// builtin kind reads what `.` reads there too, so `xs["length"]` is the length.

class Greeter
    var name

    greet(self) = "hi " + self.name

    get shout(self) = upper(self.name)

anything(v) = v

at(o, k) = o[k]

// -- a class instance ------------------------------------------------------------------------------

@test
A_METHOD_A_CLASS_SHARES_IS_FOUND_BY_A_COMPUTED_NAME_AS_IT_IS_BY_A_WRITTEN_ONE()
    val g = Greeter.new("ann")

    assert(at(g, "greet") is function)
    assert(at(g, "greet") == g.greet)

    // **`o.m` on its own hands back the bare function, and so does `o[k]`**: the receiver is passed
    // only by `o.m(...)`, so a method read out is handed the object it is to work on.
    assertEq(at(g, "greet")(g), "hi ann")

@test
A_PROPERTY_IS_READ_BY_A_COMPUTED_NAME()
    val g = Greeter.new("bo")

    assertEq(at(g, "shout"), "BO")
    assertEq(at(g, anything("shout")), g.shout)

@test
A_NAME_NOTHING_IN_THE_CHAIN_HAS_IS_STILL_ABSENT()
    val g = Greeter.new("cy")

    val k = anything("nope")

    assertEq(g[k] ?? "nothing", "nothing")
    assertEq({}[k] ?? "nothing", "nothing")

// -- a hand-built chain ------------------------------------------------------------------------------

@test
A_FIELD_UP_A_HAND_BUILT_CHAIN_IS_FOUND_AT_EVERY_DEPTH()
    val top = { x: 1 }
    val middle = { proto: top, y: 2 }
    val leaf = { proto: middle, z: 3 }

    assertEq(at(leaf, "x"), 1)
    assertEq(at(leaf, "y"), 2)
    assertEq(at(leaf, "z"), 3)

    // The nearest one wins, as it does for `.`.
    assertEq(at({ proto: top, x: 9 }, "x"), 9)

@test
A_KEY_THAT_IS_NOT_A_STRING_WALKS_THE_SAME_CHAIN()
    var base = {}
    var child = { proto: base }

    base[1] = "one"
    base[[2, 3]] = "pair"
    child[4] = "four"

    assertEq(at(child, 1), "one")
    assertEq(at(child, [2, 3]), "pair")
    assertEq(at(child, 4), "four")
    assertEq(child[anything(5)] ?? "nothing", "nothing")

@test
A_CIRCULAR_CHAIN_IS_A_FAULT_AND_NOT_A_HANG()
    var a = { proto: null }
    val b = { proto: a }

    a.proto = b

    assertFaults(() -> at(a, "missing"), "deep, which means it is a circle")
    assertFaults(() -> at(a, 7), "deep, which means it is a circle")

@test
THE_UNIVERSAL_METHODS_ARE_FOUND_AS_THE_DOT_FINDS_THEM()
    // JavaScript's `({})["toString"]` is a function, and so is slate's -- which is the reason an
    // object used as a dictionary of words asks `has` before trusting a read.
    val o = { a: 1 }

    assert(at(o, "toString") is function)
    assert(at(o, "toString") == o.toString)
    assertEq(at(o, "toString")(o), o.toString())

// -- what stays the object's own ---------------------------------------------------------------------

@test
has_ASKS_ABOUT_THE_OBJECTS_OWN_FIELDS_AND_NOTHING_INHERITED()
    val base = { x: 1 }
    val child = { proto: base, y: 2 }

    assert(has(child, "y"))
    assert(!has(child, "x"))
    assert(!has(Greeter.new("d"), "greet"))
    assert(!has(Greeter.new("d"), "shout"))

@test
keys_AND_entries_LIST_THE_OBJECTS_OWN_FIELDS()
    val child = { proto: { x: 1 }, y: 2 }
    var walked = []

    for [k, v] in entries(child)
        walked.push(k)

    assertEq(keys(child), ["proto", "y"])
    assertEq(walked, ["proto", "y"])
    assertEq(keys(Greeter.new("e")), ["name"])

@test
A_COMPUTED_WRITE_GOES_ON_THE_OBJECT_ITSELF()
    val base = { x: 1 }
    var child = { proto: base }

    child["x"] = 5

    assertEq(child.x, 5)
    assertEq(base.x, 1)
    assert(has(child, "x"))

@test
A_COMPOUND_WRITE_READS_THE_INHERITED_VALUE_AND_WRITES_AN_OWN_ONE()
    val base = { n: 10 }
    var child = { proto: base }

    child["n"] += 1

    assertEq(child.n, 11)
    assertEq(base.n, 10)

@test
with_AND_without_KEEP_THE_CHAIN_A_COMPUTED_READ_FOLLOWS()
    val base = { x: 1 }
    val child = { proto: base, y: 2 }

    assertEq(at(child with { y: 3 }, "x"), 1)
    assertEq(at(without(child, "y"), "x"), 1)

    // `without` takes away an own field and nothing inherited.
    assertEq(at(without(child, "x"), "x"), 1)

// -- a builtin kind ----------------------------------------------------------------------------------

@test
A_STRING_KEY_ON_A_BUILTIN_KIND_READS_WHAT_THE_DOT_READS()
    val xs = [1, 2, 3]

    assertEq(at(xs, "length"), 3)
    assertEq(at("héllo", "length"), 5)
    assertEq(at(toBytes("ab"), "length"), 2)
    assertEq(at(Set([1, 2]), "size"), 2)
    assertEq(at(Map([["a", 1]]), "size"), 1)

    assert(at(xs, "map") == xs.map)
    assertEq(at(xs, "map")(xs, x -> x * 2), [2, 4, 6])
    assert(at("abc", "upper") == "abc".upper)
    assertEq(at("abc", "upper")("abc"), "ABC")

@test
A_NAME_A_BUILTIN_KIND_DOES_NOT_HAVE_IS_STILL_THE_INDEXING_FAULT()
    assertFaults(() -> at([1, 2], "nope"), "an array is indexed by an integer, and this is a string")
    assertFaults(() -> at(null, "length"), "cannot be indexed")
