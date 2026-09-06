// `Set` and `Map` on both back ends.
//
// The interpreter keeps each in the very table an object is -- insertion order, structural hashing,
// and a class's own `==` and `hash` where it wrote them -- and the JavaScript runtime keeps each in
// `SObj`, which is that table again. So what this file is for is the CONSEQUENCES of that being one
// design twice: a number and a real that are equal share a key, two arrays written alike share one,
// a class with a `hash` decides its own, and the order a walk gives back is the order things went in.
//
// Reaching for the host's own `Map` and `Set` is the version of this that would have failed here:
// they key on SameValueZero, so `1` and `1.0` would be two entries, two equal arrays would be two
// keys, and a class's hooks would never be asked.
//
// **The renderings are the other half.** `print` and `toJSON` write a set as an array and a map as
// an array of pairs on both hosts, which JavaScript itself does not -- `Set(2) {1, 2}` and `{}` are
// what a JavaScript host would say, one of which nothing parses and the other of which is empty.

// -- what is in one, and in what order --------------------------------------------------------

val s = Set()

s.add("b").add("a").add("b")
print(s, s.size(), len(s), s.values())
print(s.has("a"), s.has("z"), s.delete("a"), s.has("a"), s.size())

val t = Set([3, 1, 2, 3, 1])

print(t, t.size())

for v in t
    print("member", v)

t.forEach(v -> print("each", v))
print([...t], [...t, 99])

// -- a map, whose entries are pairs -------------------------------------------------------------

val m = Map()

m.set("first", 1).set("second", 2).set("first", 10)
print(m, m.size(), m.get("first"), m.get("missing"), m.has("second"))
print(m.keys(), m.values(), m.entries())

for [k, v] in m
    print("pair", k, v)

m.forEach(p -> print("each", p))
print([...m])
print(m.delete("first"), m.delete("first"), m.size(), m)

// -- what counts as the same key ----------------------------------------------------------------

// **An integer and a real that are numerically equal are ONE key**, because `==` says they are
// equal. A JavaScript `Map` keyed the host's way would make these two entries.
val numbers = Map()

numbers.set(1, "integer").set(1.0, "real")
print(numbers.size(), numbers.get(1), numbers.get(1.0))

// **Two arrays written alike are one key**, slate comparing them by what they hold.
val structural = Set()

structural.add([1, 2]).add([1, 2]).add([1, 3])
print(structural, structural.size(), structural.has([1, 2]))

// `null` is a value like any other and may be a key.
val nulls = Map()

nulls.set(null, "absent nothing")
print(nulls.has(null), nulls.get(null), nulls.size())

// **A class that writes `==` should write `hash` beside it, and a set is where that matters**: the
// table finds a member by its hash and only then compares, so two equal values that hashed apart
// would never meet.
class Point
    var x
    var y

    ==(self, o) = o is Point && o.x == self.x && o.y == self.y
    hash(self) = self.x * 31 + self.y

val points = Set()

points.add(Point(1, 2)).add(Point(1, 2)).add(Point(3, 4))
print(points.size(), points.has(Point(1, 2)), points.has(Point(9, 9)))

val byPoint = Map()

byPoint.set(Point(1, 2), "origin-ish").set(Point(1, 2), "written over")
print(byPoint.size(), byPoint.get(Point(1, 2)))

// -- built from something else -------------------------------------------------------------------

print(Set(0..<4), Set(Set([5, 6])), Map(Map([["z", 9]])))
print(Set([]), Map([]), Set().size(), Map().size())

// -- what a set and a map ARE, as a test and as an annotation ------------------------------------

print(t is Set, t is Map, m is Map, m is Set, [1] is Set)
print(Set([1, 2]) is Set[integer], Set([1, 2]) is Set[string], Set() is Set[string])
print(Map([[1, "a"]]) is Map[integer, string], Map([[1, "a"]]) is Map[string, string])

val annotated: Map[string, integer] = Map([["n", 1]])

print(annotated)

// -- clearing, and the rendering both hosts owe --------------------------------------------------

val emptied = Set([1, 2, 3])

emptied.clear()
print(emptied, emptied.size())
print(toJSON(Set([1, 2])), toJSON(Map([["a", 1], ["b", 2]])))
print(toJSON(Set()), toJSON(Map()))
print(toJSON(Map([["a", 1]]), 2))
print(string(Set([1, 2])), string(Map([["a", 1]])))

// **Identity, not contents.** Two sets holding the same members are two sets, which is the rule a
// mutable container has to take: an equality that walked them would stop being true without either
// value being touched by the code that asked.
val one = Set([1])
val other = Set([1])

print(one == one, one == other, one != other)

// -- what each refuses ---------------------------------------------------------------------------

anything(v) = v

try
    print(Set(anything(1)))
catch e
    print(e.message)

try
    print(Map(anything([1])))
catch e
    print(e.message)

try
    print(Map(anything([["a", 1, 2]])))
catch e
    print(e.message)

try
    print(anything(Set()).get("a"))
catch e
    print(e.message)

try
    print(len(anything(true)))
catch e
    print(e.message)
