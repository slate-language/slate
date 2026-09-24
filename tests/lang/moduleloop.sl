// A counted loop at the top of a file, over the file's own variables: the head, the increment, a
// sum and a difference each written to a module-level `var` rather than a function's local. These
// are the ways such a variable is reached from somewhere else while and after the loop runs.

import { steps, drift } from "./lib/counted.sl"

var total = 0
var i = 0

while i < 1000
    total = total + i * 2 - 1
    i = i + 1

@test
A_COUNTED_LOOP_AT_THE_TOP_OF_A_FILE_ANSWERS_WHAT_THE_SAME_LOOP_IN_A_FUNCTION_DOES()
    var t = 0
    var j = 0

    while j < 1000
        t = t + j * 2 - 1
        j = j + 1

    assertEq(total, t)
    assertEq(i, j)

// A closure made before the loop reads the variable the loop wrote, and the loop writes the variable
// the closure reassigns.
var seen = 0
val look = () -> seen

bump() =
    seen = seen + 100
    seen

while seen < 10
    seen = seen + 1

@test
A_CLOSURE_OVER_A_LOOPS_VARIABLE_READS_WHAT_THE_LOOP_LEFT_AND_MAY_WRITE_IT_AGAIN()
    assertEq(look(), 10)
    bump()
    assertEq(look(), 110)
    assertEq(seen, 110)

// A function with a local of the same spelling as the loop's variable reads its own.
var n = 0

while n < 7
    n = n + 1

shadow() =
    var n = 50

    while n < 53
        n = n + 1

    n

@test
A_LOCAL_OF_THE_SAME_SPELLING_IS_ITS_OWN_VARIABLE_AND_THE_LOOPS_IS_UNTOUCHED()
    assertEq(shadow(), 53)
    assertEq(n, 7)

@test
AN_IMPORTED_VARIABLE_A_MODULES_LOOP_WROTE_IS_WHAT_THE_LOOP_FINISHED_WITH()
    assertEq(steps, 40)
    assertEq(drift, -20)

// The slow paths of the folded loop: a sum that is not whole, and a join.
var text = ""
var real = 0.5
var k = 0

while k < 3
    text = text + "ab"
    real = real + 1
    k = k + 1

@test
A_TOP_LEVEL_LOOP_OVER_A_STRING_AND_A_REAL_TAKES_THE_ORDINARY_ARITHMETIC()
    assertEq(text, "ababab")
    assertEq(real, 3.5)

@test
A_LOOP_WRITING_ABSENCE_TO_A_MODULE_VARIABLE_IS_REFUSED()
    val e = spoil() catch e -> e

    assert(contains(e.message, "cannot be written to `k`"))
    assertEq(k, 3)

spoil() =
    k = {}.missing
    0
