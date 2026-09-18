// Actors, run as one program on both back ends.
//
// **The language suite already asserts what a program can see about an actor**
// (`tests/lang/actors.sl`), and this is the other half: a program `slate js` writes to a FILE and
// node runs, which is the path a worker's own start goes through -- a node worker is the bundle read
// back from the file it was written to, and no test of a suite can exercise that.
//
// Nothing here prints a handle. An actor's number is the interpreter's slot on one side and a
// worker's id on the other, and a corpus file is a comparison of what was printed.

import { spawn, send, ask, done, stop, transfer, me } from slate:actor

class Point
    var x
    var y

data Shape
    Circle(r)
    Rect(w, h)

actor Ledger
    var name
    var entries = []

    on record(self, amount, note)
        self.entries.push({ amount: amount, note: note })

    on total(self) = self.entries.reduce((sum, e) -> sum + e.amount, 0)

    on report(self) = s"${self.name}: ${self.entries.length} entries"

actor Mover
    on shift(self, p, by) = Point.new(p.x + by, p.y + by)

    on wider(self, s) = s match
        Circle(r) -> Circle(r * 2)
        Rect(w, h) -> Rect(w * 2, h)

actor Sizer
    on size(self, b) = b.length

    on ring(self, o) = o.self.self.name

actor Brittle
    on burst(self)
        throw "it broke"

val l = spawn(Ledger, "petty cash")

send(l.record, 5, "stamps")
send(l.record, 12, "coffee")

print(await ask(l.total))
print(await ask(l.report))

val m = spawn(Mover)
val moved = await ask(m.shift, Point.new(1, 2), 10)

print(moved is Point, moved.x, moved.y)

val bigger = await ask(m.wider, Rect(3, 4))

print(bigger is Rect, bigger is Shape, bigger.w, bigger.h)

val s = spawn(Sizer)
val copied = toBytes("hello")
val gone = toBytes("goodbye")

print(await ask(s.size, copied), copied.length)
print(await ask(s.size, transfer(gone)), gone.length)

val ring = { name: "a" }

ring.self = ring

print(await ask(s.ring, ring))

val b = spawn(Brittle)
val ended = done(b)

try
    await ask(b.burst)
catch e
    print("asked: " + e.message)

try
    await ended
catch e
    print("done: " + e.message)

val q = spawn(Ledger, "last")

send(q.record, 1, "one")
stop(q)

print(await done(q))
