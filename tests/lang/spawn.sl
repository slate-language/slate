// A child that outlives the call that started it, and the channel it is talked to over.
//
// **Every one of these is about two processes, so nothing here can be stood in for.** What is being
// tested is that a program starts another program, exchanges messages with it over a descriptor,
// learns when it dies and can signal it — and the child is `/bin/sh` throughout, which both back
// ends have and neither has anything to do with. A child written in slate would be testing which
// interpreter was installed.
//
// **The echo child counts its lines and ends**, rather than reading until the channel closes. A
// worker that waits forever is the ordinary shape of one, and it is the wrong shape for a test: the
// supervisor waits for the child and the child waits for the supervisor, which is a suite that hangs
// with nothing printed rather than a test that fails.

import { spawn, channel, run } from slate:process
import { listen, close } from slate:net

// A value whose type the checker cannot see, so that a refusal is the MACHINE's rather than the
// pass's. `tests/lang/callbacks.sl` has the same helper for the same reason.
anything(v) = v

// A child that reads `n` messages off the channel, writes each one straight back, and exits.
echoing(n) = ("i=0; while [ $i -lt " + string(n) + " ] && IFS= read -r line <&3; do " +
    "printf '%s\\n' \"$line\" >&3; i=$((i+1)); done")

@test
async A_CHILD_IS_ANSWERED_AT_ONCE_AND_ITS_EXIT_IS_A_PROMISE()
    val started = spawn("/bin/sh", ["-c", "exit 7"])

    // **The answer is a result and not a promise**, which is the whole difference from `run`: the
    // exec has been tried by the time `spawn` comes back, so there is nothing left to wait for.
    assert(started.ok)
    assert(started.value.pid > 0)

    val gone = await started.value.exited

    assertEq(gone.value.status, 7)
    assertEq(gone.value.signal, null)

    // And the child answers for itself afterwards, which is what a supervisor logging a worker's
    // death needs.
    assert(started.value.pid > 0)

@test
A_PROGRAM_THAT_IS_NOT_THERE_IS_A_RESULT_AND_NOT_A_FAULT()
    val missing = spawn("no-such-program-anywhere", [])

    assert(!missing.ok)
    assert(missing.error.contains("no-such-program-anywhere"))

@test
async kill_SETTLES_THE_EXIT_WITH_THE_SIGNAL()
    val started = spawn("/bin/sh", ["-c", "sleep 30"])

    assertEq(started.value.kill().ok, true)

    val gone = await started.value.exited

    // **A signal is a number and `SIGTERM` is 15**, which is the same answer `run` gives for a child
    // its timeout killed — one vocabulary for how a child ended, however it was started.
    assertEq(gone.value.signal, 15)

@test
async onExit_IS_THE_CALLBACK_FORM_OF_THE_SAME_ANSWER()
    var told = null
    val started = spawn("/bin/sh", ["-c", "exit 4"])

    started.value.onExit(e ->
        told = e.status)

    await started.value.exited
    assertEq(told, 4)

@test
async THREE_MESSAGES_ROUND_TRIP_OVER_THE_CHANNEL()
    val started = spawn("/bin/sh", ["-c", echoing(3)], { ipc: true })
    val worker = started.value
    val back = []

    worker.onMessage(m ->
        back.push(m))

    assertEq(worker.send({ a: 1 }).ok, true)
    assertEq(worker.send([1, "two"]).ok, true)
    assertEq(worker.send("three").ok, true)

    await worker.exited

    // Every message comes back as the value it was sent as, and in the order it was sent in.
    assertEq(back.length, 3)
    assertEq(back[0].a, 1)
    assertEq(back[1], [1, "two"])
    assertEq(back[2], "three")

@test
async A_MESSAGE_IS_WHOLE_OR_IT_HAS_NOT_ARRIVED()
    // Three messages written before the child has read any of them arrive in one read, which is
    // what the newline is for: a read is a run of bytes and a message is a line.
    val started = spawn("/bin/sh", ["-c", echoing(3)], { ipc: true })
    val worker = started.value
    var count = 0

    worker.onMessage(m ->
        count = count + m.n)

    worker.send({ n: 1 })
    worker.send({ n: 2 })
    worker.send({ n: 4 })

    await worker.exited
    assertEq(count, 7)

