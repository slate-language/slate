// `k in o` and `o[k](a)`, which are the two questions JavaScript asks of a computed key.
//
// **`k in o` is true exactly where `o[k]` would find a member** -- own or inherited, a property, a
// shape method or a universal one -- and reads and runs nothing to say so. `has` stays the object's
// own, so the two answer differently for an inherited member, as `Object.hasOwn` and `in` do.
// **`o[k](a)` passes `o` exactly where `o.k(a)` would**: to a method a class shares and to every
// method of a builtin kind, and not to a function the object holds itself or to an array's element.

class Counter
    var n

    bump(self, by = 1) = self.n + by

    get doubled(self) = self.n * 2

    set total(self, v)
        self.n = v

class Watched
    var calls = 0

    get seen(self)
        self.calls += 1
        1

anything(v) = v

// -- `in` ------------------------------------------------------------------------------------------

@test
in_FINDS_AN_OWN_FIELD_AND_AN_INHERITED_ONE_AND_NOT_AN_ABSENT_ONE()
    val base = { x: 1 }
    val child = { proto: base, y: 2 }

    assert("y" in child)
    assert("x" in child)
    assert(!("z" in child))

    // A field holding `null` is there: `in` asks about the member, not about its value.
    assert("v" in { v: null })

@test
in_FINDS_WHAT_A_CLASS_SHARES_AND_A_PROPERTY_OF_EITHER_HALF()
    val c = Counter.new(3)

    assert("n" in c)
    assert("bump" in c)
    assert("doubled" in c)

    // A property with only a `set` is there, though reading it is a fault.
    assert("total" in c)
    assert(!("nope" in c))

@test
in_FINDS_THE_UNIVERSAL_METHODS_AND_A_SHAPE_METHOD()
    assert("toString" in {})
    assert("equals" in { a: 1 })
    assert("test" in Counter)

@test
has_IS_OWN_AND_in_IS_INHERITED()
    val base = { x: 1 }
    val child = { proto: base }

    assert("x" in child)
    assert(!has(child, "x"))
    assert(!has(Counter.new(1), "bump"))
    assert("bump" in Counter.new(1))

@test
in_RUNS_NO_GETTER()
    val w = Watched.new()

    assert("seen" in w)
    assertEq(w.calls, 0)

@test
A_KEY_THAT_IS_NOT_A_STRING_WALKS_THE_SAME_CHAIN_FOR_in()
    var base = {}
    val child = { proto: base }

    base[[1, 2]] = "pair"
    base[7] = "seven"

    assert([1, 2] in child)
    assert(7 in child)
    assert(!(8 in child))

@test
in_ON_AN_ARRAY_ASKS_ABOUT_A_POSITION_OR_A_NAME()
    val xs = [10, 20, 30]

    assert(0 in xs)
    assert(2 in xs)
    assert(!(3 in xs))
    assert(!(-1 in xs))
    assert("length" in xs)
    assert("map" in xs)
    assert(!("nope" in xs))

@test
in_ON_A_STRING_AND_ON_BYTES_ASKS_THE_SAME()
    assert(1 in "héllo")
    assert(4 in "héllo")
    assert(!(5 in "héllo"))
    assert("length" in "abc")
    assert("upper" in "abc")
    assert(1 in toBytes("ab"))
    assert(!(2 in toBytes("ab")))

@test
in_ON_ANOTHER_KIND_ASKS_ABOUT_A_NAME()
    assert("size" in Set([1]))
    assert("size" in Map([]))
    assert(!("length" in Set([1])))

@test
in_REFUSES_A_VALUE_WITH_NO_MEMBERS()
    assertFaults(() -> "a" in anything(null), "null has no members for `in` to ask about")
    assertFaults(() -> "a" in anything(5), "has no members for `in` to ask about")
    assertFaults(() -> "a" in anything(true), "has no members for `in` to ask about")
    assertFaults(() -> "a" in anything(2.5), "has no members for `in` to ask about")

