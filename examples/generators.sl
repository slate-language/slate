// Generators: a function that hands values back one at a time and stands still in between.
//
// A function is a generator because it holds a `yield` -- there is no second word to write, which is
// Python's rule. Calling one runs nothing: the body waits until something asks it for a value.

counter(n)
    var i = 0

    while i < n
        yield i
        i = i + 1

for x in counter(3)
    print(x)

// The values are made as they are asked for, so a generator with no end is an ordinary thing to
// write and a loop that stops early costs only what it took.

naturals()
    var i = 0

    loop
        yield i
        i = i + 1

var total = 0

for k in naturals()
    if k > 10 then break

    total = total + k

print("the first eleven add to", total)

// `next` is the other way to drive one, and it answers `{ value, done }` rather than a bare value --
// `null` is a value a generator may yield, so a bare answer could not say which had happened.

val g = counter(2)

print(g.next())
print(g.next())
print(g.next())

// `yield` is an expression, and what it answers is what the caller sent in. That makes a generator a
// two-way conversation rather than only a source of values.

greeter()
    val name = yield "who?"
    val mood = yield "how is " + name + "?"

    name + " is " + mood

val chat = greeter()

print(chat.next().value)
print(chat.next("Ada").value)
print(chat.next("well").value)

// A generator's `try` blocks are its own and come back with it, so one may guard work that spans a
// yield -- and a fault it does not catch is raised where `next` was written.

fragile()
    try
        yield "fine"
        print(missing)
    catch e
        yield "recovered from: " + e.message

val f = fragile()

print(f.next().value)
print(f.next().value)

// One generator over another needs nothing but a `for`.

squares(xs)
    for x in xs
        yield x * x

for s in squares(counter(4))
    print(s)