@test
async A_CHILD_STARTED_WITHOUT_A_CHANNEL_IS_REFUSED_A_MESSAGE()
    val started = spawn("/bin/sh", ["-c", "exit 0"])

    assertFaults(() -> started.value.send("hello"), "started without a channel")
    await started.value.exited

@test
A_PROGRAM_NOBODY_STARTED_HAS_NO_CHANNEL()
    // **`null` rather than a fault, because a program may be run both ways**: the same file is a
    // worker under a supervisor and a script somebody typed the name of, and this is how it asks.
    assertEq(channel(), null)

@test
async A_MESSAGE_THAT_IS_NOT_JSON_IS_REFUSED_IN_toJSON_s_WORDS()
    val started = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true })

    // A value the program built itself is a fault where the world's news is a result, which is
    // slate's two-channel rule: this is the same refusal `toJSON` makes of the same value.
    assertFaults(() -> started.value.send(x -> x), "function")

    started.value.send("done")
    await started.value.exited

@test
async SENDING_TO_A_CHILD_THAT_HAS_GONE_IS_AN_ERROR_AND_NOT_A_CRASH()
    val started = spawn("/bin/sh", ["-c", "exit 0"], { ipc: true })
    val worker = started.value

    await worker.exited

    val said = worker.send({ late: true })

    assert(!said.ok)
    assert(said.error.length > 0)

@test
async WRITING_TO_A_CHILD_AS_IT_EXITS_STILL_TELLS_onExit()
    // **A supervisor answering a worker's first word is writing to a process that may already be
    // ending**, and the write failing must not cost it the exit: the answer is a result, and the
    // child's exit is still delivered exactly once. node reports that failed write as an `error`
    // event on the child, which arrives before the exit does, and treating it as the child not having
    // run left `onExit` silent for ever.
    var told = 0
    val started = spawn("/bin/sh", ["-c", "printf '{\"hello\":1}\\n' >&3"], { ipc: true })
    val worker = started.value

    worker.onExit(e ->
        told = told + 1)

    worker.onMessage((m, s) ->
        worker.send({ id: 1 }))

    val gone = await worker.exited

    assert(gone.ok)
    assertEq(told, 1)

@test
async A_SUPERVISOR_SEES_TWO_WORKERS_BY_THEIR_OWN_PIDS()
    // The shape a cluster is: several children of one program, each talked to over its own channel
    // and each watched for its own exit.
    val one = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true }).value
    val two = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true }).value

    val heard = []

    one.onMessage(m ->
        heard.push(m))

    two.onMessage(m ->
        heard.push(m))

    one.send("one")
    two.send("two")

    val first = await one.exited
    val second = await two.exited

    assert(one.pid != two.pid)
    assertEq(first.value.status, 0)
    assertEq(second.value.status, 0)
    assertEq(heard.length, 2)

@test
WHAT_spawn_SAYS_ABOUT_WHAT_IT_WAS_GIVEN_INSTEAD()
    assertFaults(() -> spawn(), "takes a command")
    assertFaults(() -> spawn(3, []), "and this is an integer")
    assertFaults(() -> spawn("/bin/sh", "-c"), "as an array")
    assertFaults(() -> spawn("/bin/sh", [3]), "as strings")
    assertFaults(() -> spawn("/bin/sh", [], 3), "options as an object")
    assertFaults(() -> spawn("/bin/sh", [], { ipc: 1 }), "`ipc` is true or false")
    assertFaults(() -> spawn("/bin/sh", [], { cwd: 1 }), "`cwd` is a string")
    assertFaults(() -> spawn("/bin/sh", [], { env: { A: 1 } }), "environment variable is a string")

