val xs = [1, 2, 3]
print(xs)
print(7 / 2, 7 \ 2, -7 \ 2, 4 / 2, 7 % 2, 2.5 + 1)
print(4 / 2 is integer, 7 \ 2 is integer, 1 / 0, -1 / 0, 7 == (7 \ 2) * 2 + 7 % 2)
var quotient = 17
quotient \= 5
print(quotient, "a\\b".length)
print("hi" + " there", "日本語".length, "日本語"[1])
val o = { a: 1, b: [1, { c: "x" }] }
print(o, keys(o), o.b[1].c)
print([1, 2] == [1, 2], 1 == 1.0, 0 == false)
var i = 0
while i < 3
    i += 1
print(i)
double(x) = x * 2
print(double(21))
print(xs.map(x -> x * 2))
