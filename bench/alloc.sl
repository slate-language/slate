// Many short-lived small objects, which is the benchmark that exercises the allocator and the
// collector rather than the instruction loop.
//
// **Nothing built here survives the iteration that built it**, so the live set never grows and every
// object made is garbage by the next turn. What that measures in slate is the cost of `gc.alloc`
// plus whatever the collector spends tracing a heap that is almost entirely dead -- and slate
// schedules a collection on how far the LIVE set has grown, so a well-behaved program of this shape
// should collect rarely and cheaply.

run()
    var total = 0
    var i = 0

    while i < 3000000
        val p = { x: i, y: i + 1 }

        total = total + p.x + p.y
        i = i + 1

    total

print(run())