@test
async WHAT_A_CHILD_SAYS_ABOUT_WHAT_ITS_METHODS_WERE_GIVEN()
    val worker = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true }).value

    assertFaults(() -> worker.kill("SIGNOPE"), "is not a signal")
    assertFaults(() -> worker.onMessage(3), "needs a function to call")
    assertFaults(() -> worker.onExit("no"), "needs a function to call")
    // **Through `anything` so that the CHECKER does not answer first.** A string's methods are
    // known before the program runs, so the interesting refusal — the one the machine makes of a
    // value whose type nobody wrote down — is reached only by a value the pass cannot see into.
    assertFaults(() -> anything("not a child").kill(), "not something a string can do")

    worker.send("done")
    await worker.exited

@test
async A_CHILD_STARTS_WHERE_IT_IS_TOLD_AND_WITH_THE_ENVIRONMENT_IT_IS_GIVEN()
    val told = "printf '\"%s\"\\n' \"$GREETING\" >&3; read line <&3"
    val worker = spawn("/bin/sh", ["-c", told], { ipc: true, cwd: "/tmp",
        env: { GREETING: "hi", PATH: "/bin:/usr/bin" } }).value

    var said = null

    worker.onMessage(m ->
        said = m
        worker.send("go on"))

    // The environment REPLACES the child's rather than adding to it, so a program that wants a
    // variable kept passes it through — which is what `PATH` is doing here.
    await worker.exited
    assertEq(said, "hi")

// -- passing a socket ------------------------------------------------------------------------------
//
// **What a supervisor is REFUSED is what can be driven from here**, `/bin/sh` being the one child both
// hosts have. A socket that actually crosses needs a slate program at the other end and a host that
// can pass a handle at all, which is `tests_process.sysl`'s arrangement on the interpreter and a pair
// of compiled programs under node.

@test
async A_MESSAGE_THAT_CARRIES_NO_SOCKET_HANDS_ITS_HANDLER_null()
    // **`null` and not a missing argument**, so a handler may read the second parameter without
    // asking whether there was one -- and a handler that declares only the first is unchanged, a call
    // dropping the arguments a function did not ask for.
    val worker = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true }).value
    var carried = "not called"

    worker.onMessage((m, sock) ->
        carried = string(sock))

    worker.send({ a: 1 })
    await worker.exited
    assertEq(carried, "null")

@test
async A_SOCKET_MAY_NOT_BE_PASSED_TO_A_CHILD_THAT_HAS_NOT_SAID_WHAT_IT_IS()
    // A descriptor may only cross between two programs on the same host, and a supervisor cannot know
    // what it started until that child has spoken. A worker signalling that it is ready is what says
    // so, which is what a cluster already does.
    val worker = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true }).value
    val server = listen(0, (conn) -> null)

    assertFaults(() -> worker.send({ job: 1 }, server), "has not said what it is yet")

    close(server)
    worker.send("done")
    await worker.exited

@test
async A_CHILD_THAT_IS_NOT_A_SLATE_PROGRAM_IS_REFUSED_A_SOCKET()
    // The shell says something and what it says is not the line a slate channel opens with, so the
    // question is settled and the refusal names it.
    val worker = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true }).value
    val server = listen(0, (conn) -> null)

    worker.onMessage((m) -> null)
    worker.send({ a: 1 })
    await worker.exited

    assertFaults(() -> worker.send({ job: 1 }, server), "is not a slate program")
    close(server)

@test
async WHAT_send_SAYS_ABOUT_A_SECOND_ARGUMENT_THAT_IS_NOT_A_SOCKET()
    val worker = spawn("/bin/sh", ["-c", echoing(1)], { ipc: true }).value

    assertFaults(() -> worker.send({ a: 1 }, 3), "passes on a socket")
    assertFaults(() -> worker.send({ a: 1 }, 3, 4), "optionally a socket")

    worker.send("done")
    await worker.exited

