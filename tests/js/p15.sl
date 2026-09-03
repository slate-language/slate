// A function declaration is hoisted, and a keyword may name a field.
//
// **Both are JavaScript's rules taken deliberately**, so this is the file that says the two back
// ends agree about them rather than each doing something reasonable.

val sink = written

written(r) = "wrote " + string(r)

print(sink(1))

outer()
    val f = inner

    inner(x) = x * 2

    f(21)

print(outer())

// **A `val` initialiser is still sequential**, which is the half that keeps a program's data flow
// readable: what is above may be read and what is below may not.
val order = []

push(order, "before")

later() = "later"

push(order, later())

print(order)

val o = { with: 1, if: 2, match: 3, class: 4, plain: 5 }

print(o.with, o.if, o.match, o.class, o.plain)
print(toJSON(o))
print((o with { if: 9 }).if)

val { with: w, if: i } = o

print(w, i)
