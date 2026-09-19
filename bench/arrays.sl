// An array built by pushing, then read back by index, then walked by a `for` -- the three things a
// program does to an array, measured in one file so the cost of growing one can be read beside the
// cost of reading one.
//
// **The build happens once and the two walks happen five times each**, because growing an array is
// amortised and reading one is not: a build big enough to dominate would say nothing about the reads
// that follow it, which is what ordinary code spends its time on.

build(n)
    var xs = []
    var i = 0

    while i < n
        push(xs, i * 2)
        i = i + 1

    xs

by_index(xs)
    var total = 0
    var i = 0

    while i < xs.length
        total = total + xs[i]
        i = i + 1

    total

by_walk(xs)
    var total = 0

    for v in xs
        total = total + v

    total

run()
    val xs = build(500000)
    var total = 0
    var turns = 0

    while turns < 10
        total = total + by_index(xs) + by_walk(xs)
        turns = turns + 1

    total

print(run())
