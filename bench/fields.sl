// Reading and writing a field of a plain object, which is the single commonest thing a program in
// any of these four languages does.
//
// **Nothing is allocated in the loop**, so what is left is the lookup: three reads and one write per
// iteration, all of them against one small object whose keys never change.

run()
    val o = { a: 0, b: 1, c: 2 }
    var i = 0

    while i < 5000000
        o.a = o.a + o.b + o.c
        i = i + 1

    o.a

print(run())
