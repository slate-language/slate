// `toExponential` and `toPrecision` over a corpus of values, on both back ends.
//
// **The two halves are implemented differently on purpose and this is what says they agree.** The
// interpreter rounds with whole-number arithmetic out of `sysl.math.bigint`, because C's `printf`
// settles a tie on the even digit where ECMAScript settles it away from zero; a JavaScript host has
// the rule already and is handed the real. An INTEGER is neither: a slate integer is 64 bits, so
// both ends take its digits off the integer itself rather than through a double, and the values
// past `2^53` below are what pins that.
//
// **The band a layout is chosen in is the other half.** `toPrecision` goes exponential outside
// `-6 <= e < p`, which moves with the number of digits asked for -- so the same value is written
// three ways in the sweep below, and a back end that read the band off the magnitude alone would
// differ on most of them.

val reals = [0.0, 0.0 * -1.0, 1.0, 1.5, 2.5, 0.5, 0.1, 0.125, 1.25, 1.35, 1.45, 1.005, 9.99,
    123.456, 1234.5678, 0.000123, 0.0000001, 0.000000123, 3.141592653589793, 2.718281828459045,
    -1.5, -2.5, -0.1, -123.456, -0.000123, 1e21, 1.5e21, 1e-7, 6.02e23, 1.6e-19,
    1.7976931348623157e308, 5e-324, 2.2250738585072014e-308, 0.3333333333333333]

val wholes = [0, 1, 7, 10, 100, 120, 255, 999, 1000, 123456, -255, -1000000,
    9007199254740993, -9007199254740993, 4611686018427387904]

// -- as many digits as the value needs --------------------------------------------------------------

for x in reals
    print(toExponential(x), toPrecision(x))

for n in wholes
    print(toExponential(n), toPrecision(n))

// -- an exact number of digits ------------------------------------------------------------------------

for x in reals
    print(toExponential(x, 0), toExponential(x, 1), toExponential(x, 2), toExponential(x, 5))

for x in reals
    print(toExponential(x, 10), toExponential(x, 17), toExponential(x, 30))

for n in wholes
    print(toExponential(n, 0), toExponential(n, 2), toExponential(n, 6), toExponential(n, 20))

// -- an exact number of significant digits ------------------------------------------------------------

for x in reals
    print(toPrecision(x, 1), toPrecision(x, 2), toPrecision(x, 3), toPrecision(x, 6))

for x in reals
    print(toPrecision(x, 10), toPrecision(x, 17), toPrecision(x, 21))

for n in wholes
    print(toPrecision(n, 1), toPrecision(n, 3), toPrecision(n, 8), toPrecision(n, 25))

// -- the widest counts either of them takes -----------------------------------------------------------

print(toExponential(1.5, 100))
print(toPrecision(1.5, 100))
print(toExponential(0, 100))
print(toPrecision(0, 100))

// -- as methods ---------------------------------------------------------------------------------------

print((255).toExponential(2), (0.1).toExponential(), (123.456).toPrecision(4), (1.5).toPrecision())

// -- and how each of them refuses ---------------------------------------------------------------------

print(toExponential(1, -1) catch e -> e.message)
print(toExponential(1, 101) catch e -> e.message)
print(toPrecision(1, 0) catch e -> e.message)
print(toPrecision(1, 101) catch e -> e.message)
print(anything(toExponential)(1, "two") catch e -> e.message)
print(anything(toPrecision)("x", 2) catch e -> e.message)
print(anything(toExponential)() catch e -> e.message)

// A call through a value is what gets a wrong type past the checker, the signature refusing one
// where it can see it.
anything(v) = v
