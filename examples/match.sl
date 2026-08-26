// Patterns, which is the biggest thing slate takes from Scala.

// A literal arm, a binding arm, and a wildcard.
describe(x)
    x match
        0 -> "zero"
        1 -> "one"
        n if n < 0 -> "negative"
        _ -> "many"

print(describe(0), describe(1), describe(-5), describe(9))

// Alternatives. No alternative may bind, so every one of these is a literal.
weekend(day)
    day match
        "sat" | "sun" -> true
        _ -> false

print(weekend("sat"), weekend("wed"))

// Array patterns, by shape and by length.
sum_pair(xs)
    xs match
        [] -> 0
        [a] -> a
        [a, b] -> a + b
        [first, ...rest] -> first + sum_pair(rest)

print(sum_pair([]), sum_pair([7]), sum_pair([3, 4]), sum_pair([1, 2, 3, 4]))

// Object patterns match an object with at least these fields, and `{ name }` is shorthand
// for `{ name: name }`.
greet(who)
    who match
        { name, title } -> "dear " + title + " " + name
        { name } -> "hello " + name
        _ -> "hello stranger"

print(greet({ name: "ada", title: "countess" }))
print(greet({ name: "ada" }))
print(greet({ born: 1815 }))

// Patterns nest, and a guard reads what the pattern bound.
classify(v)
    v match
        { kind: "point", at: [0, 0] } -> "origin"
        { kind: "point", at: [x, y] } if x == y -> "diagonal"
        { kind: "point", at: [_, _] } -> "somewhere"
        [_, ...] -> "a list"
        _ -> "something else"

print(classify({ kind: "point", at: [0, 0] }))
print(classify({ kind: "point", at: [3, 3] }))
print(classify({ kind: "point", at: [1, 2] }))
print(classify([1, 2, 3]))
print(classify("hi"))

// A match is an expression, so it feeds straight into anything.
val labels = []

for n in [1, 2, 3, 4, 5]
    push(labels, n % 3 match
        0 -> "fizz"
        _ -> str(n))

print(labels)