@test
in_REFUSES_A_KEY_THE_CONTAINER_IS_NOT_ASKED_BY()
    assertFaults(() -> anything(1.5) in [1, 2], "about a position or a name, and this is a real")
    assertFaults(() -> anything(1) in Set([1]), "about a name, and this is an integer")

@test
in_SITS_WITH_THE_COMPARISONS()
    val o = { a: 1 }

    // Looser than arithmetic and a field read, tighter than `&&`, `||` and `!`'s operand.
    assert("a" in o && !("b" in o))
    assert("a" + "" in o)
    assertEq("a" in o == true, true)
    assertEq(if "a" in o then "yes" else "no", "yes")

    val present = "a" in o

    assertEq(present, true)

@test
A_for_HEAD_STILL_READS_in_AS_ITS_OWN()
    var seen = []

    for k in ["a", "b"]
        seen.push(k)

    for [i, x] in [[0, "z"]]
        seen.push(x)

    // An `in` inside the iterable is the operator, as it is in JavaScript's `for (x in a in b)`.
    for b in ["a" in { a: 1 }, "b" in { a: 1 }]
        seen.push(b)

    assertEq(seen, ["a", "b", "z", true, false])

// -- `o[k](a)` -------------------------------------------------------------------------------------

@test
A_COMPUTED_CALL_PASSES_THE_RECEIVER_A_WRITTEN_ONE_DOES()
    val c = Counter.new(5)
    val k = anything("bump")

    assertEq(c[k](2), c.bump(2))
    assertEq(c["bump"](), 6)

    // A read on its own is still the bare function, handed the object by whoever calls it.
    assertEq(anything(c[k])(c, 10), 15)

@test
A_COMPUTED_CALL_NAMES_ITS_ARGUMENTS_AND_SPREADS_THEM()
    val c = Counter.new(5)
    val k = anything("bump")

    assertEq(c[k](by = 4), 9)
    assertEq(c[k](...[3]), 8)

@test
A_FUNCTION_THE_OBJECT_HOLDS_IS_CALLED_WITHOUT_A_RECEIVER()
    val o = { f: x -> x * 3 }

    assertEq(o["f"](2), 6)
    assertEq(o[anything("f")](...[4]), 12)

@test
AN_ENTRY_UNDER_ANOTHER_KEY_IS_HANDED_THE_OBJECT_WHERE_A_proto_ANSWERED()
    var shared = {}
    var own = { proto: shared }

    shared[1] = (self, x) -> self.tag + x
    own[2] = x -> x + "!"
    own.tag = "t"

    assertEq(own[1]("a"), "ta")
    assertEq(own[2]("b"), "b!")

@test
A_COMPUTED_CALL_ON_A_BUILTIN_KIND_IS_ITS_METHOD()
    var xs = [1, 2]

    xs["push"](3)

    assertEq(xs, [1, 2, 3])
    assertEq(xs[anything("map")](x -> x * 2), [2, 4, 6])
    assertEq("abc"["upper"](), "ABC")

@test
AN_ARRAYS_ELEMENT_IS_CALLED_WITH_WHAT_WAS_WRITTEN()
    val fs = [x -> x + 1, (a, b) -> a * b]

    assertEq(fs[0](1), 2)
    assertEq(fs[1](3, 4), 12)

@test
A_GUARDED_COMPUTED_CALL_FOLLOWS_THE_SAME_RULE()
    val c = Counter.new(1)
    val gone = anything(null)

    assertEq(c?.["bump"](1), 2)
    assertEq(gone?.["bump"](1) ?? "none", "none")

@test
A_COMPUTED_CALL_TO_NOTHING_SAYS_SO()
    val c = Counter.new(1)

    assertFaults(() -> c[anything("nope")](), "`nope` is not a field of this object, so there is nothing to call")
    assertFaults(() -> c[anything("doubled")](), "`doubled` is a property, not a method")

// -- `o.m?.(a)` and `o[k]?.(a)` ------------------------------------------------------------------------

class Ledger
    var total

    add(self, by) = self.total + by

    // `self` reached through a guarded call: the receiver has to be the ledger, not nothing.
    report(self) = self.add?.(0)

    get adder(self) = x -> x + 100

