// An opaque type from the OUTSIDE: `lib/glyphs.sl` declares two, and this file may only use what that
// one exports. Everything here is a run-time fact, so both back ends have to agree on every line --
// a value carries its type, a bare representation is never one, and what it prints and encodes as is
// what it is made of.
//
// **The refusals go through `anything`**, a function nobody annotated, which is the way to hand the
// machine a value the checker cannot see the type of -- the checker refuses every one of these
// mistakes before the program runs where it CAN see, and `tests_opaque.sysl` pins that half.

import { GlyphId, Points, glyph, next, twice, fromFive, raw, doubled, bigger, counted, total, pt, add, square } from "./lib/glyphs.sl"

anything(v) = v

@test
the_declaring_file_uses_the_type_as_its_representation_with_no_cast() =
    assertEq(raw(next(glyph(41))), 42)
    assertEq(raw(twice(glyph(1))), 3)
    assertEq(raw(fromFive()), 6)
    assertEq(raw(doubled(glyph(21))), 42)
    assertEq(raw(bigger(glyph(3), glyph(7))), 7)
    assertEq(raw(counted(4)), 4)
    assertEq(total([glyph(1), glyph(2), glyph(3)]), 6)

@test
a_value_is_its_own_type_and_never_its_representation() =
    val g = glyph(5)

    assert(g is GlyphId)
    assert(!(g is integer))
    assert(!(5 is GlyphId))
    assert(!(anything(g) is number))
    assert(GlyphId.test(g))
    assert(!GlyphId.test(5))
    assertEq(GlyphId.name(), "GlyphId")

@test
a_bare_representation_is_refused_where_the_type_is_declared() =
    val said = anything(next)(41) catch e -> e.message

    assertEq(said, "`g` was declared GlyphId, and was given 41")

@test
the_representations_operators_are_not_the_outsides() =
    val g = anything(glyph(5))

    assertEq((g + 1) catch e -> e.message, "`+` does not apply to a GlyphId and an integer")
    assertEq((g.toFixed(2)) catch e -> e.message, "`toFixed` is not something a GlyphId can do")

@test
a_sealed_type_does_not_widen_back_to_its_representation() =
    val said = anything(square)(glyph(3)) catch e -> e.message

    assertEq(said, "`n` was declared integer, and was given GlyphId(3)")

@test
a_bound_lets_the_outside_use_it_as_the_bound_says() =
    val p = pt(1.5)

    assertEq(p + 1.0, 2.5)
    assertEq(sqrt(add(pt(8.0), pt(8.0))), 4.0)

    val r: real = p

    assertEq(r, 1.5)

@test
a_bound_does_not_make_the_representation_fit_the_type() =
    val said = anything(add)(1.5, pt(1.0)) catch e -> e.message

    assertEq(said, "`a` was declared Points, and was given 1.5")

@test
it_prints_and_encodes_as_what_it_is_made_of() =
    val g = glyph(41)

    assertEq(string(g), "41")
    assertEq(s"<${g}>", "<41>")
    assertEq(toJSON([g, next(g)]), "[41,42]")
    assertEq(string([g]), "[41]")

@test
two_values_are_equal_where_what_they_are_made_of_is() =
    assert(glyph(1) == glyph(1))
    assert(glyph(1) != glyph(2))
    assert(anything(glyph(1)) != 1)
    assertEq(Set([glyph(1), glyph(1), glyph(2)]).size, 2)

@test
a_value_is_true_whatever_it_is_made_of() =
    assert(if glyph(0) then true else false)
