val n = 3
print(n match
    1 -> "one"
    2 | 3 -> "few"
    k -> s"many ${k}")

describe(v) = v match
    [a, b] -> s"pair ${a} ${b}"
    [first, ...rest] -> s"${first} then ${rest}"
    { name, age } -> s"${name} is ${age}"
    integer -> "an integer"
    _ -> "something else"

print(describe([1, 2]))
print(describe([1, 2, 3]))
print(describe({ name: "ed", age: 40 }))
print(describe(7))
print(describe("x"))

val r = 1..5
print(r, [1,2,3,4,5][1..<3])

var total = 0
for i in 1..10
    if i % 2 == 0
        continue
    total += i
print(total)

'outer for i in 1..3
    for k in 1..3
        if k == 2 then break 'outer
print("broke out")

counter() =
    var c = 0
    () -> 
        c += 1
        c
val next = counter()
print(next(), next(), next())

risky()
    throw "gone wrong"
val said = try
    risky()
catch e
    e
print(said)

val faulted = try
    val bad = [1][5]
    "no"
catch e
    e.message
print(faulted)

print(toJSON({ a: [1, 2], b: "x" }))
print(parseJSON("{\"k\": [1, 2.5, null]}"))
print([3, 1, 2].sorted(), "abc".upper(), [1,2,3].sum())
