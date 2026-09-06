// A file whose test FAILS while holding what its `@setup` opened.
//
// **The teardown is what closes the listener, and it runs after a failure exactly as after a pass.**
// A runner that let the loop settle on the test's own verdict would still be holding an open
// listener at that point, so the file would never report at all — the failure this pins is a suite
// that hangs forever with nothing printed rather than one that says the wrong thing.

import { listen, close } from slate:net

var server = null

@setup
open_the_listener() =
    server = listen(0, conn -> close(conn))

@teardown
shut_the_listener() =
    close(server)

@test
one_that_fails_holding_what_its_setup_opened() =
    assert(false, "a test that fails still has its teardown run")
