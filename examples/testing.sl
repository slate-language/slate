// Tests, written beside what they test.
//
//     slate test examples/testing.sl
//
// **`@test` marks a function of no arguments, and `slate test` is the only thing that calls one.**
// Running this file as an ordinary program runs what is below and none of the tests -- so a test
// costs a program that is not being tested one closure and nothing else.
//
// Tests may also live in a file of their own that imports what it tests. Which to reach for is the
// usual trade: a test beside the code can see what the file kept private, and one in its own file
// can see only what was exported, which is the same thing a reader of your module can see.

import { readFile } from slate:fs

val floor = 2

export clamp(x) = if x < floor then floor else x

export widen(xs) =
    var out = []

    for x in xs
        push(out, clamp(x))

    out

@test
clamp_leaves_a_big_enough_number_alone() =
    assertEq(clamp(7), 7)

@test
clamp_lifts_a_small_one_to_the_floor() =
    assertEq(clamp(-3), floor)

@test
the_floor_is_private_and_a_test_beside_the_code_still_sees_it() =
    // A test in a separate file could not reach this, `floor` never having been exported.
    assertEq(floor, 2)

@test
widen_clamps_every_element() =
    assertEq(widen([1, 5, -2]), [2, 5, 2])

@test
an_assertion_may_say_what_it_was_checking() =
    assert(len(widen([])) == 0, "widening nothing gives nothing")

// A test may be `async`, and the runner waits for it rather than calling it a pass.
@test
async a_missing_file_answers_rather_than_raising() =
    val r = await readFile("no-such-file-here.txt")

    assert(!r.ok, "a file that is not there answers a result")
    assert(len(r.error) > 0, "and the result carries a sentence saying why")

print("run me with `slate test` to see the tests; running me plainly does this instead")
print(widen([1, 5, -2]))
