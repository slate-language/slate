// What a string knows about its own length, and what a position into one means.
//
// **A slate string is counted in CHARACTERS and the bytes under it are UTF-8**, so every one of
// these is a question about the two disagreeing. They are ordinary questions about the language and
// every one of them was true before the count was kept on the string itself; they are written down
// because the count is now carried and derived rather than worked out at each question, and each of
// these is a way that could be wrong while an ordinary ASCII program still looked right.
//
// **A CHARACTER IS A CODE POINT.** An emoji outside the basic plane is one character here and two
// units in JavaScript, and a letter written with a combining mark is two characters in both.

val ascii = "abcdefghij"
val mixed = "héllo, 日本語"
val astral = "a👋b"
val combining = "e\u{301}x"

@test
a_length_is_the_number_of_characters() =
    assertEq("".length, 0)
    assertEq(ascii.length, 10)
    assertEq(mixed.length, 10)
    assertEq(astral.length, 3)
    assertEq(combining.length, 3)
    assertEq(len(mixed), 10)

@test
a_byte_length_is_a_different_number_and_both_are_available() =
    assertEq(toBytes(mixed).length, 18)
    assertEq(toBytes(astral).length, 6)
    assertEq(toBytes("").length, 0)

@test
a_joined_string_knows_its_own_length() =
    assertEq((ascii + mixed).length, 20)
    assertEq((mixed + astral).length, 13)
    assertEq(("" + "").length, 0)
    assertEq((astral + "").length, 3)

@test
a_string_built_a_piece_at_a_time_reports_the_whole_length() =
    // The shape every program that assembles text has, and the one where a count carried from piece
    // to piece could drift a character at a time without any single step looking wrong.
    var text = ""
    var i = 0

    while i < 200
        text = text + "日本" + "ab"
        i = i + 1

    assertEq(text.length, 800)
    assertEq(text[798], "a")
    assertEq(text[0..<4], "日本ab")

@test
an_interpolated_string_knows_its_own_length() =
    val who = "日本語"
    val n = 42

    assertEq(s"hi ${who}".length, 6)
    assertEq(s"${n} of ${who}".length, 9)
    assertEq(s"${astral}${combining}".length, 6)

@test
a_repeated_string_knows_its_own_length() =
    assertEq(repeat("日", 4).length, 4)
    assertEq(repeat("ab", 3).length, 6)
    assertEq(repeat("👋", 5).length, 5)
    assertEq(repeat("x", 0).length, 0)

@test
a_padded_string_is_exactly_the_width_asked_for() =
    assertEq(padStart("7", 5).length, 5)
    assertEq(padStart("7", 5, "ab"), "abab7")
    assertEq(padEnd("日", 4, "語").length, 4)
    assertEq(padEnd("日", 4, "語"), "日語語語")

    // Already that wide is answered unchanged, and still says how long it is.
    assertEq(padStart(mixed, 3).length, 10)

@test
a_sliced_string_knows_its_own_length() =
    assertEq(mixed[0..<5].length, 5)
    assertEq(mixed[7..<10], "日本語")
    assertEq(mixed[7..<10].length, 3)
    assertEq(astral[1..<2], "👋")
    assertEq(astral[1..<2].length, 1)
    assertEq(mixed[0..<0].length, 0)

@test
a_character_read_by_index_is_one_character_long() =
    assertEq(mixed[8], "本")
    assertEq(mixed[8].length, 1)
    assertEq(astral[1].length, 1)
    assertEq(combining[1], "\u{301}")
    assertEq(combining[1].length, 1)

@test
a_string_walked_by_index_reads_the_same_forwards_and_backwards() =
    // The interpreter remembers where it last was in a string that is not all one-byte, so this is
    // the pair of walks that says the memory is an optimisation and not an answer.
    var forwards = ""
    var i = 0

    while i < mixed.length
        forwards = forwards + mixed[i]
        i = i + 1

    var backwards = ""
    var j = mixed.length - 1

    while j >= 0
        backwards = mixed[j] + backwards
        j = j - 1

    assertEq(forwards, mixed)
    assertEq(backwards, mixed)
    assertEq(forwards.length, 10)

