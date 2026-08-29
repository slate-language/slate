// The other arrangement: a test file that imports what it tests, and can reach only its exports.

import { triple } from "./lib.sl"
import { readFile } from slate:fs

@test
it_multiplies_from_outside() =
    assertEq(triple(5), 15)

@test
async an_async_test_is_waited_for() =
    val r = await readFile("/no/such/file")

    assert(!r.ok, "a missing file answers rather than raising")
    assertEq(triple(1), 3)
