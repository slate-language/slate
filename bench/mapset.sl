// A `Map` and a `Set` written to in a loop and then read back.
//
// **slate's `Map` and `Set` are the object's own table under another name**, so they hash
// structurally and consult a class's `==` and `hash`; they are not the host's. Lua has one
// associative structure and no set at all, so its twin uses a table for each -- which is the honest
// comparison, that being what a Lua program would write.

run()
    val m = Map()
    val s = Set()
    var i = 0

    while i < 2000000
        m.set(i % 1000, i)
        s.add(i % 1000)
        i = i + 1

    var total = 0
    var k = 0

    while k < 1000
        total = total + m.get(k)

        if s.has(k) then total = total + 1

        k = k + 1

    total

print(run())
