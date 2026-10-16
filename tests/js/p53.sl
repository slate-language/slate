// A subclass is built through its base on both back ends -- JavaScript's rule.
//
// **One with no `new` of its own runs the base's `new` with the same arguments**, a hand-written body
// included, with the subclass's instance as `self`; its own initialised fields go on after and its
// proto is the subclass. **One that writes its own `new` starts from what the bases' initialisers
// make**, a base field with no initialiser left absent. The base may be computed. Positional patterns
// see the subclass's own fields and none of its bases'.

class Notes
    var served = 0

    show(self, req) = 2

    bump(self)
        self.served += 1

class Archive from Notes
    show(self, req) = 4

class Vault from Archive
    var sealed = true

class Base
    var log = []

    new(var n)
        self.log.push(s"base ${n} ${self is Top}")

    describe(self) = s"${self.n} ${self.log}"

class Mid from Base
    var extra = 7

class Top from Mid
    top(self) = "top"

class Plain
    new(v) = { v: v }

class Wrapped from Plain
    twice(self) = self.v * 2

class Point
    var x
    var y

class Named from Point
    var label = "p"

class Holder
    var a
    var b = 5

class HeldOwn from Holder
    new(var z)
        self.seen = self.b

pick(flag) = if flag then Notes else Base

class Chosen from pick(false)
    var x = 1

class Shape
    describe(self) = "a shape"

class Hollow from Shape

val v = Vault()

v.bump()
print(v.show(0), v is Vault, v is Archive, v is Notes, v.served, v.sealed, Notes().served)
print(Archive() is Vault, Notes() is Archive)

val t = Top(3)

print(t.describe(), t.extra, t.top(), t is Top, t is Mid, t is Base, Base(9).describe())
print(Wrapped(5).twice(), Wrapped(5) is Wrapped, Wrapped(5) is Plain)
print("label" in Named(1, 2), Named(1, 2, "q").label, Named(1, 2) match
    Named(l) -> l
    _ -> "no")

val h = HeldOwn(1)

print(h.b, h.z, h.seen, has(h, "a"), h is Holder)

val c = Chosen(4)

print(c.n, c.x, c.log, c is Chosen, c is Base)
print(Hollow() catch e -> e.message)