@test
async A_CHILD_STARTED_WITHOUT_A_CHANNEL_IS_REFUSED_A_SOCKET_BEFORE_ANYTHING_ELSE()
    // The `ipc` question is about the `spawn` and is asked first, so a supervisor that forgot the
    // option hears about that rather than about the socket it was holding.
    val started = spawn("/bin/sh", ["-c", "exit 0"])
    val server = listen(0, (conn) -> null)

    assertFaults(() -> started.value.send("hello", server), "started without a channel")

    close(server)
    await started.value.exited

@test
async A_MESSAGE_SENT_JUST_BEFORE_EXIT_IS_DELIVERED_BEFORE_exited_SETTLES()
    // node's `exit` fires the moment the process has terminated, which can land before the last
    // read of the IPC channel -- so a worker that writes a message and stops in the same breath
    // could once have had `exited` settle before the parent had seen what it said. `exited` now
    // resolves on `close`, which waits for the channel to drain first. Racing this twenty times
    // is what makes a windowed failure show up.
    for i in 0..<20
        val worker = spawn("/bin/sh", ["-c", "printf '\"ping\"\\n' >&3"], { ipc: true }).value
        var got = null

        worker.onMessage(m ->
            got = m)

        await worker.exited

        assertEq(got, "ping")

@test
async onExit_IS_CALLED_AFTER_THE_LAST_MESSAGE_TOO()
    // The callback form of the rule above: the exit and the channel's end are two events, and the
    // exit is told only once both have happened, whichever came first.
    for i in 0..<20
        val worker = spawn("/bin/sh", ["-c", "printf '\"ping\"\\n' >&3; exit 5"], { ipc: true }).value
        var seen = []

        worker.onMessage(m ->
            seen.push(m))
        worker.onExit(e ->
            seen.push(e.status))

        await worker.exited

        assertEq(seen, ["ping", 5])

@test
async A_CHILD_THAT_CLOSES_ITS_CHANNEL_BEFORE_IT_EXITS_STILL_SETTLES_exited()
    // The other order: the channel ends first, and the exit that comes after it is what settles the
    // promise. A child that never says anything on its channel is the same case.
    val early = spawn("/bin/sh", ["-c", "exec 3>&-; sleep 0.1; exit 2"], { ipc: true }).value
    val quiet = spawn("/bin/sh", ["-c", "exit 3"], { ipc: true }).value

    assertEq((await early.exited).value.status, 2)
    assertEq((await quiet.exited).value.status, 3)

@test
async A_SIGPIPE_DOES_NOT_END_THE_PROGRAM()
    // **A write to a peer that has gone is an error the write answers**, which is node's rule and
    // slate's on both hosts. What finds it in the wild is a race -- a supervisor writing to a worker
    // in the instant after the worker exits -- so the signal is sent here on purpose instead, and a
    // host that left its default in place dies on this line every time rather than once in sixty.
    await spawn("/bin/sh", ["-c", "kill -PIPE $PPID"]).value.exited

    assert(true)

// -- a child's output, piped to the program ---------------------------------------------------------

@test
async A_PIPED_STDOUT_IS_READ_WHOLE_BY_text()
    val child = spawn("/bin/sh", ["-c", "printf 'hello\\nworld\\n'"], { stdout: "pipe" }).value
    val said = await child.stdout.text()

    assert(said.ok)
    assertEq(said.value, "hello\nworld\n")
    assertEq((await child.exited).value.status, 0)

@test
async A_PIPED_STREAM_HANDS_OVER_EACH_CHUNK_AS_IT_ARRIVES()
    // **The first line is handed over while the child is still running**, which `onExit` not having
    // been called yet says -- a stream that handed nothing over until the child ended would see it
    // called by then.
    val child = spawn("/bin/sh", ["-c", "echo first; sleep 0.2; echo second"], { stdout: "pipe" }).value
    var gone = false

    child.onExit(_ ->
        gone = true)

    val first = await child.stdout.next()

    assert(!first.done)
    assertEq(fromBytes(first.value).value, "first\n")

    // The exit waits for the stream, so a child still writing has not been reported gone.
    assert(!gone)

    var rest = ""

    for await chunk in child.stdout
        rest = rest + fromBytes(chunk).value

    assertEq(rest, "second\n")
    assertEq((await child.exited).value.status, 0)
    assert(gone)

