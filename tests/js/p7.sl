// The event loop: timers, `sleep`, and the promises a program makes for itself.
//
// **What this pins is the ORDER**, which is the part two implementations of an event loop can
// disagree about while both being reasonable: a timer fires after the code that started it, a
// shorter delay fires before a longer one, and an `await` resumes where the promise settled.
//
// **The phases run one after another, and that is the test's own correctness rather than slate's.**
// Two timers due at the same instant fire in an order neither loop promises, and a repeating timer
// drifts by however long its callback took -- so a program comparing two loops must not ask them
// either question. Each phase here has the loop to itself and waits for its own end.

async timers()
    val done = pending()

    setTimeout(() -> print("timer 0"), 0)
    setTimeout(() -> print("timer 30"), 30)
    setTimeout(() -> print("timer 15"), 15)
    setTimeout(() -> settle(done, null), 45)

    // A timer cancelled before it is due says nothing at all, cancelling it twice is not an error,
    // and neither is cancelling one that never existed.
    val id = setTimeout(() -> print("never"), 5)

    clearTimeout(id)
    clearTimeout(id)
    clearTimeout(9999)

    await done

// An interval that stops itself, which is the only kind a program that means to end can use.
async counting()
    val done = pending()
    var n = 0
    var id = null

    tick() =
        n += 1

        print(s"tick ${n}")

        if n == 3
            clearInterval(id)
            settle(done, null)

    id = setInterval(tick, 5)

    await done

// `pending` is the bridge from a callback into `await`: nothing else makes a promise that something
// outside slate answers.
async bridged()
    val p = pending()

    setTimeout(() -> settle(p, "answered"), 10)

    print(await p)

async refused()
    val p = pending()

    setTimeout(() -> fail(p, "no good"), 10)

    val said = try
        await p
    catch e
        e.message

    print(said)

// `resolve` and `reject` adapt something that has already happened.
async settled()
    print(await resolve(7))

    val said = try
        await reject(42)
    catch e
        e.message

    print(said)

    // A second answer is dropped rather than refused.
    val p = pending()

    settle(p, "first")
    settle(p, "second")

    print(await p)

async slowly(ms, v)
    await sleep(ms)
    v

async waiting()
    print(await slowly(10, "waited"))
    print(await slowly(0, "and again"))

async everything()
    print("start")

    await timers()
    await counting()
    await settled()
    await bridged()
    await refused()
    await waiting()

    print("done")

everything()
