---
title: Collections
weight: 85
---

# Collections

An array holds things in order and an object holds things under names. A **set** holds each value
once, and a **map** holds a value under any other value at all — not only under a string.

Both are built by a global of the same name, and both keep the order things arrived in.

```slate
val seen = Set(["b", "a", "b"])
val ages = Map([["ada", 36], ["alan", 41]])

print(seen, ages)
```

```output
["b", "a"] [["ada", 36], ["alan", 41]]
```

## Any value is a key

**This is the whole reason the two exist.** An object's field names are strings, so a program that
wants to count occurrences of an array, or to hold a record under a point, has to invent a spelling
for the key and hope nothing else spells the same thing. A set and a map take the value itself.

```slate
val corners = Set()

corners.add([1, 2])
corners.add([1, 2])
corners.add([1, 3])

print(corners.size, corners.has([1, 2]))
```

```output
2 true
```

**A key is compared exactly the way `==` compares it**, which is by value all the way down — so two
arrays written alike are one key. `null` is a key like any other.

```slate
val m = Map()

m.set(null, "the value null")
m.set("null", "the word")

print(m.size, m.get(null), m.get("null"))
```

```output
2 the value null the word
```

### A class that decides its own equality decides its own keys

A set finds a member by its hash and compares only the members that hashed alike. So **a class that
writes `==` must write `hash` beside it** to be usable as a key: two equal values that hashed apart
would never be compared, and the set would hold both.

```slate
class Point
    var x
    var y

    ==(self, o) = o is Point && o.x == self.x && o.y == self.y
    hash(self) = self.x * 31 + self.y

val visited = Set()

visited.add(Point(1, 2))
visited.add(Point(1, 2))

print(visited.size, visited.has(Point(1, 2)), visited.has(Point(9, 9)))
```

```output
1 true false
```

Writing `==` and leaving `hash` out is not refused — it is the rule
[Objects](objects.md) states, and a set is where breaking it shows.

## What a set can do

| | |
|---|---|
| `s.size` | how many members, a **property** and not a call |
| `s.add(v)` | adds `v`, answers the set |
| `s.has(v)` | whether `v` is in it |
| `s.delete(v)` | removes `v`, answers whether there was one |
| `s.clear()` | removes everything |
| `s.values()` | the members, as an array |
| `s.forEach(f)` | calls `f` on each member |

`add` answers the set so a chain reads as building one, and `delete` answers whether there was
something to delete so a program need not ask `has` first.

```slate
val s = Set().add(1).add(2).add(3)

print(s.delete(2), s.delete(2), s)
```

```output
true false [1, 3]
```

## What a map can do

| | |
|---|---|
| `m.size` | how many pairs, a **property** and not a call |
| `m.set(k, v)` | writes `v` under `k`, answers the map |
| `m.get(k)` | the value, or `null` where there is none |
| `m.has(k)` | whether the key is there |
| `m.delete(k)` | removes the pair, answers whether there was one |
| `m.clear()` | removes everything |
| `m.keys()`, `m.values()`, `m.entries()` | arrays |
| `m.forEach(f)` | calls `f` on each `[key, value]` pair |

**`get` answers `null` for a key that is not there, and never `undefined`** — slate
[stores no absence](values.md). `has` is what tells a stored `null` from a missing key.

```slate
val m = Map([["a", null]])

print(m.get("a"), m.get("b"), m.has("a"), m.has("b"))
```

```output
null null true false
```

**Writing a key that is already there keeps its position** and replaces the value, which is what
makes the order a map walks in the order its keys were *first* written.

```slate
val m = Map()

m.set("first", 1)
m.set("second", 2)
m.set("first", 10)

print(m.keys(), m.values())
```

```output
["first", "second"] [10, 2]
```

## `size` is a property

`s.size` and `m.size` are read with no brackets after them, as
[`.length`](values.md) is on an array or a string. Calling one is a mistake the compiler names.

```slate
print(Set([1, 2]).size())
```

```error
`size` is a property, not a method
```

**Nothing in one is at a position, which is also what `forEach` hands over.** An array's callbacks
are given the element, its index and the array — [Globals](../library/globals.md) — while a set's
`forEach` is given a member and a map's a `[key, value]` pair, and nothing else: there is no index to
give.

**`.length` is not a set's or a map's.** Neither is a sequence, nothing in one is at a position, and
a program reaching for `.length` has confused it with an array.

```slate
print(Set([1, 2]).length)
```

```error
`length` is not something a set can do
```

## Building one from anything walkable

`Set(x)` takes an array, a range, a generator, another set, or a map; `Map(x)` reads a list of
pairs, which is the shape `entries()` answers with — so `Map(m.entries())` copies a map, and so does
`Map(m)`.

```slate
print(Set([3, 1, 2, 3]))
print(Set(0..<4))
print(Set(Set([5, 6])))
print(Map(Map([["a", 1]])))
print(Set(), Map())
```

```output
[3, 1, 2]
[0, 1, 2, 3]
[5, 6]
[["a", 1]]
[] []
```

A pair is exactly two values, and anything else is named where it was found.

```slate
print(Map([["a", 1, 2]]))
```

```error
one of these has 3 values rather than a key and a value
```

## Walking one

**A set yields its members and a map yields its pairs** — one answer to "what is in this", which
`for`, `...` and `forEach` all give.

```slate
val s = Set([1, 2])
val m = Map([["a", 1], ["b", 2]])

for v in s
    print("member", v)

for [k, v] in m
    print("pair", k, v)

print([...s], [...m])
```

```output
member 1
member 2
pair a 1
pair b 2
[1, 2] [["a", 1], ["b", 2]]
```

