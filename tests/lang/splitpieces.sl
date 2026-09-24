// `split` gathers its pieces before it knows how many there are, and makes the array once at the
// count it found. These ask it the shapes where a gathering could go wrong: nothing between two
// separators, a separator at either end, no separator at all, a separator longer than one byte,
// pieces that are not ASCII, a piece far longer than any other, and one split after another -- the
// gathering buffer is kept from call to call, so a second split must not see what the first left.

@test
EMPTY_PIECES_ARE_KEPT_WHERE_THEY_FALL() =
    assertEq("a,,b".split(","), ["a", "", "b"])
    assertEq(",a,".split(","), ["", "a", ""])
    assertEq(",".split(","), ["", ""])
    assertEq("".split(","), [""])

@test
A_TEXT_WITH_NO_SEPARATOR_IS_ONE_PIECE() =
    val parts = "no commas here".split(",")

    assertEq([parts.length, parts[0]], [1, "no commas here"])

@test
A_SEPARATOR_OF_SEVERAL_BYTES_CUTS_WHERE_IT_STANDS() =
    assertEq("1::2::::3".split("::"), ["1", "2", "", "3"])

@test
PIECES_THAT_ARE_NOT_ASCII_KEEP_THEIR_CHARACTERS() =
    val parts = "héllo,wörld,👋,ß".split(",")

    assertEq(parts, ["héllo", "wörld", "👋", "ß"])
    assertEq(parts.map(p -> p.length), [5, 5, 1, 1])
    assertEq(parts[2][0], "👋")

@test
A_LONG_PIECE_BESIDE_SHORT_ONES_IS_WHOLE() =
    val long = "x".repeat(10000)
    val parts = ("a," + long + ",b").split(",")

    assertEq([parts.length, parts[0], parts[1].length, parts[2]], [3, "a", 10000, "b"])

@test
ONE_SPLIT_AFTER_ANOTHER_SEES_ONLY_ITS_OWN_PIECES() =
    val many = "1,2,3,4,5,6,7,8,9,10,11,12".split(",")
    val few = "x;y".split(";")

    assertEq([many.length, few], [12, ["x", "y"]])

    val lines = "1,2,a\n3,4,b\n5,6,c".split("\n")
    var total = 0

    for line in lines
        val parts = line.split(",")

        total = total + number(parts[0]) + number(parts[1]) + parts[2].length

    assertEq([lines.length, total], [3, 24])

@test
THE_ARRAY_A_SPLIT_ANSWERS_GROWS_LIKE_ANY_OTHER() =
    val parts = "a,b".split(",")

    parts.push("c")
    push(parts, "d")

    assertEq(parts, ["a", "b", "c", "d"])
