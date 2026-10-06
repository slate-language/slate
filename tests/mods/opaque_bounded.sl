import { glyph, next, pt, GlyphId } from "./opaque_lib.sl"

val p = pt(1.5)
val r: real = p

print(next(glyph(1)), p + 1.0, r, glyph(2) is GlyphId)
