// Building a string a piece at a time: every string keeps the text it had.
//
// **The interpreter appends in place where it can** -- a string made by appending shares a buffer
// with spare room after it, and the next append to the longest one writes into that room -- and the
// JavaScript back end leaves it to the host. Nothing here may tell the two apart: a string held
// under another name, a prefix kept in an array and a string appended to after something else was
// appended to it all read what they read before.

@test
a_string_held_under_another_name_is_unchanged_by_an_append() =
    var s = "a".repeat(70)
    s += "b"
    val a = s
    s += "ccc"
    assertEq(a, "a".repeat(70) + "b")
    assertEq(s, "a".repeat(70) + "bccc")
    assertEq(a.length, 71)
    assertEq(s.length, 74)

@test
appending_to_a_string_that_is_no_longer_the_longest_copies_it() =
    var s = "x".repeat(80)
    s += "1"
    val a = s
    s += "22"
    val b = a + "33"
    assertEq(s, "x".repeat(80) + "122")
    assertEq(b, "x".repeat(80) + "133")
    assertEq(a, "x".repeat(80) + "1")

@test
every_prefix_kept_along_the_way_reads_back() =
    var s = "p".repeat(64)
    val kept = []
    for i in 0..<2000
        s += string(i % 10)
        if i % 400 == 0
            kept.push(s)
    assertEq(kept.length, 5)
    for k in 0..<kept.length
        assertEq(kept[k].length, 65 + k * 400)
        assertEq(kept[k][kept[k].length - 1], "0")
    assertEq(s.length, 2064)

@test
a_string_joined_to_itself_reads_twice_over() =
    var s = "ab".repeat(40)
    s += "c"
    val t = s + s
    assertEq(t.length, 162)
    assertEq(t, "ab".repeat(40) + "c" + "ab".repeat(40) + "c")
    assertEq(s.length, 81)

@test
an_empty_append_and_a_later_one_do_not_see_each_other() =
    var s = "q".repeat(90)
    s += "."
    val same = s + ""
    val one = s + "1"
    val two = same + "2"
    assertEq(one, "q".repeat(90) + ".1")
    assertEq(two, "q".repeat(90) + ".2")
    assertEq(same, s)

@test
characters_are_counted_across_appended_pieces() =
    var s = "é".repeat(40)
    s += "日本"
    val a = s
    s += "語"
    assertEq(a.length, 42)
    assertEq(s.length, 43)
    assertEq(s[42], "語")
    assertEq(a[41], "本")

// `string` of an integer or of a string is what a loop building text hands to the append, and the
// interpreter answers both without walking a printer: the digits are counted as they are written,
// and a string is its own answer.
@test
string_of_an_integer_or_a_string_is_counted_like_any_other() =
    assertEq(string(-1234567), "-1234567")
    assertEq(string(-1234567).length, 8)
    assertEq(string(0), "0")
    assertEq(string(9223372036854775807).length, 19)
    assertEq(string("héllo"), "héllo")
    assertEq(string("héllo").length, 5)
    assertEq(string("日本")[1], "本")
    assertEq(string(9223372036854775807 * 128), "1180591620717411303296")
    var s = "n".repeat(64)
    for i in 0..<12
        s += string(i)
    assertEq(s, "n".repeat(64) + "01234567891011")
    assertEq(s.length, 78)
