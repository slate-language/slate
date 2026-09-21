// Padding, and it is what makes the tests below able to fail. A span belonging to the other
// file still LOCATES in this one -- an offset is an offset -- so a report drawn against the wrong
// file quotes a line of this comment, which exists, reads plausibly, and has nothing whatever to
// do with the fault. The fixture is long enough that there is always such a line to quote.
import { fails_after_parking, fails_at_once, counts_then_fails } from "./awaited_faulty.sl"

@test
async an_await_that_fails_inside_the_module()
    await fails_after_parking(1)

@test
async a_call_that_fails_inside_the_module_after_an_await()
    await sleep(0)
    fails_at_once(1)

@test
a_generator_from_the_module_that_fails_when_it_is_stepped()
    var last = 0

    for v in counts_then_fails(0)
        last = v
