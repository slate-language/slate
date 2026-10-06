// The declaring half of `tests_opaque.sysl`'s boundary tests.
export opaque type GlyphId = integer
export opaque type Points is real = real

export glyph(n: integer) -> GlyphId = n
export next(g: GlyphId) -> GlyphId = g + 1
export pt(x: real) -> Points = x
