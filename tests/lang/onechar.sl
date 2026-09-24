// Strings of one character: what `string(n)`, `s[i]`, a `for` over a string, `chars` and `split`
// answer.
//
// **The interpreter hands out one shared string per ASCII character** and the JavaScript back end
// leaves it to the host. Nothing here may tell the two apart: a string compares by its text, and
// one of these appended to, kept, or read back out of something built from it is what it was.

@test
a_single_digit_is_its_own_string() =
    assertEq(string(7), "7")
    assertEq(string(0), "0")
    assertEq(string(10), "10")
    assertEq(string(-3), "-3")
    assertEq(string(7).length, 1)
    assertEq(string(7) + string(7), "77")

@test
reading_one_character_answers_a_string_of_one() =
    val s = "héllo€"
    assertEq(s[0], "h")
    assertEq(s[1], "é")
    assertEq(s[5], "€")
    assertEq(s[1..<2], "é")
    assertEq(s[2..<3], "l")
    assertEq(s.at(-1), "€")
    assertEq(s[0].length, 1)
    assertEq(s[1].length, 1)

@test
chars_and_split_give_one_string_per_character() =
    assertEq(chars("ab€"), ["a", "b", "€"])
    assertEq(split("x€y", ""), ["x", "€", "y"])
    assertEq(split("1,2,,3", ","), ["1", "2", "", "3"])

@test
a_for_over_a_string_walks_its_characters() =
    var seen = []
    for c in "a€b"
        seen.push(c)
    assertEq(seen, ["a", "€", "b"])

@test
a_character_appended_to_is_unchanged() =
    val a = "xyz"[0]
    var s = a
    for i in 0..<100
        s += string(i % 10)
    assertEq(a, "x")
    assertEq(s.length, 101)
    assertEq(s[0], "x")
    assertEq(s[100], "9")
    assertEq("x" + "yz"[0], "xy")
    assertEq("xyz"[0], a)
