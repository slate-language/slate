// A slate key is ANY VALUE, and the JavaScript back end could not do this at all: an `SObj` was a
// `Map` of strings, so `t[[1, 2]]` was refused with *"an object is indexed by a string"* -- and a
// `hash` hook was therefore unreachable under `slate js`, an object never getting as far as being a
// key. The table underneath is slots now: a scalar is its own, and anything else is hashed and then
// settled by `eq`.

var t = {}
t[[1, 2]] = "array key"
t[{a: 1}] = "object key"
t[1] = "one"
t[1.0] = "one again"
t["s"] = "string"
t[true] = "bool"
t[null] = "null"
print(t[[1, 2]], t[{a: 1}], t[1], t["s"], t[true], t[null], len(t))
print(keys(t))

class K
    var v

    hash(self) = 7
    equals(self, o) = o is K

var u = {}
u[K.new(1)] = "first"
u[K.new(2)] = "second"
print(u[K.new(9)], len(u))

data Shape
    Circle(r)

var d = {}
d[Circle(3)] = "circle three"
print(d[Circle(3)], has(d, Circle(4)))
