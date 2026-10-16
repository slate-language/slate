// A guarded call of a member passes the receiver its plain call would, on both back ends --
// JavaScript's rule.
//
// **`o.m?.(a)` and `o[k]?.(a)` are `o.m(a)` and `o[k](a)` where the member is there**: a method a
// class shares, a builtin kind's method and a universal one are handed `o`; a function the object
// holds itself is not. Where the member is missing the call answers null with nothing to its right
// worked out, and `o?.m(a)` and `o?.[k](a)` guard `o` the same way. A method taken off on its own
// stays unbound. The interpreter's `taken_member` and the runtime's `memberAt` are the two halves.

class Tally
    var n

    add(self, by) = self.n + by

    get doubler(self) = x -> x * 2

class Sub from Tally
    new(n) = { n: n }

    twice(self, by) = self.add(by) * 2

val t = Tally.new(10)
val s = Sub.new(1)
val gone = null
var worked = 0

arg(v) =
    worked += 1
    v

// -- the four spellings, with the member there ------------------------------------------------------

print(t.add?.(1), t["add"]?.(2), t?.add(3), t?.["add"](4))
print(s.twice?.(1), s["twice"]?.(2), s?.add(5), s.add?.(6))
print(t.doubler?.(4), { f: x -> x + 1 }.f?.(1), { f: x -> x + 1 }["f"]?.(2))
print([1, 2].map?.(x -> x * 3), "ab".upper?.(), [1]["concat"]?.([2]), t.toString?.() == t.toString())

// -- a missing member or a missing object: null, and nothing to the right worked out ------------------

print(t.nope?.(arg(1)) ?? "none", t["nope"]?.(arg(1)) ?? "none", { f: null }.f?.(arg(1)) ?? "none")
print(gone?.add(arg(1)) ?? "none", gone?.["add"](arg(1)) ?? "none", gone?.add?.(arg(1)) ?? "none")
print(worked)

// -- a chain past the call, and a key worked out once -------------------------------------------------

var keys = 0

key() =
    keys += 1
    "add"

print(t[key()]?.(1), keys, t.nope?.().x.y ?? "none", t.add?.(1).toString())

// -- a method value taken off on its own stays unbound --------------------------------------------------

val f = t.add

try
    f(1)
catch e
    print("unbound")

// -- a spread -----------------------------------------------------------------------------------------

val by = [7]

print(t.add?.(...by), t["add"]?.(...by), t.nope?.(...by) ?? "none")
