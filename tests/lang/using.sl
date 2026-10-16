// `using` -- a binding whose value is released when the block around it is left.
//
// Every one of the five ways out is here, because the feature is exactly the claim that all five
// release: falling off the end, a `return`, a `break`, a `continue`, and a fault on its way past.
// An `await` and a `yield` are not ways out and are pinned as such.
//
// **A log array is what makes this observable on both back ends**: what a release does is an
// effect, so the test has to watch for it rather than read an answer. The order the log comes out
// in is the whole assertion.

// A resource that writes its own name down when it is released.
made(log, name) = { dispose: () -> push(log, name) }

// A resource whose release fails.
fails(why) =
    throw why

breaks(why) = { dispose: () -> fails(why) }

// A class and a type belong to the top level of a file, so the two tests that want them read these
// rather than declaring their own.
class Handle
    var log
    var name

    dispose(self) = push(self.log, self.name)

type Res = { dispose: function }

@test
a_block_releases_what_it_held_when_it_ends() =
    var log = []

    run() =
        using a = made(log, "a")

        push(log, "body")

    run()
    assertEq(log, ["body", "a"])

@test
several_in_one_block_release_in_reverse() =
    var log = []

    run() =
        using a = made(log, "a")
        using b = made(log, "b")
        using c = made(log, "c")

        push(log, "body")

    run()
    assertEq(log, ["body", "c", "b", "a"])

@test
a_return_releases_before_it_leaves() =
    var log = []

    run() =
        using a = made(log, "a")

        return "answered"

    assertEq(run(), "answered")
    assertEq(log, ["a"])

@test
a_break_releases_and_a_continue_releases_every_turn() =
    var log = []

    run() =
        for i in 0..<3
            using r = made(log, "turn " + string(i))

            if i == 0 then continue
            if i == 2 then break

            push(log, "did " + string(i))

        "done"

    assertEq(run(), "done")
    assertEq(log, ["turn 0", "did 1", "turn 1", "turn 2"])

@test
a_fault_on_its_way_out_releases_and_keeps_its_own_message() =
    var log = []

    run() =
        using a = made(log, "a")

        fails("gone wrong")

    assertEq(run() catch e -> e.message, "gone wrong")
    assertEq(log, ["a"])

// **A release that fails with nothing travelling propagates**, which is what a `finally` throwing
// of its own does. There is no original for it to be suppressed by.
@test
a_release_that_fails_alone_propagates() =
    run() =
        using a = breaks("release failed")

        7

    assertEq(run() catch e -> e.message, "release failed")

// **A release that fails while a fault is travelling rides along as `suppressed`.** The original is
// what the program was told about; the release's own complaint is a field of it.
@test
a_release_that_fails_under_a_fault_is_suppressed() =
    run() =
        using a = breaks("release failed")

        fails("the original")

    val e = run() catch caught -> caught

    assertEq(e.message, "the original")
    assertEq(e.suppressed.message, "release failed")

// **`null` is skipped**, which is TypeScript's rule and is what lets an optional resource be
// written with no branch around the block.
@test
a_null_resource_is_skipped() =
    run() =
        using a = null

        "ran"

    assertEq(run(), "ran")

// **The refusal is at the DECLARATION and not at the release**, so the block has not run when the
// reader is told.
@test
a_value_with_no_dispose_is_refused_where_it_is_acquired() =
    var log = []

    run() =
        using a = 42

        push(log, "body")

    val said = run() catch e -> e.message

    assert(said.indexOf("`using` needs a value with a `dispose` method") != null)
    assertEq(log, [])

@test
a_class_that_writes_dispose_is_a_resource() =
    var log = []

    run() =
        using h = Handle(log, "h")

        "ran"

    assertEq(run(), "ran")
    assertEq(log, ["h"])

// **The binding is `val`'s, so the three shapes a `val` has are the three shapes a `using` has.**
@test
an_annotated_using_binds_and_checks_as_a_val_does() =
    var log = []

    run() =
        using r: Res = made(log, "annotated")

        "ran"

    assertEq(run(), "ran")
    assertEq(log, ["annotated"])

// **A destructuring `using` releases the WHOLE value and binds its parts**, which is the only
// reading that can be right: what was acquired is the value, and the names are a way of reading it.
@test
a_destructuring_using_releases_the_value_it_took_apart() =
    var log = []

    run() =
        using { port } = { port: 99, dispose: () -> push(log, "pair") }

        port

    assertEq(run(), 99)
    assertEq(log, ["pair"])

@test
a_nested_block_releases_before_the_block_around_it() =
    var log = []

    run() =
        using outer = made(log, "outer")

        if true
            using inner = made(log, "inner")

            push(log, "inside")

        push(log, "after")

    run()
    assertEq(log, ["inside", "inner", "after", "outer"])

// **A block is an expression, and the release does not disturb its value.** The resource was
// acquired before that value existed, so it is the lower of the two on the way out.
@test
a_block_holding_a_using_still_answers_its_last_statement() =
    var log = []

    run() =
        using a = made(log, "a")

        "the answer"

    assertEq(run(), "the answer")
    assertEq(log, ["a"])

// **An `await` is NOT a way out**: the block has not been left and the resource is still the
// running program's.
@test
async an_await_does_not_release() =
    var log = []

    async run() =
        using a = made(log, "a")

        await sleep(1)
        push(log, "after the wait")

    await run()
    assertEq(log, ["after the wait", "a"])

// **A `for await` leaves the stack as it found it**, so a `using` around one releases the value it
// acquired -- the loop's way out once left the compiler a slot short, and the release after it reached
// for the wrong value or for none. The resource is the source being walked, which is the shape a
// streamed `fetch` body is read in, and both an ending loop and a `break` are asked.
@test
async a_for_await_inside_a_using_releases_the_source_it_walked() =
    var log = []

    source(name, n) =
        var left = n

        tick() =
            left = left - 1
            return { done: left < 0, value: left }

        return { next: tick, dispose: () -> push(log, name) }

    async walk() =
        using s = source("whole", 2)
        var seen = []

        for await v in s
            push(seen, v)

        push(log, string(seen))

    async stop() =
        using s = source("broken off", 5)

        for await v in s
            if v == 3 then break

        push(log, "stopped")

    await walk()
    await stop()
    assertEq(log, ["[1, 0]", "whole", "stopped", "broken off"])

// **A `yield` is not a way out either**, and an abandoned generator is never left: the release runs
// when the body finally ends.
@test
a_generator_releases_when_its_body_ends() =
    var log = []

    steps() =
        using a = made(log, "a")

        yield 1
        yield 2

    val g = steps()

    assertEq(g.next().value, 1)
    assertEq(log, [])
    assertEq(g.next().value, 2)
    assertEq(log, [])
    assert(g.next().done)
    assertEq(log, ["a"])

// **A release that faults in front of a `break` or a `return` is made once.** It runs while the
// block's own disposal handler is still standing, and that handler used to release the same value a
// second time on the way past.
@test
a_release_that_faults_on_a_break_or_a_return_is_made_once() =
    var count = 0

    release() =
        count = count + 1
        fails("dispose failed")

    counting() = { dispose: release }

    broken() =
        for i in [1, 2]
            using r = counting()
            break

    returned() =
        using r = counting()
        return 1

    assertEq(broken() catch e -> e.message, "dispose failed")
    assertEq(returned() catch e -> e.message, "dispose failed")
    assertEq(count, 2)
