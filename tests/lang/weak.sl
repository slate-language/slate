// A weak map and a weak reference: the surface, the key rule, and the refusals.
//
// Nothing here forces a collection, because nothing in slate can and a JavaScript host offers no way
// to ask. What the collector does with these is pinned in the compiler's own suite, where
// `collect_now` can be called directly; what belongs here is everything a program can observe on
// both back ends.

@test
a_weak_map_holds_a_value_under_an_object_key() =
    val k = { name: "a" }
    val wm = WeakMap()

    wm.set(k, 1)

    assertEq(wm.get(k), 1)
    assert(wm.has(k))
    assertEq(string(wm), "<WeakMap>")

@test
set_answers_the_weak_map_so_writes_chain() =
    val xs = [1, 2]
    val ys = [3]
    val wm = WeakMap().set(xs, "first").set(ys, "second")

    assertEq(wm.get(xs), "first")
    assertEq(wm.get(ys), "second")

@test
delete_answers_whether_there_was_one() =
    val k = { a: 1 }
    val wm = WeakMap().set(k, 1)

    assert(wm.delete(k))
    assert(!wm.delete(k))
    assert(!wm.has(k))

@test
a_missing_key_reads_as_null() =
    assertEq(WeakMap().get({ a: 1 }), null)

// A class belongs to the top level of a file, its name being a type as well as a value.
class Held
    var x

// A class whose own `hash` and `==` say that every one of its values is the same value. That is what
// a structural table asks and what identity does not.
class Boxed
    var v

    hash(self) = 7
    ==(self, other) = true

// Every kind a program keeps and hands around is a key. A closure is one, which is what makes a
// listener table possible; so is a set, a map and a class instance.
@test
every_kind_the_collector_can_free_is_a_key() =
    val f = (n) -> n
    val p = Held.new(3)
    val s = Set([1])
    val m = Map()

    assertEq(WeakMap().set(f, "closure").get(f), "closure")
    assertEq(WeakMap().set(p, "instance").get(p), "instance")
    assertEq(WeakMap().set(s, "set").get(s), "set")
    assertEq(WeakMap().set(m, "map").get(m), "map")

// **A weak map keys by IDENTITY where a map keys by what a value holds**, which is the one place the
// two tables differ. It is not a choice: a key found structurally could never be dropped, another
// equal one always being able to arrive.
@test
a_weak_map_finds_a_key_by_identity_where_a_map_finds_one_by_value() =
    val a = { n: 1 }
    val b = { n: 1 }

    assert(a == b)
    assertEq(Map().set(a, "one").get(b), "one")
    assertEq(WeakMap().set(a, "one").get(b), null)
    assertEq(WeakMap().set(a, "one").get(a), "one")
    assert(!WeakMap().set(a, "one").has(b))

// A class's own `hash` and `==` are what a structural table asks, and identity asks nothing of the
// program at all.
@test
a_classs_own_hash_and_equality_are_not_asked_by_a_weak_map() =
    val p = Boxed.new(1)
    val q = Boxed.new(2)

    assertEq(Map().set(p, "p").get(q), "p")
    assertEq(WeakMap().set(p, "p").get(q), null)
    assertEq(WeakMap().set(p, "p").get(p), "p")

@test
a_weak_reference_answers_its_target_while_something_holds_it() =
    val k = { name: "a" }
    val r = WeakRef(k)

    assertEq(r.deref(), k)
    assert(r.deref() == k)
    assertEq(string(r), "<WeakRef>")

// Identity, which is the only equality either could have: what is in a weak map is the collector's
// to change, and a weak reference's target may be gone by the time it is asked.
@test
the_weak_pair_compares_by_identity() =
    val wm = WeakMap()
    val k = { name: "a" }
    val r = WeakRef(k)

    assert(wm == wm)
    assert(wm != WeakMap())
    assert(r == r)
    assert(r != WeakRef(k))

// A key the collector could never free is refused by all four names, and by `WeakRef` too --
// JavaScript refuses only `set` and answers `undefined` or `false` for the rest, which tells a
// program that read with the wrong key nothing at all.
@test
a_key_the_collector_cannot_free_is_refused_by_every_name() =
    val wm = WeakMap()
    val said = (wm.set("a", 1)) catch e -> e.message

    assert(said.contains("must be something the collector can free"))
    assert(said.contains("and this is a string"))

    assert((wm.set(1, 1) catch e -> true))
    assert((wm.set(true, 1) catch e -> true))
    assert((wm.get(1) catch e -> true))
    assert((wm.has(1) catch e -> true))
    assert((wm.delete(1) catch e -> true))
    assert((WeakRef("a") catch e -> true))

@test
a_weak_references_target_is_refused_in_the_same_words() =
    val said = (WeakRef(3)) catch e -> e.message

    assert(said.contains("a weak reference's target must be something the collector can free"))
    assert(said.contains("and this is an integer"))

// Neither is walkable and neither has a size: what is in a weak map is the collector's to decide, so
// a walk would answer differently on two runs of one program with nothing between them.
@test
a_weak_map_has_no_size_no_clear_and_no_walk() =
    anything(v) = v

    val wm = anything(WeakMap())

    assert((wm.size catch e -> e.message).contains("`size` is not something a weak map can do"))
    assert((wm.keys() catch e -> e.message).contains("`keys` is not something a weak map can do"))
    assert((wm.clear() catch e -> e.message).contains("`clear` is not something a weak map can do"))

@test
the_two_constructors_say_what_they_take() =
    anything(v) = v

    val make = anything(WeakMap)

    assert((make(1) catch e -> e.message).contains("`WeakMap` takes nothing, and was given 1 argument"))

    val wm = anything(WeakMap())

    assert((wm.set({ a: 1 }) catch e -> e.message)
        .contains("`set` takes a weak map, a key and a value, and was given 2 arguments"))

@test
neither_has_a_json_form() =
    assert((toJSON(WeakMap()) catch e -> e.message).contains("there is no JSON for a weak map"))
    assert((toJSON(WeakRef([1])) catch e -> e.message).contains("there is no JSON for a weak reference"))
