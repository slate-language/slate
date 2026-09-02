// A rest parameter and an operator a class answers for, on both back ends.
//
// The two hold both entirely differently -- the interpreter gathers the surplus into an array
// before it binds anything and looks a hook up through `field_from`, and the emitted program uses
// JavaScript's own `...` and `SObj.lookup` -- so what they print is the only thing that says they
// agree.

f(a, ...rest) = string(a) + " " + toJSON(rest)

print(f(1))
print(f(1, 2, 3))

// It composes with the spread at a call, which it had no counterpart for until now.
val args = [1, 2, 3]

print(f(...args))

// A default before it is fine, and a call that leaves the default unfilled still binds the rest.
h(a, b = 9, ...rest) = toJSON([a, b, rest])

print(h(1))
print(h(1, 2))
print(h(1, 2, 3, 4))

// A lambda, an async function and a generator each gather.
val g = (a, ...rest) -> len(rest)

print(g(1), g(1, 2, 3))

async wide(...xs) = len(xs)

gen(...xs)
    for x in xs
        yield x

// A class method and a class's own `new`.
class Tagger
    new(var name, ...tags) = 1

    say(self, ...more) = self.name + toJSON(more)

val t = Tagger("a", "x", "y")

print(t.name)
print(t.say(1, 2))

// -- an operator a class answers for --------------------------------------------------------------

class Money
    var cents

    plus(self, o) = Money(self.cents + o.cents)
    minus(self, o) = Money(self.cents - o.cents)
    times(self, n) = Money(self.cents * n)
    dividedBy(self, n) = Money(self.cents / n)
    remainder(self, n) = Money(self.cents % n)
    negated(self) = Money(-self.cents)
    compare(self, o) = self.cents - o.cents

val a = Money(500)
val b = Money(125)

print((a + b).cents, (a - b).cents, (a * 3).cents, (a / 2).cents, (a % 300).cents)
print((-a).cents)
print(a < b, a > b, a <= a, a >= a)
// `==` is structural here, `equals` being handed no receiver and so not writable as a method.
print(a == Money(500), a == b)

// A comparator answers a BOOLEAN, which is what `compare` above lets one be written from.
print(map(sorted([a, b, Money(300)], (x, y) -> x < y), m -> m.cents))

// An inherited operator, one link up the chain.
class Cents from Money
    new(var cents) = 1

print((Cents(100) + Cents(50)).cents)

// An operator the class does not answer for still says what it always said -- and names itself,
// which the six bitwise operators did not until this release.
print((a & b) catch e -> e.message)
print((-{ x: 1 }) catch e -> e.message)

async main()
    print(await wide(1, 2, 3))

    val it = gen(4, 5)

    print(next(it).value, next(it).value)

main()
