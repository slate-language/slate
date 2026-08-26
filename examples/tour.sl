// slate, in one file.

val name = "slate"
var n = 0

print("hello from", name)

// A function has no keyword: the shape is what identifies it.
double(x) = x * 2

add(a, b)
    a + b

print(double(21), add(40, 2))

// A block's value is its trailing expression, so `return` is for leaving early.
grade(mark)
    if mark >= 90
        "A"
    elif mark >= 80
        "B"
    else
        "C"

print(grade(95), grade(85), grade(70))

first_even(xs)
    for x in xs
        if x % 2 == 0
            return x
    nil

print(first_even([1, 3, 6, 7]))

// Closures capture a scope, and keep seeing writes to it.
counter()
    var count = 0
    bump()
        count = count + 1
        count
    bump

val c = counter()

print(c(), c(), c())

// Functions are values.
apply_twice(f, v) = f(f(v))

print(apply_twice(x -> x * 3, 2))

// Arrays and objects are reference types, and compare by their contents.
val xs = [1, 2, 3]
val ys = xs

push(ys, 4)

print(xs, len(xs), xs == [1, 2, 3, 4])

val person = { name: "ada", born: 1815 }

person.born = 1816

print(person, person.name, person.missing)

// The loops.
while n < 3
    n = n + 1

print("counted to", n)

loop
    n = n + 1
    if n > 5
        break

print("ended at", n)

// `match` is postfix, as in Scala and sysl: a transformation of the thing to its left.
describe(v)
    v match
        0 -> "zero"
        [a, b] -> "a pair summing " + str(a + b)
        { name } -> "someone called " + name
        "sat" | "sun" -> "a weekend"
        _ -> "something else"

print(describe(0))
print(describe([3, 4]))
print(describe({ name: "ada" }))
print(describe("sun"))
print(describe(9))

// A guard runs after the pattern has bound, and can refuse the arm so a later one gets its turn.
sign(n)
    n match
        0 -> "zero"
        n if n < 0 -> "negative"
        _ -> "positive"

print(sign(0), sign(-3), sign(3))
