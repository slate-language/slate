// A server opened once for the whole file, and a client that never says anything to it before the
// first test runs.
//
// **A listener is asked for connections once and answers for as long as it is open**, so the slot for
// a connection is claimed whenever a client happens to dial -- which here is inside the first test,
// the loop not having turned since. The connection is the file's all the same: a runner that counted
// it as that test's made the test wait five seconds for a handle it never opened, reported it as the
// test's leak, and closed it under the two tests that come after.
//
// The round trips are what say the connection is still live by then, and they are deliberately not
// done in the `@setupAll` -- one there would force the accept while the file's own scope was current
// and hide the whole thing.

import { listen, connect, close, localPort, onData, send } from slate:net

var server = null
var client = null
var taken = null
var dialling = null
var heard = null

echoed(chunk) =
    if chunk != null && heard != null
        val waiting = heard

        heard = null
        settle(waiting, chunk)

serving(conn) =
    taken = conn

    onData(conn, chunk -> if chunk != null then send(conn, chunk))

// One round trip, answering `<silence>` rather than waiting for ever: a connection closed under this
// file fails a test in a second instead of hanging the run.
async said(what) =
    var timer = null

    heard = pending()

    val reply = heard

    quiet() =
        timer = null
        heard = null
        settle(reply, "<silence>")

    timer = setTimeout(quiet, 1000)

    send(client, what)

    val got = await reply

    if timer != null then clearTimeout(timer)

    got

@setupAll
open_the_server() =
    server = listen(0, serving)
    dialling = connect("127.0.0.1", localPort(server))

// **The file gives back what the file took**, the accepted connection included: it is the file's, so
// nothing before this point closes it and the drain after this would otherwise wait for it.
@teardownAll
shut_it_down() =
    if taken != null then close(taken)

    if client != null then close(client)

    close(server)

@test
async a_connection_the_file_dialled_arrives_in_the_first_test() =
    val r = await dialling

    assert(r.ok, "the client reached what the `@setupAll` opened")
    client = r.value
    onData(client, echoed)

@test
async the_next_test_still_has_it() =
    assert(await said("one") == "one", "the connection the file opened was closed under this test")

@test
async and_so_does_the_one_after_that() =
    assert(await said("two") == "two", "and it is still open for the last of them")
