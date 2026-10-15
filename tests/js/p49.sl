// The handlers of one signal run in the order they were registered, on both back ends.
//
// **node's rule, and the interpreter has to keep it.** `process.on` calls a signal's listeners in
// registration order. libuv calls its signal handles in the order of its own tree, which is by
// address, so a watcher per handler would make the order the allocator's. This program raises
// `SIGWINCH` -- whose default is to be ignored, so a delivery missed is harmless -- by having a child
// shell signal its parent, and prints what each delivery ran:
//
//     three handlers run a, b, c;
//     with the middle one stopped they run a, c;
//     a handler added while a delivery is running is heard from the next delivery on;
//     a handler stopped while a delivery is running still runs for that delivery.

import { onSignal, offSignal, spawn } from slate:process

val log = []
var shown = 0

async until(f, ms)
    var left = ms

    while left > 0 && !f()
        await sleep(20)

        left = left - 20

    f()

// Send this program a SIGWINCH and wait for `n` handler calls to have been made because of it.
async raise(n)
    await spawn("/bin/sh", ["-c", "kill -WINCH $PPID"]).value.exited
    await until(() -> log.length >= shown + n, 4000)

// Print what has run since the last time.
flush()
    for i in shown..<log.length
        print(log[i])

    shown = log.length

async main()
    val a = onSignal("SIGWINCH", () -> log.push("a"))
    val b = onSignal("SIGWINCH", () -> log.push("b"))
    val c = onSignal("SIGWINCH", () -> log.push("c"))

    await raise(3)
    flush()

    offSignal(b)
    await raise(2)
    flush()

    offSignal(a)
    offSignal(c)

    var qid = 0
    var once = false

    onSignal("SIGWINCH", () ->
        log.push("p")
        if !once
            once = true
            offSignal(qid)
            onSignal("SIGWINCH", () -> log.push("late")))

    qid = onSignal("SIGWINCH", () -> log.push("q"))

    await raise(2)
    flush()

    await raise(2)
    flush()

    print("done")

main()
