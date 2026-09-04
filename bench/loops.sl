// A `for` over an array with a destructuring head, which is the shape ordinary slate is written in
// and the one nothing before B2 could put in a slot.
//
// **The loop is inside a function for `arith.sl`'s reason**, and its head binds two names per turn
// through a pattern rather than one through a `val`. Every name here -- the pair the head takes
// apart, the running total, the index -- is a name the compiler can see the whole life of.
import { now } from slate:time

run(pairs)
    var total = 0
    var turns = 0

    while turns < 2000
        for [a, b] in pairs
            total = total + a * b

        turns = turns + 1

    total

var pairs = []
var i = 0

while i < 1000
    push(pairs, [i, i + 1])
    i = i + 1

val started = now()

print(run(pairs))
print((now() - started).millis())
