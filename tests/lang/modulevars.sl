// A module-level `var` is written where a function's local would be, and read back the same way, by
// the file's own statements, its functions, the closures they hand out, and the module that imports
// it. These are the readers, one test each.

import { settled, count, stepper, peek, shape, shadowed, ownShadowed } from "./lib/tallied.sl"
import * as tallied from "./lib/tallied.sl"

var total = 0
var i = 0

while i < 100
    total = total + i * 2 - 1
    i = i + 1

@test
A_LOOP_AT_THE_TOP_OF_A_FILE_WRITES_ITS_VARIABLES_AND_READS_THEM_BACK()
    assertEq(total, 9800)
    assertEq(i, 100)

// A function of the file reads and writes the same variable the file's own statements do.
var hits = 0

hit() =
    hits = hits + 1
    hits

@test
A_FUNCTION_WRITES_THE_FILES_VARIABLE_AND_THE_FILE_SEES_IT()
    val before = hits

    hit()
    hit()
    assertEq(hits, before + 2)

// A closure made at the top level reads the variable as it is when it is called, not as it was made.
var late = "made"

val readLate = () -> late

late = "called"

@test
A_CLOSURE_OVER_A_MODULE_VARIABLE_READS_ITS_LATEST_VALUE()
    assertEq(readLate(), "called")
    late = "again"
    assertEq(readLate(), "again")

@test
AN_IMPORTED_VARIABLE_IS_WHAT_THE_MODULE_FINISHED_WITH()
    // `settled` was declared `1` and written four times by the module's own loop.
    assertEq(settled, 24)
    assertEq(tallied.settled, 24)
    assertEq(shape, "gone")

@test
AN_IMPORTED_VARIABLE_WHOSE_SPELLING_A_FUNCTION_REBINDS_IS_WHAT_THE_MODULE_FINISHED_WITH_TOO()
    assertEq(shadowed, 5)
    assertEq(ownShadowed(), 9)

spoil() =
    total = {}.missing
    0

@test
WRITING_ABSENCE_TO_A_MODULE_VARIABLE_IS_REFUSED()
    val e = spoil() catch e -> e

    assert(contains(e.message, "undefined"))
    assertEq(total, 9800)

@test
A_CLOSURE_ANOTHER_MODULE_HANDS_OUT_READS_AND_WRITES_ITS_OWN_VARIABLE()
    val step = stepper()
    val look = peek()
    val had = look()

    assertEq(step(), had + 1)
    assertEq(step(), had + 2)
    assertEq(look(), had + 2)

    // The binding this file imported is the snapshot, and stays it.
    assertEq(count, 0)