@test
async A_CHILD_WRITING_A_MEGABYTE_IS_NOT_BLOCKED_BY_A_PROGRAM_THAT_WAITS_FOR_ITS_EXIT_FIRST()
    // **More than any pipe buffer holds, and the exit awaited before a byte is read.** A stream that
    // only read when asked would leave the child blocked on a full pipe and the program waiting on
    // an exit that never comes.
    val child = spawn("/bin/sh", ["-c", "head -c 1048576 /dev/zero | tr '\\0' x"], { stdout: "pipe" }).value

    assertEq((await child.exited).value.status, 0)

    val said = await child.stdout.text()

    assertEq(said.value.length, 1048576)
    assert(said.value.startsWith("xxxx"))

@test
async A_MEGABYTE_READ_CHUNK_BY_CHUNK_ARRIVES_WHOLE()
    val child = spawn("/bin/sh", ["-c", "head -c 1048576 /dev/zero"], { stdout: "pipe" }).value
    var total = 0

    for await chunk in child.stdout
        total = total + chunk.length

    assertEq(total, 1048576)
    assertEq((await child.exited).value.status, 0)

@test
async STDOUT_AND_STDERR_ARE_PIPED_APART()
    val child = spawn("/bin/sh", ["-c", "printf out; printf err >&2; printf more; exit 4"],
        { stdout: "pipe", stderr: "pipe" }).value

    val out = await child.stdout.text()
    val err = await child.stderr.text()
    val gone = await child.exited

    assertEq(out.value, "outmore")
    assertEq(err.value, "err")
    assertEq(gone.value.status, 4)

@test
async EVERYTHING_A_CHILD_WROTE_BEFORE_IT_EXITED_IS_THERE_AFTER_exited_SETTLES()
    // **`exited` waits for the piped streams to end**, as it waits for the channel, so a program that
    // learns of the exit first reads everything afterwards -- stderr written as the last act included.
    val child = spawn("/bin/sh", ["-c", "echo one; echo two >&2; echo three; exit 1"],
        { stdout: "pipe", stderr: "pipe" }).value
    val gone = await child.exited

    assertEq(gone.value.status, 1)
    assertEq((await child.stdout.text()).value, "one\nthree\n")
    assertEq((await child.stderr.text()).value, "two\n")

@test
async A_CHILD_THAT_EXITS_AT_ONCE_HAS_AN_EMPTY_STREAM()
    val quiet = spawn("/bin/sh", ["-c", "exit 0"], { stdout: "pipe" }).value
    val step = await quiet.stdout.next()

    assert(step.done)
    assertEq((await quiet.stdout.next()).done, true)

    val also = spawn("/bin/sh", ["-c", "exit 0"], { stderr: "pipe" }).value

    assertEq((await also.stderr.text()).value, "")
    assertEq((await quiet.exited).value.status, 0)
    assertEq((await also.exited).value.status, 0)

@test
async OUTPUT_THAT_IS_NOT_TEXT_IS_AN_ANSWER_FROM_text()
    val child = spawn("/bin/sh", ["-c", "printf '\\377'"], { stdout: "pipe" }).value
    val said = await child.stdout.text()

    assert(!said.ok)
    assert(said.error.contains("not text"))
    await child.exited

@test
async A_STREAM_LEFT_EARLY_IS_STILL_DRAINED_SO_THE_CHILD_ENDS()
    // **Leaving the loop lets go of the stream and does not close the pipe under the child**, which
    // goes on writing a megabyte nobody reads -- and still exits, because the rest is thrown away.
    val child = spawn("/bin/sh", ["-c", "head -c 1048576 /dev/zero"], { stdout: "pipe" }).value

    for await chunk in child.stdout
        assert(chunk.length > 0)
        break

    assertEq((await child.exited).value.status, 0)
    assertEq((await child.stdout.next()).done, true)
    assert(!(await child.stdout.text()).ok)

