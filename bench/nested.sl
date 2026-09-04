// A loop INSIDE a function that holds a closure reading one of its names, which is the shape
// ordinary slate is written in and the one `closures.sl` does not reach.
//
// **`scale` is read from inside `weigh`, so the chunk keeps a scope for it** -- and every block in
// such a chunk used to build an `EnvObj` of its own, once a turn, for names that were all cells.
// The loop head takes a pair apart into two of them and the body declares nothing at all, so what
// this measures is the scope that had nothing to hold.
import { now } from slate:time

run(pairs)
    var total = 0
    var turns = 0
    val scale = 1
    val weigh = (v) -> v * scale

    while turns < 2000
        for [a, b] in pairs
            total = total + weigh(a * b)

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