Removing an entry does not move the ones after it, so a walk gives back what is left in the order it
was written.

```slate
val s = Set([1, 2, 3, 4, 5])

s.delete(1)
s.delete(3)

print([...s])
```

```output
[2, 4, 5]
```

## Printing, JSON, and equality

**A set prints as the array of its members and a map as the array of its pairs**, and `toJSON`
writes the same shape — one rendering rather than two, so a value written out and read back is the
same thing in both directions. (JavaScript prints `Set(2) {1, 2}`, which nothing parses, and encodes
a `Map` as `{}`, which is empty.)

```slate
print(Set([1, 2]), Map([["a", 1]]))
print(toJSON(Set([1, 2])), toJSON(Map([["a", 1], ["b", 2]])))
```

```output
[1, 2] [["a", 1]]
[1,2] [["a",1],["b",2]]
```

**A set and a map compare by IDENTITY**, as a promise and a function do. A container whose contents
can change cannot compare by them, or an answer would stop being true without either value being
touched by the code that asked.

```slate
val one = Set([1])
val other = Set([1])

print(one == one, one == other)
```

```output
true false
```

## In the type language

`Set` and `Map` are words a [pattern](patterns.md) is written with, and each takes a member type in
brackets: `Set[T]`, and `Map[K, V]`.

```slate
print(Set([1, 2]) is Set, Map([["a", 1]]) is Map, [1] is Set)
print(Set([1, 2]) is Set[integer], Set([1, "x"]) is Set[integer])
print(Map([["a", 1]]) is Map[string, integer], Map([["a", 1]]) is Map[string, string])
```

```output
true true false
true false
true false
```

**A member type is tested member by member, at run time**, which is what makes it a claim the machine
checks rather than a note to the checker — `array of T` is the same arrangement. An empty set fits
every member type, as an empty array does.

```slate
type Names = Set[string]

val bad = Set(["a", 2])

for problem in Names.mismatch(bad)
    print(problem.path, problem.wanted, problem.got)
```

```output
2 string integer
```

The [checker](types.md) reports a member type only against an annotation the program **declared**,
since the machine takes any key at all and a sharper inference would refuse programs that run.

```slate
val s: Set[string] = Set([1, 2, 3])
```

```error
declared Set[string], and this is Set[integer]
```

## A weak map does not keep its keys alive

`WeakMap()` is a table from an object to anything, and **an entry goes away by itself once nothing
else in the program holds its key**. That is the whole of what it is for: a table keyed by things
somebody else owns — a listener list keyed by node, a cache keyed by request, a bit of state keyed by
connection — would otherwise keep every one of those alive for as long as the table lived, which is
the ordinary shape of a leak.

Four names and no more: `set`, `get`, `has` and `delete`.

```slate
val node = { id: 1 }
val listeners = WeakMap()

listeners.set(node, ["click"])

print(listeners.get(node), listeners.has(node))
print(listeners.delete(node), listeners.has(node), listeners.get(node))
```

```output
["click"] true
true false null
```

**`set` answers the weak map, so writes chain**, and `get` answers `null` where there is no entry —
which is also what it answers for a key the collector has taken away. A program that has to tell
those apart is holding the key, and a program holding the key has an entry.

**A key must be something the collector can free**: an object, an array, a class instance, a closure,
a set, a map, a promise, or an [external](external.md). A number, a boolean and a string are not —
two occurrences of `"a"` are one value as far as a program can tell, so an entry keyed by one could
never be dropped, and a weak map keyed by strings is a map that leaks.

```slate
val wm = WeakMap()

wm.set("a", 1)
```

```error
a weak map's key must be something the collector can free
```

**All four names refuse such a key**, where JavaScript refuses only `set` and answers `undefined` or
`false` for the rest. A read with a key that could never have been written with is a mistake, and it
is named at the line rather than at the missing entry.

**A weak map finds a key by IDENTITY, where a map finds one by what it holds.** This is the one place
the two tables behave differently, and it is not a choice: a key found structurally could never be
dropped, since another equal one can always arrive. A class's own `hash` and `==` are what a
structural table asks, so a weak map does not consult them at all.

```slate
val a = { n: 1 }
val b = { n: 1 }

print(a == b)
print(Map().set(a, "one").get(b))
print(WeakMap().set(a, "one").get(b), WeakMap().set(a, "one").get(a))
```

```output
true
one
null one
```

**There is no `size`, no `clear`, and no way to walk one**, and none of those is an omission: what is
in a weak map is the collector's to decide, so a walk would answer differently on two runs of one
program with nothing between them, and a count is a walk that says how long it was. It prints as
`<WeakMap>` and has no JSON form.

```slate
print(WeakMap())
print(WeakMap().size)
```

```error
`size` is not something a weak map can do
```

## A weak reference holds a value without keeping it

`WeakRef(target)` is one slot rather than a table, and `deref()` answers what is in it — the target
while something else still holds it, and `null` once the collector has taken it away.

```slate
val page = { title: "Home" }
val r = WeakRef(page)

print(r, r.deref(), r.deref() == page)
```

```output
<WeakRef> {title: "Home"} true
```

**`null` and not `undefined`**, which is slate's rule rather than a choice made here: nothing that may
be a target is ever `null`, so a `null` from `deref` means gone. A target obeys the same rule a weak
map's key does, and is refused in the same words.

```slate
print(WeakRef(3))
```

```error
a weak reference's target must be something the collector can free
```

**Neither kind gives a program any way to make a collection happen**, and that is deliberate: when an
entry goes is the collector's business, and a program that could ask would be written against one
implementation of it. What either promises is only that a value held here does not, by itself, keep
anything alive.
