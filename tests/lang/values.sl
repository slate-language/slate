// Truthiness -- what a condition, `!`, `&&`, `||` and a predicate treat as true and false.

@test
false_null_absent_zero_nan_and_empty_string_are_all_falsy() =
    assertEq(if 0 then "true" else "false", "false")
    assertEq(if -0 then "true" else "false", "false")
    assertEq(if 0.0 then "true" else "false", "false")
    assertEq(if 0.0 / 0.0 then "true" else "false", "false")
    assertEq(if "" then "true" else "false", "false")
    assertEq(if null then "true" else "false", "false")
    assertEq(if false then "true" else "false", "false")
    assertEq(if ({}.nope) then "true" else "false", "false")

@test
everything_else_is_truthy() =
    assertEq(if [] then "true" else "false", "true")
    assertEq(if {} then "true" else "false", "true")
    assertEq(if "0" then "true" else "false", "true")
    assertEq(if " " then "true" else "false", "true")
    assertEq(if 1 then "true" else "false", "true")
    assertEq(if -1 then "true" else "false", "true")
    // `bytes` is an object in JS terms -- an empty buffer is still true.
    assertEq(if bytes(0) then "true" else "false", "true")
    assertEq(if (() -> 1) then "true" else "false", "true")

@test
the_logical_operators_read_the_same_rule() =
    assertEq(!0, true)
    assertEq(0 || "x", "x")
    assertEq("" && 1, "")

@test
question_question_is_unchanged_and_still_asks_about_absence_not_truth() =
    // `??` tests whether a value is ABSENT, not whether it is truthy -- zero and the empty string
    // are values, not absences, so they are untouched by the rule above.
    assertEq(0 ?? 5, 0)
    assertEq("" ?? "d", "")

@test
a_while_loop_can_test_a_counter_directly_now_that_zero_is_false() =
    var n = 3
    val seen = []

    while n
        seen.push(n)
        n -= 1

    assertEq(seen, [3, 2, 1])

@test
filter_drops_every_falsy_element() =
    assertEq([0, 1, "", "a", null].filter(x -> x), [1, "a"])
