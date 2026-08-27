// A module. What another file can see is what this one writes `export` in front of, and nothing
// else -- so the constant below is this file's own however many programs import `area`.

val pi = 3.14159265358979

export area(radius) = pi * radius * radius

export circumference(radius) = 2 * pi * radius

// A module keeps state the same way anything else does: a closure over a `var` nothing exported.
var measured = 0

export measure(radius) =
    measured += 1
    { radius: radius, area: area(radius), circumference: circumference(radius) }

export howManyMeasured() = measured
