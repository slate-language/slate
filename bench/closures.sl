// A loop calling a small closure, which is the shape `sluice` and `lath` are written in and the one
// a chunk holding a lambda gave up all its cells for.
//
// **The closure captures ONE name and the rest of the function is ordinary locals**, which is the
// whole of what per-name slotting claims: `scale` is read from inside `weigh`, so it has to stay
// somewhere a closure can reach, and `total`, `turns` and `weigh` itself are read only here. Before
// this, one lambda anywhere in a body cost the body every cell it had.
//
// The loop is inside a function for the reason `arith.sl` says.
import { now } from slate:time

run()
    var total = 0
    var turns = 0
    val scale = 3
    val weigh = (v) -> v * scale

    while turns < 1000000
        total = total + weigh(turns)
        turns = turns + 1

    total

val started = now()

print(run())
print((now() - started).millis())
