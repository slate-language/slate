// A call to a plain function of FIXED ARITY, once per iteration, and nothing else.
//
// **This is the call benchmark with everything else taken out.** `calls.sl` calls a method and
// allocates, `closures.sl` calls a lambda that reads a captured name, and `fib.sl` recurses -- so
// each of those measures a call plus something. What is left here is the frame itself: three
// arguments laid into slots, a body of one expression, and a return.

add3(a, b, c) = a + b + c

run()
    var total = 0
    var i = 0

    while i < 4000000
        total = total + add3(i, 1, 2)
        i = i + 1

    total

print(run())
