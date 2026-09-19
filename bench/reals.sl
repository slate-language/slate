// A tight loop over REALS, which is `arith.sl`'s question asked of the other number type. slate has
// integers and reals as separate kinds and promotes between them; Lua has the same split, and
// JavaScript has only the double. Reading the two side by side says what slate's integer arithmetic
// costs against its own real arithmetic, and what carrying two kinds costs against a host that
// carries one.
//
// The answer is printed to one decimal place rather than as a bare real, because how a language
// spells a large double is its own business and this file is about the arithmetic.

run()
    var total = 0.0
    var i = 0

    while i < 10000000
        total = total + i * 1.5 - 0.5
        i = i + 1

    total

print(run().toFixed(1))
