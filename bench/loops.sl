// A `for` over an array with a destructuring head, which is the shape ordinary slate is written in
// and the one a binding form other than `val` puts into a numbered slot.
//
// **The loop is inside a function for `arith.sl`'s reason**, and its head binds two names per turn
// through a pattern rather than one through a `val`. Every name here -- the pair the head takes
// apart, the running total, the index -- is a name the compiler can see the whole life of.

run(pairs)
    var total = 0
    var turns = 0

    while turns < 8000
        for [a, b] in pairs
            total = total + a * b

        turns = turns + 1

    total

var pairs = []
var i = 0

while i < 1000
    push(pairs, [i, i + 1])
    i = i + 1

print(run(pairs))
