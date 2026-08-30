class Point
    var x
    var y

    show(self) = s"(${self.x}, ${self.y})"

class Square from Point
    val kind = "square"

val p = Point.new(1, 2)
print(p.show(), p is Point)

evens()
    var n = 0
    loop
        yield n
        n = n + 2

val g = evens()
print(g.next(), g.next(), g.next())

squares()
    for i in 1..4
        yield i * i

val out = []
for v in squares()
    out.push(v)
print(out)

val base = { a: 1, b: 2 }
print(base with { b: 3, c: 4 })
print(base with { a: 9 } == { a: 9, b: 2 })

greet(name, greeting = "hello") = s"${greeting}, ${name}"
print(greet("ed"), greet("ed", "hi"))

add(a, b) = a + b
val pair = [1, 2]
print(add(...pair))

var count = 0
count++
print(count++, count)
print(-3.abs(), pow(2, 10))
