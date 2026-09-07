// What an array builtin hands the function it was given.
//
// **THE RULE IS JAVASCRIPT'S: the element, its position and the array**, and `reduce` puts the
// running answer in front of those three. A callback declares as many of them as it wants and is
// given that many, every call dropping what it cannot bind -- so `x -> x * 2` is written exactly as
// it always was and `(x, i) -> x + i` needs no `for` loop beside it.
//
// **Both back ends have to agree about every one of these**, which is what this file is for: a
// JavaScript host's own `map` already passes three, so the emitted program would have agreed here by
// accident rather than by rule, and its `groupBy` and `count` are slate's own loops that would not
// have agreed at all.

// A value whose type nobody wrote down, so a call through it reaches the machine rather than the
// checker. It is how the run-time refusal at the bottom is asked for.
anything(v) = v

@test
map_HANDS_THE_ELEMENT_THE_INDEX_AND_THE_ARRAY() =
    assertEq(map([10, 20, 30], (x, i) -> x + i), [10, 21, 32])
    assertEq(map([10, 20], (x, i, xs) -> xs.length), [2, 2])

    // The one-parameter form is untouched, which is the whole point of supplying a ceiling rather
    // than a count.
    assertEq(map([1, 2, 3], x -> x * 2), [2, 4, 6])

@test
filter_AND_flatMap_HAND_THE_SAME_THREE() =
    assertEq(filter([5, 6, 7], (x, i) -> i > 0), [6, 7])
    assertEq(filter([5, 6, 7], (x, i, xs) -> x == xs[i]), [5, 6, 7])
    assertEq(flatMap([1, 2], (x, i) -> [x, i]), [1, 0, 2, 1])
    assertEq(filter([1, 2, 3], x -> x > 1), [2, 3])

@test
forEach_HANDS_THE_SAME_THREE() =
    val seen = []

    forEach(["a", "b"], (x, i, xs) -> push(seen, [x, i, xs.length]))
    assertEq(seen, [["a", 0, 2], ["b", 1, 2]])

@test
THE_SEARCHES_HAND_THE_SAME_THREE() =
    assertEq(find([5, 6, 7], (x, i) -> i == 2), 7)
    assertEq(findIndex([5, 6, 7], (x, i) -> x == 6), 1)
    assertEq(findLast([1, 2, 3], (x, i) -> i < 2), 2)
    assertEq(findLastIndex([1, 2, 3], (x, i, xs) -> x == xs.length), 2)

    // A search that finds nothing still answers nothing, the index changing none of that.
    assertEq(find([1, 2], (x, i) -> i > 5), null)

@test
THE_QUANTIFIERS_HAND_THE_SAME_THREE() =
    assertEq(some([1, 2], (x, i) -> i == 1), true)
    assertEq(every([1, 2], (x, i, xs) -> xs.length == 2), true)
    assertEq(every([1, 2], (x, i) -> i == 0), false)

@test
reduce_PUTS_THE_RUNNING_ANSWER_IN_FRONT_OF_THE_THREE() =
    // The accumulator, then the element, then its position, then the array -- so a four-parameter
    // fold reads the way JavaScript's does.
    assertEq(reduce([1, 2, 3], (acc, x, i) -> acc + x * i, 0), 8)
    assertEq(reduce([1, 2], (acc, x, i, xs) -> acc + xs.length, 0), 4)

    // Two parameters is what nearly every fold writes, and it is unchanged.
    assertEq(reduce([1, 2, 3], (acc, x) -> acc + x, 0), 6)

@test
THE_RESHAPING_BUILTINS_HAND_THE_SAME_THREE() =
    // `count`, `groupBy`, `partition`, `minBy` and `maxBy` are slate's own and are not JavaScript
    // methods at all, so what settles their shape is that every element-wise callback in the
    // language reads alike.
    assertEq(count([1, 2, 3], (x, i) -> i > 0), 2)
    assertEq(groupBy([1, 2, 3], (x, i) -> i % 2), { "0": [1, 3], "1": [2] })
    assertEq(partition([1, 2, 3], (x, i) -> i < 1), [[1], [2, 3]])
    assertEq(minBy([3, 1, 2], (x, i) -> x + i), 1)
    assertEq(maxBy([3, 1, 2], (x, i, xs) -> xs.length - x), 1)

@test
A_COMPARATOR_IS_STILL_HANDED_TWO_ELEMENTS() =
    // `sort` and `sorted` are not element-wise: their function is asked about a PAIR, so there is no
    // position to hand it and none is.
    assertEq(sorted([2, 1], (a, b) -> a < b), [1, 2])
    assertEq(sorted([2, 1], a -> a > 0).length, 2)

@test
THE_ARRAY_A_CALLBACK_IS_HANDED_IS_THE_ONE_BEING_WALKED() =
    val xs = [1, 2, 3]
    val same = []

    forEach(xs, (x, i, given) -> push(same, given.length))
    assertEq(same, [3, 3, 3])

    // Reaching past the element the walk is on is what the third argument is for.
    assertEq(map([1, 2, 3], (x, i, ys) -> if i + 1 < ys.length then ys[i + 1] else 0), [2, 3, 0])

@test
A_CALLBACK_DECLARING_A_FOURTH_IS_REFUSED_AND_THE_SENTENCE_NAMES_THE_NATIVE() =
    // Three is what an element-wise builtin has, so a fourth parameter has nothing to fill it -- the
    // reader's function is not wrong, and the surface they attached it to is named.
    assertFaults(() -> map([1], anything((a, b, c, d) -> a)),
        "`map` calls this with 3 arguments and it takes 4 arguments")
    assertFaults(() -> reduce([1], anything((a, b, c, d, e) -> a), 0),
        "`reduce` calls this with 4 arguments and it takes 5 arguments")
