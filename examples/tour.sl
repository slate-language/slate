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
    null

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

// A parameter may say what it is when nobody gives one. The default is worked out at the call, so it
// can read the parameters to its left -- and an array written there is a fresh one every time.
greet(who, greeting = "hello") = greeting + ", " + who

between(xs, from, to = len(xs)) = xs[from..<to]

print(greet("ada"), greet("ada", "good day"))
print(between([1, 2, 3, 4], 1), between([1, 2, 3, 4], 1, 3))

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

print(person, person.name)

// A field that is not there reads as `undefined`, which is second class: it may be compared,
// defaulted and tested, and it may not be stored, passed or put in a container.
print(has(person, "born"), has(person, "missing"))
print(person.missing ?? "no such field")

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
//
// A bare name in a pattern tests for a kind where it names one -- `int`, `str`, `array` and the
// rest -- and binds otherwise. That is sysl's bare-name rule, whose scrutinee here is always a
// value, and `n @ pat` is sysl's spelling for testing and naming at once.
describe(v)
    v match
        0 -> "zero"
        n @ number if n < 0 -> "negative"
        n @ number -> "the number " + string(n)
        [a, b] -> "a pair summing " + string(a + b)
        { name } -> "someone called " + name
        "sat" | "sun" -> "a weekend"
        s @ string -> "the text " + s
        _ -> "something else"

print(describe(0))
print(describe(-3))
print(describe(1.5))
print(describe([3, 4]))
print(describe({ name: "ada" }))
print(describe("sun"))
print(describe("hi"))
print(describe(true))

// The syntax is sysl's. A one-line body is a *statement*, `do` introduces one for a loop, and `end`
// closes a block where the block is long enough to want it.
// A loop is an expression: `break` gives it a value, and `else` runs when it finished on its own.
find_first(xs, wanted)
    for i in 0..<len(xs) do
        if xs[i] == wanted then break i
    else
        -1
end find_first

print(find_first(["a", "b", "c"], "b"), find_first([1], 9))

// A label says which loop a `break` leaves, which is the only way out of a nested one.
first_pair_over(limit)
    'search for a in [1, 2, 3]
        for b in [1, 2, 3]
            if a * b > limit then break 'search [a, b]
    else
        null
end first_pair_over

print(first_pair_over(3))

// Compound assignment evaluates its place once; `++` and `--` step a name, a field or an element.
var counts = { hits: 0 }

counts.hits += 2
counts.hits++
print(counts, s"there were ${counts.hits} of them")

// Comparisons chain rather than associate, so this asks what it looks like it asks -- and the middle
// operand is evaluated once.
val n = 5

print(0 <= n < 10)

// A pattern where a condition is wanted, which is the same grammar a `match` arm uses.
print(n is number, n is not string, n is 1 | 3 | 5)

// Ranges are values: `for` walks one, and a subscript slices with one. An end left out is taken from
// whatever it is used on.
val letters = ["a", "b", "c", "d"]

print(letters[1..<3], letters[2..], "hello"[..2])

// A copy with a field changed, rather than a change in place.
val base = { size: 1, colour: "red" }

print(base with { size: 9 })

// An `async` function answers a promise, and `await` waits for one. Everything above a function's
// first `await` runs before its caller sees the promise; everything below it runs after the caller
// has moved on -- which is why "started both" prints before either worker's first line.
async work(name, ms, turns)
    var i = 0

    while i < turns
        await sleep(ms)
        print(name, "step", i)
        i = i + 1

    name + " finished"

async main()
    val a = work("a", 8, 3)
    val b = work("b", 20, 2)

    print("started both")
    print(await a)
    print(await b)

main()
print("the last synchronous line")
