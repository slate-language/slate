// Sorting an array of 20,000 numbers, two hundred times.
//
// **This is the one benchmark whose work is almost entirely a BUILTIN's**, which is what makes it
// worth having: `sorted` is compiled sysl doing the comparisons itself, so the instruction loop runs
// a hundred times rather than twenty million. Read beside the others it says how much of slate's
// distance from Lua is the machine and how much is everything else.
//
// The numbers come from a multiplicative generator whose products stay inside 2^53, so every
// language sees the same array.

build(n)
    var xs = []
    var seed = 1
    var i = 0

    while i < n
        seed = (seed * 16807) % 2147483647
        push(xs, seed)
        i = i + 1

    xs

run()
    val xs = build(20000)
    var total = 0
    var turns = 0

    while turns < 200
        val ys = xs.sorted()

        total = total + ys[0] + ys[19999]
        turns = turns + 1

    total

print(run())
