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

// -- `k in o`: true where `o[k]` finds a member, own or inherited --------------------------------------

isIn(k, o) = k in o

print(isIn("greet", g), isIn("shout", g), isIn("name", g), isIn("nope", g), has(g, "greet"))
print(isIn("x", leaf), isIn("y", leaf), isIn("w", leaf), isIn(1, child), isIn([2, 3], child), isIn(9, child))
print(isIn("toString", {}), isIn("test", Greeter), isIn("v", { v: null }))
print(isIn(0, xs), isIn(3, xs), isIn(-1, xs), isIn("length", xs), isIn("nope", xs))
print(isIn(4, "héllo"), isIn(5, "héllo"), isIn("upper", "abc"), isIn(1, toBytes("ab")), isIn("size", Set([1])))
print("a" in { a: 1 } && !("b" in { a: 1 }), "a" + "" in { a: 1 }, "a" in { a: 1 } == true)

for v in [null, 5, true, 2.5]
    try
        isIn("a", v)
    catch e
        print(e.message)

for pair in [[1.5, xs], [1, Set([1])]]
    try
        isIn(pair[0], pair[1])
    catch e
        print(e.message)

// -- `o[k](a)` passes the receiver `o.k(a)` would ---------------------------------------------------

callAt(o, k, x) = o[k](x)

print(callAt(g, "greet", 0) ?? "", g["greet"](), g[at({ m: "greet" }, "m")]())
print(callAt({ f: x -> x * 3 }, "f", 2), callAt([x -> x + 1], 0, 1))

var ys = [1]

ys["push"](2)
print(ys, ys["map"](x -> x * 10), "abc"["upper"](), g?.["greet"]())

var shared = {}
var holder = { proto: shared, tag: "t" }

shared[1] = (self, x) -> self.tag + x
holder[2] = x -> x + "!"

print(holder[1]("a"), holder[2]("b"), holder["greet"] ?? "none")

for k in ["nope", "shout"]
    try
        g[k]()
    catch e
        print(e.message)
