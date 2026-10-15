// `o[k]` reads what `o.k` reads, on both back ends -- JavaScript's rule.
//
// **A computed name finds an inherited member**: a method a class shares, a `get`, a field up a
// hand-built chain, the universal methods, and a key that is not a string up the same chain. What
// reports what an object HOLDS stays its own -- `has`, `keys`, `entries` and a computed write -- and a
// string key on a builtin kind reads that kind's property or method. The interpreter's `read_at` and
// the runtime's `index` are the two halves.

class Greeter
    var name

    greet(self) = "hi " + self.name

    get shout(self) = upper(self.name)

at(o, k) = o[k]

val g = Greeter.new("ann")

// -- a class instance ------------------------------------------------------------------------------

print(at(g, "greet") is function, at(g, "greet") == g.greet, at(g, "greet")(g))
print(at(g, "shout"), g["nope"] ?? "nothing")

// -- a hand-built chain ------------------------------------------------------------------------------

val top = { x: 1 }
val leaf = { proto: { proto: top, y: 2 }, z: 3 }

print(at(leaf, "x"), at(leaf, "y"), at(leaf, "z"), at({ proto: top, x: 9 }, "x"))

var base = {}
var child = { proto: base }

base[1] = "one"
base[[2, 3]] = "pair"
child[4] = "four"

print(at(child, 1), at(child, [2, 3]), at(child, 4), child[5] ?? "nothing")

// -- the universal methods ---------------------------------------------------------------------------

val o = { a: 1 }

print(at(o, "toString") is function, at(o, "toString")(o))

// -- what stays the object's own ---------------------------------------------------------------------

var mine = { proto: { n: 10 }, y: 2 }

print(has(mine, "y"), has(mine, "n"), has(g, "greet"), keys(mine), keys(g))

mine["n"] += 1
mine["m"] = 7

print(mine.n, mine.proto.n, has(mine, "n"), keys(mine))
print(at(mine with { y: 3 }, "y"), at(without(mine, "n"), "n"))

// -- a builtin kind ----------------------------------------------------------------------------------

val xs = [1, 2, 3]

print(at(xs, "length"), at("héllo", "length"), at(toBytes("ab"), "length"))
print(at(Set([1, 2]), "size"), at(Map([["a", 1]]), "size"))
print(at(xs, "map") == xs.map, at(xs, "map")(xs, x -> x * 2), at("abc", "upper")("abc"))

try
    at(xs, "nope")
catch e
    print(e.message)

try
    at(null, "length")
catch e
    print(e.message)
