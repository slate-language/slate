// A pattern's source is not always a string literal. A sysl string literal is followed by a
// NUL the compiler can lean on; a substring view, a run-time concatenation and an astral
// string built at run time are not. `regex` has to compile all four the same way a literal
// compiles.

import { regex } from slate:regex

@test
a_pattern_sliced_from_a_longer_string_compiles_and_matches() =
    val src = "a+b)))"
    val pat = src[0..<3]
    assertEq(pat, "a+b")
    assert(regex(pat).test("aab"))

@test
a_pattern_built_by_concatenation_compiles_and_matches() =
    val pat = "a" + "+b"
    assertEq(pat, "a+b")
    assert(regex(pat).test("aab"))

@test
a_pattern_of_five_astral_characters_matches_the_same_text() =
    val text = "😀".repeat(5) + "a"
    assert(regex(text).test(text))

@test
an_empty_pattern_sliced_from_a_non_empty_string_matches_at_the_start() =
    val src = "abc"
    val pat = src[0..<0]
    assertEq(pat, "")
    val m = regex(pat).find("xyz")
    assertEq(m.start, 0)
    assertEq(m.end, 0)
    assertEq(m.text, "")