@test
reading_the_same_position_twice_answers_the_same_thing() =
    assertEq(mixed[8], mixed[8])
    assertEq(mixed[0], "h")
    assertEq(mixed[9], "語")
    assertEq(mixed[0], "h")
    assertEq(mixed[9], "語")

@test
an_index_outside_the_string_is_refused_in_characters() =
    val past = (mixed[10] catch e -> e.message)
    val below = (mixed[-1] catch e -> e.message)

    assert(contains(past, "10"))
    assert(contains(past, "10 characters"))
    assert(contains(below, "-1"))
    assert(contains(below, "10 characters"))

    // The byte length is 18 and it is not the number a reader is told about.
    assert(!contains(past, "18"))

@test
an_index_into_the_empty_string_is_refused() =
    val nothing = ""
    val said = (nothing[0] catch e -> e.message)

    assert(contains(said, "0 characters"))

@test
the_characters_of_a_string_are_its_length_many() =
    assertEq(chars(mixed).length, 10)
    assertEq(chars(astral), ["a", "👋", "b"])
    assertEq(chars(combining).length, 3)
    assertEq(chars(""), [])
    assertEq(join(chars(mixed), ""), mixed)
    assertEq(join(chars(mixed), "").length, 10)

@test
splitting_on_nothing_is_the_characters() =
    assertEq(split(astral, ""), ["a", "👋", "b"])
    assertEq(split("a,日,b", ","), ["a", "日", "b"])
    assertEq(split("a,日,b", ",")[1].length, 1)

@test
a_joined_array_knows_its_own_length() =
    assertEq(join(["日", "本", "語"], "-").length, 5)
    assertEq(join([1, 2, 3], "日").length, 5)
    assertEq(join([], "-").length, 0)
    assertEq(join(["x"], "-").length, 1)

@test
a_replaced_string_knows_its_own_length() =
    // The width of what went in and what came out differ four ways, and the count has to be right
    // for all of them: same size, wider, narrower, and the same bytes meaning fewer characters.
    assertEq(replace("aXbXc", "X", "日").length, 5)
    assertEq(replace("aXbXc", "X", "").length, 3)
    assertEq(replace("aXbXc", "X", "yy").length, 7)
    assertEq(replace("日日", "日", "ab").length, 4)
    assertEq(replace("日日", "日", "ab"), "abab")
    assertEq(replace("abc", "z", "q").length, 3)

@test
a_trimmed_string_knows_its_own_length() =
    assertEq(trim("  日本語  ").length, 3)
    assertEq(trimStart("  ab").length, 2)
    assertEq(trimEnd("ab  ").length, 2)
    assertEq(trim("   ").length, 0)

@test
a_case_mapping_that_changes_the_count_still_reports_it() =
    assertEq(upper("ß").length, 2)
    assertEq(upper("straße").length, 7)
    assertEq(lower("HÉLLO").length, 5)
    assertEq(upper("日本語").length, 3)

@test
a_position_a_search_answers_is_a_character_position() =
    assertEq(indexOf(mixed, "日"), 7)
    assertEq(indexOf(mixed, "語"), 9)
    assertEq(lastIndexOf(mixed, "l"), 3)
    assertEq(indexOf(mixed, "z"), null)
    assertEq(indexOf(astral, "b"), 2)
    assertEq(indexOf("日日日", "日", 1), 1)
    assertEq(lastIndexOf("日日日", "日"), 2)
    assertEq(indexOf(mixed, ""), 0)

@test
a_string_a_search_cut_from_a_position_reads_the_same() =
    // Finding the second occurrence: what a position is for, and what it is worth only if the slice
    // taken from it lands on a character.
    val at = indexOf(mixed, "日") ?? 0

    assertEq(mixed[at..<mixed.length], "日本語")
    assertEq(mixed[at..<mixed.length].length, 3)

@test
a_stepped_slice_of_a_string_knows_its_own_length() =
    assertEq("日a本b語"[0..<5 by 2], "日本語")
    assertEq("日a本b語"[0..<5 by 2].length, 3)
    assertEq(ascii[0..<10 by 3].length, 4)
