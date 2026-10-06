// The module `opaque.sl` is the outside of: two opaque types, one sealed and one with a bound, and
// what this file does with them. Inside here a `GlyphId` IS an integer -- no cast is written anywhere
// below -- and every way a representation becomes one, or one gives its representation back, is a
// conversion the compiler writes where this file hands a value over.

export opaque type GlyphId = integer
export opaque type Points is real = real

// A result annotation makes one.
export glyph(n: integer) -> GlyphId = n

// An operand is read as what the type is made of, and the answer is made one again.
export next(g: GlyphId) -> GlyphId = g + 1

// A value of the type handed on as itself.
export twice(g: GlyphId) -> GlyphId = next(next(g))

// A representation handed to a parameter declared with the type, in this file, is made one.
export fromFive() -> GlyphId = next(5)

// And one given back out where the representation is wanted.
export raw(g: GlyphId) -> integer = g

// A helper nobody annotated is handed the value as it is, and its operators still read it.
helper(x) = x * 2

export doubled(g: GlyphId) -> GlyphId = helper(g)

// A `return` deep in a block, which only the machine checks, converts the same way.
export bigger(a: GlyphId, b: GlyphId) -> GlyphId
    if a > b then return a

    b

// A binding declared with the type, a compound assignment to it, and a `for` over a list of them.
export counted(n: integer) -> GlyphId
    var c: GlyphId = 0

    for i in 0..<n
        c += 1

    c

export total(xs: array of GlyphId) -> integer
    var sum = 0

    for g in xs
        sum += g

    sum

export pt(x: real) -> Points = x
export add(a: Points, b: Points) -> Points = a + b

// A function that wants a bare integer, for the outside to hand a `GlyphId` to by mistake.
export square(n: integer) -> integer = n * n
