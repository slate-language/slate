// A binding may take a value apart, using the same patterns a `match` arm is written with.

val [x, y] = [3, 4]

print("point:", x, y)

val { name, born } = { name: "Ada Lovelace", born: 1815 }

print(name, "was born in", born)

// The long form renames; `{ name }` is shorthand for `{ name: name }`.
val { name: who, born: year } = { name: "Grace Hopper", born: 1906 }

print(who, year)

// Nesting and `...` come for free, being the patterns slate already had.
val [first, ...rest] = [1, 2, 3, 4]

print("first:", first, "rest:", rest)

val { at: { row, col } } = { at: { row: 12, col: 5 } }

print("at", row, col)

// A `for` head takes each element apart the same way, which is what `entries` is for.
val counts = { apples: 3, pears: 7, plums: 2 }

for [fruit, n] in entries(counts)
    print(fruit, "->", n)

for [a, b] in [[1, 2], [3, 4]]
    print(a + b)

// A `var` binding introduces names that may be written to; a `val` does not.
var [head, tail] = [1, [2, 3]]

head = head * 10
print(head, tail)

// A binding has no next arm to try, so a value that does not fit is a fault rather than an
// `undefined` that travels. Each half of the mismatch gets its own sentence:
//
//     val [a, b] = [1]        this binding takes 2 elements out of an array, and this one has 1
//     val { a } = { b: 1 }    this object has no field called `a`, which this binding takes out of it
//     val [a] = 5             this binding takes an array apart, and this is an integer

// `?.` reads a field only where there is something to read it from, and answers `null` otherwise.
// It guards its own link and not the rest of the chain, so each place absence is allowed says so.

val config = { server: { port: 8080 } }

print(config?.server?.port)
print(config?.database?.port ?? 5432)
