// Strings: counted in characters, and ASCII where a case or a space rule has to draw a line.

@test
a_string_is_counted_in_characters_and_not_in_bytes() =
    assertEq(len("日本語"), 3)
    assertEq(len("héllo"), 5)
    assertEq(len(toBytes("日本語")), 9)

@test
a_character_is_a_string_of_one() =
    assertEq("日本語"[0], "日")
    assertEq("héllo"[1], "é")
    assertEq(chars("abc"), ["a", "b", "c"])

@test
slicing_is_by_character_too() =
    assertEq("日本語"[0..<2], "日本")
    assertEq("héllo"[1..<3], "él")

@test
case_is_ascii_only_and_that_is_deliberate() =
    // A case mapping that is right needs a table, a locale and a rule for the characters whose
    // upper case is two characters. slate says where its line is instead of half-doing it.
    assertEq(upper("héllo"), "HéLLO")
    assertEq(lower("HÉLLO"), "hÉllo")
    assertEq(upper("abc123"), "ABC123")

@test
trimming_is_ascii_whitespace_only() =
    assertEq(trim("  x\t\n"), "x")
    assertEq(trimStart("  x  "), "x  ")
    assertEq(trimEnd("  x  "), "  x")

    // A non-breaking space is not ASCII whitespace, so it stays.
    assertEq(trim(" \u{a0}x "), "\u{a0}x")

@test
searching_answers_null_for_a_miss_and_not_a_negative_number() =
    assertEq(indexOf("abcabc", "b"), 1)
    assertEq(indexOf("abcabc", "z"), null)
    assertEq(lastIndexOf("abcabc", "b"), 4)
    assertEq(lastIndexOf("abcabc", "z"), null)
    assert(contains("abc", "bc"))
    assert(startsWith("abc", "ab"))
    assert(endsWith("abc", "bc"))

@test
an_index_counts_characters_here_as_well() =
    assertEq(indexOf("héllo", "llo"), 2)

@test
splitting_and_joining() =
    assertEq(split("a,b,c", ","), ["a", "b", "c"])
    assertEq(split("abc", ""), ["a", "b", "c"])
    assertEq(join(["a", "b"], "-"), "a-b")
    assertEq(replace("banana", "a", "o"), "bonono")
    assertEq(repeat("ab", 3), "ababab")

@test
interpolation_renders_a_value_the_way_print_does() =
    val n = 3
    val xs = [1, 2]

    assertEq(s"n is ${n} and xs is ${xs}", "n is 3 and xs is [1, 2]")

@test
a_string_prints_bare_and_shows_quoted_inside_a_container() =
    assertEq(string("a\"b"), "a\"b")
    assertEq(string(["a\"b"]), "[\"a\\\"b\"]")

@test
asking_a_string_for_something_only_an_array_can_do_is_a_fault() =
    assert((anything("abc").push(1)) catch e -> true)

// A value the checker cannot see the type of, so the refusal is the machine's rather than the
// compiler's.
anything(v) = v