@test
async A_STREAM_IS_ONE_VALUE_AND_HAS_ONE_READER_AT_A_TIME()
    val child = spawn("/bin/sh", ["-c", "sleep 0.1; echo late"], { stdout: "pipe" }).value

    assert(child.stdout == child.stdout)

    val pending = child.stdout.next()

    assertFaults(() -> child.stdout.next(), "already working on a `next`")
    assertFaults(() -> child.stdout.text(), "already being read")

    assertEq(fromBytes((await pending).value).value, "late\n")
    await child.exited

@test
async AN_OUTPUT_THAT_IS_NOT_PIPED_IS_null()
    // **Inherited is still the default**, so a child started as before has nothing to read.
    val plain = spawn("/bin/sh", ["-c", "exit 0"]).value
    val ignored = spawn("/bin/sh", ["-c", "echo nobody hears this"], { stdout: "ignore", stderr: "inherit" }).value

    assertEq(plain.stdout, null)
    assertEq(plain.stderr, null)
    assertEq(ignored.stdout, null)
    assertEq(ignored.stderr, null)
    await plain.exited
    await ignored.exited

@test
WHAT_spawn_SAYS_ABOUT_AN_OPTION_IT_DOES_NOT_TAKE()
    // **Refused rather than ignored**, naming the key -- a misspelt `stdout` that was quietly dropped
    // would leave a program waiting on a stream it never asked for.
    assertFaults(() -> spawn("/bin/sh", [], anything({ stdot: "pipe" })), "`stdot` is not one of `spawn`'s options")
    assertFaults(() -> spawn("/bin/sh", [], anything({ cwd: "/", timeout: 5 })), "`timeout` is not one of")
    assertFaults(() -> spawn("/bin/sh", [], { stdout: "piped" }), "`stdout` is \"inherit\", \"pipe\" or \"ignore\", and this is \"piped\"")
    assertFaults(() -> spawn("/bin/sh", [], { stderr: true }), "`stderr` is \"inherit\", \"pipe\" or \"ignore\", and this is")
    assertFaults(() -> spawn("/bin/sh", [], { stdout: null }), "`stdout` is \"inherit\", \"pipe\" or \"ignore\", and this is")

@test
async EVERY_OPTION_spawn_TAKES_IS_STILL_TAKEN_TOGETHER()
    val all = spawn("/bin/sh", ["-c", "pwd; printf '%s' \"$A\""],
        { cwd: "/", env: { A: "1" }, ipc: false, stdout: "pipe", stderr: "ignore" })

    assert(all.ok)
    assertEq((await all.value.stdout.text()).value, "/\n1")
    await all.value.exited

@test
WHAT_run_SAYS_ABOUT_AN_OPTION_IT_DOES_NOT_TAKE()
    // **Refused rather than ignored**, as `spawn` does -- a misspelt `timeout` that was quietly
    // dropped would leave a call with no limit.
    assertFaults(() -> run("/bin/sh", [], anything({ timeot: 5 })), "`timeot` is not one of `run`'s options -- there are `cwd`, `env` and `timeout`")
    assertFaults(() -> run("/bin/sh", [], anything({ cwd: "/", stdout: "pipe" })), "`stdout` is not one of `run`'s options")
    assertFaults(() -> run("/bin/sh", [], anything({ ipc: true })), "`ipc` is not one of `run`'s options")
    assertFaults(() -> run("/bin/sh", [], anything({ cwd: 5 })), "`cwd` is a string, and this is")
    assertFaults(() -> run("/bin/sh", [], anything({ env: 5 })), "`env` is an object of names and values")
    assertFaults(() -> run("/bin/sh", [], anything({ timeout: "x" })), "`timeout` is a duration or a number of milliseconds")

@test
async EVERY_OPTION_run_TAKES_IS_STILL_TAKEN_TOGETHER()
    val all = await run("/bin/sh", ["-c", "pwd; printf '%s' \"$A\""], { cwd: "/", env: { A: "1" }, timeout: 30000 })

    assert(all.ok)
    assertEq(all.value.out, "/\n1")
