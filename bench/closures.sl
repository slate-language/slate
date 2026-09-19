// A loop calling a small closure, which is the shape `sluice` and `lath` are written in.
//
// **The closure captures ONE name and the rest of the function is ordinary locals**, which is the
// whole of what per-name slotting claims: `scale` is read from inside `weigh`, so it has to stay
// somewhere a closure can reach, and `total`, `turns` and `weigh` itself are read only here.
//
// The loop is inside a function for the reason `arith.sl` says.

run()
    var total = 0
    var turns = 0
    val scale = 3
    val weigh = (v) -> v * scale

    while turns < 4000000
        total = total + weigh(turns)
        turns = turns + 1

    total

print(run())
