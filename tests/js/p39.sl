// How a real is WRITTEN, on both back ends.
//
// **The rule is JavaScript's `Number.prototype.toString`**: the shortest decimal that reads back as
// the same double, plain while `1e-7 <= |x| < 1e21` and an exponent outside that band. The host
// answers it directly under `slate js` and the interpreter reconstructs it from `%g`, so the two
// halves share no code at all and this file is the only thing that says they agree.
//
// **The cases are the ones where a fixed number of figures and the shortest one part company.** Six
// significant figures — what this replaced — writes every line of the first block wrong, and gets
// every line of the whole-number block right, which is why both are here.

// -- the shortest text ------------------------------------------------------------------------------

print(0.1 + 0.2)
print(1 / 3.0)
print(123456789.123)
print(3.141592653589793)
print(1.7976931348623157e308)
print(5e-324)

// -- where the plain band ends -----------------------------------------------------------------------

print(1e20, 1e21, 1.5e21)
print(1e-6, 1e-7, 1e100)

// -- a whole value, which prints as a whole number ----------------------------------------------------

print(2.0, -2.0, 100.0, 1234567.0)
print(string(1.0), string(-0.5))

// -- the values with no digits ------------------------------------------------------------------------

print(0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0)
print(0.0, -0.0)

// -- the round trip, which is what the rule is for -----------------------------------------------------

for x in [0.1 + 0.2, 1 / 3.0, 1e21, 1e-7, 1e20, 123456789.123, 1.7976931348623157e308, 5e-324, 2.0,
        -0.5, 0.000001]
    print(number(string(x)) == x)

// -- inside a structure, which goes through the same renderer -------------------------------------------

print([0.1 + 0.2, 1.5])
print({ a: 0.1 + 0.2 })
