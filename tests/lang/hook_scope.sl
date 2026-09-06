// A `@setup`, the test it prepares and its `@teardown` share ONE event-loop scope.
//
// **Both tests here are about the scope and not about what they call.** A listener and a timer are
// the two cheapest things a hook can leave standing on the loop, and each says half of the rule: a
// handle a setup opens is still open while the body runs, and a handle the body opens is still open
// while the teardown runs. A runner that let the loop settle between the three would hang on the
// first — the listener never closes on its own — and would wait the second's three seconds out
// before the teardown could clear it.

import { listen, connect, close, localPort } from slate:net

var server = null
var armed = null

@setup
open_a_listener() =
    armed = null
    server = listen(0, conn -> close(conn))

@teardown
give_back_what_the_test_took() =
    if armed != null then clearTimeout(armed)

    close(server)

@test
async A_LISTENER_OPENED_IN_A_setup_IS_ON_THE_LOOP_THE_BODY_RUNS_ON() =
    val dialled = await connect("127.0.0.1", localPort(server))

    assert(dialled.ok, "the body reached what the setup opened")
    close(dialled.value)

// What the timer would do if the runner waited it out instead of letting the teardown clear it.
never() =
    throw "a timer the teardown was going to clear went off"

@test
A_TIMER_ARMED_IN_THE_BODY_IS_CLEARED_BY_THE_teardown() =
    armed = setTimeout(never, 3000)

    assert(armed != null, "a timer answers the id that cancels it")
