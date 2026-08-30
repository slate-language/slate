// Defaults inside a pattern, on both back ends.
//
// Every line here turns on the one mechanism that makes them work: slate refuses to store
// `undefined`, so a name the subject did not supply is simply NOT BOUND -- and the question asked
// afterwards is about the scope rather than about the value. The machine asks it with
// `JumpIfBound`; the emitted JavaScript asks it with `=== undefined` over a slot the matcher left
// empty. They have to answer the same, and the interesting half is what they do NOT default.

val { a = 1, b } = { b: 2 }
print(a, b)

val { c: seen = "none" } = {}
print(seen)

val [x, y = 9] = [1]
print(x, y)

val [p, q = 9] = [1, 2]
print(p, q)

// A default fires on absence and on nothing else. JavaScript's `x || 1` takes the default for every
// one of these, and `x ?? 1` takes it for the null.
val { z1 = "d" } = { z1: 0 }
val { z2 = "d" } = { z2: false }
val { z3 = "d" } = { z3: "" }
val { z4 = "d" } = { z4: null }
print(z1, z2, z3, z4)

// Worked out where the binding is, so it sees what was bound to its left.
sized({ width, height = width }) = width * height
print(sized({ width: 3 }), sized({ width: 3, height: 2 }))

// And each binding gets a value of its own rather than one made once.
gather({ xs = [] }) =
    push(xs, 1)
    xs

print(gather({}), gather({}))

// A destructuring parameter, whose hidden name has to be spellable in both languages.
titled({ title = "Untitled", size = 1 }) = title + " " + string(size)
print(titled({}), titled({ title: "x" }), titled({ title: "x", size: 3 }))

// A `for` head and a `var` binding are the same unpack.
for { n, tag = "?" } in [{ n: 1 }, { n: 2, tag: "b" }]
    print(n, tag)

var { m = 5 } = {}
m = m + 1
print(m)

// A default may be a whole expression, and it is not evaluated where it is not needed.
var made = 0

fresh() =
    made = made + 1
    made

val { k1 = fresh() } = { k1: "given" }
val { k2 = fresh() } = {}
print(k1, k2, made)
