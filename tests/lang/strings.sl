// Strings: counted in characters, and Unicode wherever a case or a space rule has to decide.

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
case_is_the_whole_database_and_not_the_ascii_range() =
    assertEq(upper("héllo"), "HÉLLO")
    assertEq(lower("HÉLLO"), "héllo")
    assertEq(upper("abc123"), "ABC123")

@test
a_case_mapping_may_change_a_strings_length() =
    // A hundred and two characters uppercase to more than one, and one lowercases to more than one.
    // A per-character walk would answer a single letter for each and disagree with every other
    // language that has a case table.
    assertEq(upper("ß"), "SS")
    assertEq(upper("ﬁ"), "FI")
    assertEq(len(lower("İ")), 2)

@test
a_sigma_at_the_end_of_a_word_is_written_differently() =
    // Which is context rather than a table: the letter is the same one and the shape it takes
    // depends on what stands either side of it.
    assertEq(lower("ΟΔΟΣ"), "οδος")
    assertEq(lower("ΟΔΟΣΑ"), "οδοσα")

@test
trimming_is_unicode_whitespace() =
    assertEq(trim("  x\t\n"), "x")
    assertEq(trimStart("  x  "), "x  ")
    assertEq(trimEnd("  x  "), "  x")

    // A non-breaking space is whitespace and comes off; a zero-width no-break space is not one
    // and stays, which is the pair every host's own `trim` gets the other way round.
    assertEq(trim(" \u{a0}x\u{a0} "), "x")
    assertEq(trim("\u{feff}x\u{feff}"), "\u{feff}x\u{feff}")

@test
normalizing_is_what_makes_two_spellings_of_one_word_equal() =
    // The same text typed on two machines is routinely two different sequences of characters, and
    // nothing about comparing them says so.
    assert("é" != "e\u{301}")
    assertEq(normalize("e\u{301}", "NFC"), "é")
    assertEq(normalize("é", "NFD"), "e\u{301}")

    // The compatibility forms throw information away, which is what makes them for matching.
    assertEq(normalize("ﬁ", "NFKC"), "fi")

@test
a_form_nobody_knows_is_refused_naming_all_four() =
    val said = (normalize("x", "nfc") catch e -> e.message)

    assert(contains(said, "NFC"))
    assert(contains(said, "NFKD"))

@test
folding_is_for_comparing_and_lowering_is_for_showing() =
    // `ß` folds to `ss` where it lowercases to itself, so folding is what answers *is this the same
    // word* and lowering is not.
    assert(casefold("STRASSE") == casefold("Straße"))
    assert(lower("STRASSE") != lower("Straße"))

    // And folding is idempotent, which is what makes it the thing to store.
    assertEq(casefold(casefold("Straße")), casefold("Straße"))

    // It composes what it answers, so a decomposed spelling folds to the composed one.
    assert(casefold("ÉCOLE") == casefold("e\u{301}cole"))

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
a_search_may_be_told_where_to_start() =
    // A negative counts back from the end, and past the end there is nothing at or after it. That
    // is one rule for a string and for an array, where JavaScript reads the same argument two ways.
    assertEq(indexOf("abcabc", "b", 2), 4)
    assertEq(indexOf("abcabc", "b", 5), null)
    assertEq(lastIndexOf("abcabc", "b", 3), 1)
    assertEq(lastIndexOf("abcabc", "b", 0), null)
    assertEq(indexOf("abcabc", "b", -3), 4)
    assertEq(lastIndexOf("abcabc", "b", -3), 1)
    assertEq(indexOf("abc", "a", 99), null)
    assertEq(lastIndexOf("abc", "a", 99), 0)

    // In characters, exactly as the answer is.
    assertEq("héllé".indexOf("l", 3), 3)
    assertEq("héllé".lastIndexOf("l", 2), 2)

@test
a_subsequence_is_found_where_the_haystack_keeps_almost_matching() =
    val h = repeat("aaab", 400) + "aaac"

    assertEq(indexOf(h, "aaac"), 1600)
    assertEq(lastIndexOf(h, "aaab"), 1596)
    assertEq(indexOf(h, "aaad"), null)
    assert(contains(h, "aaac"))
    assert(!contains(h, "aaad"))

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
bytes_go_out_and_come_back_as_a_result() =
    // **A result, because arbitrary bytes are not text.** Answering the string itself would hide the
    // difference between a file that is not text and one that is empty — and it is what the
    // JavaScript back end did, so every `fromBytes(bs).value` in every program was `undefined` there.
    val r = fromBytes(toBytes("日本語"))

    assert(r.ok)
    assertEq(r.value, "日本語")

    // The decoder is strict where JavaScript's own replaces what it cannot read with U+FFFD: a
    // continuation byte standing alone spells nothing.
    val bad = fromBytes([0x80])

    assert(!bad.ok)
    assert(len(bad.error) > 0)

    // An overlong form, a surrogate and a sequence that stops early are each refused.
    assert(!fromBytes([0xc0, 0xaf]).ok)
    assert(!fromBytes([0xed, 0xa0, 0x80]).ok)
    assert(!fromBytes([0xe6, 0x97]).ok)

    // A byte outside the range is the program's own mistake, so it FAULTS rather than answering.
    assert(fromBytes([256]) catch e -> true)
    assert(fromBytes(["a"]) catch e -> true)

@test
asking_a_string_for_something_only_an_array_can_do_is_a_fault() =
    assert((anything("abc").push(1)) catch e -> true)

// A value the checker cannot see the type of, so the refusal is the machine's rather than the
// compiler's.
anything(v) = v
