// The object model: what a value prints as, and what it means for two of them to be the same.
//
// Both back ends have to agree about every line here. The interpreter walks its own printer and its
// own equality; the emitted program walks JavaScript's `Map` and `===`, and the two arrived at these
// answers by different routes.

class Point
    var x
    var y

class Empty

class Money
    var cents

    equals(self, o) = o is Money && self.cents == o.cents
    toString(self) = "$" + string(self.cents)

data Shape
    Circle(r)
    Nothing

val p = Point.new(1, 2)
val q = Point.new(1, 2)

// A class instance names its class and its own fields; the class object says it is one.
print(p)
print(Point)
// A class that declares no fields gets no constructor, so an instance is written out --
// and it prints as the bare name, the way a variant carrying nothing does.
print({ proto: Empty })
print([p, q])

// `==` is content-based for every value, a class instance included.
print(p == q, p == p, {x: 1} == {x: 1}, [1, 2] == [1, 2])
print(Circle(3) == Circle(3), Nothing == Nothing)

// `eq` is the other question, and the only way to ask it: identity on every value that has one, and
// equality on every value that has not.
print(p.eq(q), p.eq(p), p.ne(q))
print([1, 2].eq([1, 2]), 1.eq(1), "a".eq("a"), true.eq(true), null.eq(null))

// `equals` is `==` under its own name, and the two may never disagree.
print(p.equals(q), p.equals(p), [1, 2].equals([1, 2]))

// A class that writes `equals` gets it for `==` too, and one that writes `toString` gets it
// everywhere a value is rendered.
val m = Money.new(150)

print(m == Money.new(150), m.eq(Money.new(150)))
print(m, string(m), m.toString(), s"cost $m", [m])

// `toString` on anything else is what `print` would have shown.
print((42).toString(), [1, 2].toString(), Circle(3).toString(), {a: 1}.toString())

// A tag a declaration wrote is not a field.
print(keys(Point), len(Point), keys(p), len(p))

// A DIAGNOSTIC does not run `toString` -- a message about a fault that renders its values with the
// program's own code can fault again, and the second fault is the one the reader would meet. Both
// back ends have to draw that line in the same place, and for one release they did not.
print((m match
    1 -> "one") catch e -> e.message)

print((Money.new(1) + 1) catch e -> e.message)
print(assertEq(m, 1) catch e -> e.message)

speak(v: string) = v

print(speak(m) catch e -> e.message)

// `equals` and `==` are one function, so a redefined `equals` decides both.
print(m == Money.new(150), m.equals(Money.new(150)), m == 150)

// `eq` and `ne` over every kind that has an identity and every kind that has not.
val xs = [1, 2]
val o = { a: 1 }

print(xs.eq(xs), xs.eq([1, 2]), o.eq(o), o.eq({ a: 1 }))
print(xs.ne(xs), xs.ne([1, 2]))
print(1.eq(1.0), 1.eq(2), true.ne(false), null.eq(null))

val f = (x) -> x

print(f.eq(f), f.ne(f))