class Branch from Ledger
    new(total) = { total: total }

    twice(self, by) = self["add"]?.(by) * 2

@test
A_GUARDED_MEMBER_CALL_PASSES_THE_RECEIVER_ITS_PLAIN_CALL_DOES()
    val l = Ledger.new(10)
    val k = anything("add")

    assertEq(l.add?.(1), l.add(1))
    assertEq(l[k]?.(2), l[k](2))
    assertEq(l?.add(3), 13)
    assertEq(l?.[k](4), 14)
    assertEq(l?.add?.(5), 15)

@test
self_IN_A_METHOD_REACHED_THROUGH_A_GUARD_IS_THE_OBJECT()
    val b = Branch.new(3)

    assertEq(b.report?.(), 3)
    assertEq(b["report"]?.(), 3)
    assertEq(b.twice?.(1), 8)
    assertEq(b?.["twice"](2), 10)

@test
A_GUARDED_CALL_OF_WHAT_THE_OBJECT_HOLDS_PASSES_NO_RECEIVER()
    val o = { f: x -> x * 3 }

    assertEq(o.f?.(2), 6)
    assertEq(o[anything("f")]?.(3), 9)

    // A `get` is read once and what it answers is called with what was written.
    assertEq(Ledger.new(0).adder?.(1), 101)

@test
A_GUARDED_CALL_ON_A_BUILTIN_KIND_IS_ITS_METHOD()
    var xs = [1, 2]

    xs.push?.(3)
    xs["push"]?.(4)

    assertEq(xs, [1, 2, 3, 4])
    assertEq("abc".upper?.(), "ABC")
    assertEq({ a: 1 }.toString?.(), { a: 1 }.toString())

@test
A_GUARDED_MEMBER_CALL_NAMES_AND_SPREADS_ITS_ARGUMENTS()
    val c = Counter.new(5)

    assertEq(c.bump?.(by = 4), 9)
    assertEq(c[anything("bump")]?.(by = 2), 7)
    assertEq(c.bump?.(...[3]), 8)
    assertEq(c["bump"]?.(...[1]), 6)
    assertEq(c.nope?.(...[1]) ?? "none", "none")

@test
A_MISSING_MEMBER_ANSWERS_NULL_AND_WORKS_OUT_NOTHING_TO_ITS_RIGHT()
    var worked = 0

    arg() =
        worked += 1
        1

    val c = Counter.new(1)
    val gone = anything(null)

    assertEq(c.nope?.(arg()), null)
    assertEq(c[anything("nope")]?.(arg()), null)
    assertEq({ f: null }.f?.(arg()), null)
    assertEq(c.nope?.(arg()).x.y, null)
    assertEq(gone?.bump(arg()), null)
    assertEq(gone?.["bump"](arg()), null)
    assertEq(gone?.bump?.(arg()), null)
    assertEq(worked, 0)

@test
A_GUARDED_MEMBER_CALL_WORKS_OUT_ITS_OBJECT_AND_KEY_ONCE()
    var keys = 0
    var made = 0

    key() =
        keys += 1
        "bump"

    make() =
        made += 1
        Counter.new(1)

    assertEq(make()[key()]?.(1), 2)
    assertEq(make().bump?.(1), 2)
    assertEq([keys, made], [1, 2])

@test
A_METHOD_TAKEN_OFF_ON_ITS_OWN_STAYS_UNBOUND()
    val f = Ledger.new(10).add

    assertEq(f(Ledger.new(1), 2), 3)

@test
A_GUARD_ANSWERS_FOR_AN_ABSENCE_AND_NOT_FOR_A_WRONG_KIND()
    val c = Counter.new(1)

    assertFaults(() -> anything(null).bump?.(1), "there is nothing here to read `bump` from")
    assertFaults(() -> { f: 3 }.f?.(), "not something that can be called")
    assertFaults(() -> anything([1]).nope?.(), "`nope` is not something an array can do")
