// `slate:actor` -- the same programs on both back ends.
//
// **An actor is a thread with a whole runtime on it under the interpreter and a worker under
// `slate js`**, and everything below is written about what a PROGRAM can see: what crosses, what is
// refused, what an `ask` settles to, and when an actor stops. The two implementations have nothing in
// common but this file, which is the point of it.
//
// What is deliberately not here: a heap ceiling, which a page cannot give at all, and anything about
// how a handle prints, its number being one implementation's slot and the other's worker id.

import { spawn, send, ask, done, stop, detach, me, transfer } from slate:actor
import { date, seconds, months } from slate:time
import { regex } from slate:regex

actor Counter
    var n = 0

    on bump(self, by = 1)
        self.n += by

    on total(self) = self.n

@test
async an_actor_keeps_its_own_state_and_answers_about_it() =
    val c = spawn(Counter)

    send(c.bump, 2)
    send(c.bump)

    assertEq(await ask(c.total), 3)

@test
async a_handler_is_named_by_text_as_well_as_by_reading_it_off_a_handle() =
    val c = spawn(Counter)

    send(c, "bump", 5)

    assertEq(await ask(c, "total"), 5)

actor Squarer
    on square(self, n) = n * n

@test
async four_actors_are_asked_at_once_and_gathered_with_the_ordinary_all() =
    val workers = [spawn(Squarer), spawn(Squarer), spawn(Squarer), spawn(Squarer)]

    assertEq(await all(workers.map((w, i) -> ask(w.square, i + 1))), [1, 4, 9, 16])

actor Waiter
    async on later(self, n)
        await sleep(1)

        n * 2

@test
async an_async_handler_answers_what_its_promise_settles_to() =
    val w = spawn(Waiter)

    assertEq(await ask(w.later, 21), 42)

actor Recorder
    var seen = []

    on note(self, n)
        self.seen.push(n)

    on report(self) = self.seen

@test
async sends_from_one_actor_arrive_in_the_order_they_were_written() =
    val r = spawn(Recorder)

    for i in 0..<200
        send(r.note, i)

    val seen = await ask(r.report)

    assertEq(seen.length, 200)
    assertEq(seen[0], 0)
    assertEq(seen[199], 199)

// -- what a handler cannot reach -----------------------------------------------------------------

val topLevelLimit = 512

actor NameLeaker
    on read(self) = topLevelLimit

@test
async a_handler_reaching_a_top_level_val_faults_with_the_same_sentence_on_both_back_ends() =
    // **`docs/reference/modules.md` says a handler's own module gives it declarations and nothing
    // else**, so a top-level `val` is simply not bound where the handler runs -- reaching it faults
    // exactly as any other undefined name does. This is the interpreter's own sentence, and the
    // JavaScript back end must say the same words rather than the host's -- V8's own `ReferenceError`
    // has no backticks around the name.
    val a = spawn(NameLeaker)
    var said = ""

    try
        await ask(a.read)
    catch e
        said = e.message

    assertEq(said, "`topLevelLimit` is not defined")

// -- what crosses ------------------------------------------------------------------------------

class Point
    var x
    var y

data Shape
    Circle(r)
    Rect(w, h)

actor Echo
    on back(self, v) = v

    on shifted(self, p, by) = Point.new(p.x + by, p.y + by)

    on named(self, s) = s.r

@test
async every_sendable_kind_arrives_as_itself() =
    val e = spawn(Echo)

    assertEq(await ask(e.back, 42), 42)
    assertEq(await ask(e.back, 1.5), 1.5)
    assertEq(await ask(e.back, "text"), "text")
    assertEq(await ask(e.back, true), true)
    assertEq(await ask(e.back, null), null)
    assertEq(await ask(e.back, [1, [2, 3]]), [1, [2, 3]])
    assertEq(await ask(e.back, { a: 1, b: "two" }), { a: 1, b: "two" })
    assertEq(await ask(e.back, 1..<4), 1..<4)
    assertEq(await ask(e.back, date(2026, 9, 18)), date(2026, 9, 18))
    assertEq(await ask(e.back, seconds(90)), seconds(90))
    assertEq(await ask(e.back, months(3)), months(3))
    assertEq(await ask(e.back, regex("a+b")), regex("a+b"))

@test
async a_set_and_a_map_are_rebuilt_with_their_order_kept() =
    val e = spawn(Echo)
    val s = Set().add(3).add(1)
    val m = Map().set("a", 1).set("b", 2)

    // A set prints as its members and a map as its pairs, in the order they were added, which is
    // what "insertion order kept" means where the containers themselves compare by identity.
    assertEq(string(await ask(e.back, s)), "[3, 1]")
    assertEq(string(await ask(e.back, m)), "[[\"a\", 1], [\"b\", 2]]")

@test
async a_class_instance_crosses_as_an_instance_and_not_as_a_plain_object() =
    val e = spawn(Echo)
    val moved = await ask(e.shifted, Point.new(1, 2), 10)

    assert(moved is Point)
    assertEq(moved.x, 11)
    assertEq(moved.y, 12)

@test
async a_data_variant_crosses_as_the_same_variant() =
    val e = spawn(Echo)
    val back = await ask(e.back, Circle(4))

    assert(back is Circle)
    assert(back is Shape)
    assertEq(back.r, 4)
    assertEq(await ask(e.named, Circle(7)), 7)

@test
async shared_structure_arrives_shared_and_a_cycle_arrives_as_a_cycle() =
    val e = spawn(Echo)
    val one = { n: 1 }
    val both = await ask(e.back, { left: one, right: one })

    both.left.n = 9

    assertEq(both.right.n, 9)

    val ring = { name: "a" }

    ring.self = ring

    val back = await ask(e.back, ring)

    assertEq(back.self.self.name, "a")

actor Sizer
    on size(self, b) = b.length

@test
async bytes_are_copied_and_transfer_leaves_the_senders_buffer_empty() =
    val s = spawn(Sizer)
    val copied = toBytes("hello")
    val moved = toBytes("goodbye")

    assertEq(await ask(s.size, copied), 5)
    assertEq(copied.length, 5)

    assertEq(await ask(s.size, transfer(moved)), 7)
    assertEq(moved.length, 0)

// -- identity, addressing and `me` --------------------------------------------------------------

actor Worker
    on introduce(self, boss)
        send(boss.enrol, me())

actor Boss
    var seen = []

    on enrol(self, who)
        self.seen.push(who)

    on count(self) = self.seen.length

    on knows(self, who) = self.seen.contains(who)

@test
async an_actor_hands_its_own_address_to_somebody_with_me() =
    val b = spawn(Boss)
    val w = spawn(Worker)

    send(w.introduce, b)

    await sleep(80)

    assertEq(await ask(b.count), 1)

@test
async a_handle_compares_by_identity_and_crosses_as_the_actor_it_names() =
    val b = spawn(Boss)
    val e = spawn(Echo)

    assert(b == b)
    assert(b != e)

    val back = await ask(e.back, b)

    assert(back == b)

@test
a_handle_outside_a_handler_has_no_me_to_answer() =
    assertFaults(() -> me(), "`me()` is an actor's own handle")

// -- what does not cross -----------------------------------------------------------------------

actor Sink
    on take(self, v) = 1

// A function is a generator BECAUSE it holds a `yield`, so this is the shortest one there is.
counting()
    yield 1

@test
async a_message_may_not_carry_a_function_and_the_refusal_names_the_field() =
    val s = spawn(Sink)

    assertFaults(() -> send(s.take, { handlers: { onDone: () -> 1 } }),
        "a message may not carry a function: `handlers.onDone` is a function")

@test
async a_message_may_not_carry_a_promise_a_generator_or_a_type() =
    val s = spawn(Sink)

    assertFaults(() -> send(s.take, sleep(1)), "a message may not carry a promise")
    assertFaults(() -> send(s.take, counting()), "a message may not carry a generator")
    assertFaults(() -> send(s.take, Point), "a message may not carry a declaration")

@test
async a_message_naming_something_that_is_not_a_handler_is_refused_where_it_arrives() =
    val c = spawn(Counter)
    var said = ""

    try
        await ask(c, "nope")
    catch e
        said = e.message

    assert(said.contains("is not a handler of this actor"), said)

// -- failure, stopping and detaching -------------------------------------------------------------

actor Brittle
    on burst(self)
        throw "it broke"

    on fine(self) = 1

@test
async an_actor_that_faults_dies_and_its_pending_ask_and_done_both_learn_why() =
    val b = spawn(Brittle)
    val ended = done(b)
    var asked = ""
    var ending = ""

    try
        await ask(b.burst)
    catch e
        asked = e.message

    try
        await ended
    catch e
        ending = e.message

    assertEq(asked, "it broke")
    assertEq(ending, "it broke")

@test
async a_later_ask_of_a_dead_actor_rejects_at_once() =
    val b = spawn(Brittle)

    try
        await ask(b.burst)
    catch e
        assertEq(e.message, "it broke")

    await sleep(80)

    var said = ""

    try
        await ask(b.fine)
    catch e
        said = e.message

    assert(said.contains("not running") || said.contains("stopped before it answered this"), said)

@test
async stopping_an_actor_drains_it_and_settles_done_with_null() =
    val c = spawn(Counter)
    val ended = done(c)

    send(c.bump, 4)

    val total = await ask(c.total)

    stop(c)

    assertEq(total, 4)
    assertEq(await ended, null)

@test
async done_on_an_actor_that_has_already_stopped_settles_at_once() =
    val c = spawn(Counter)

    stop(c)

    await done(c)
    assertEq(await done(c), null)

@test
async detach_leaves_an_actor_out_of_what_the_program_waits_for() =
    val c = spawn(Counter)

    detach(c)
    send(c.bump)

    assertEq(await ask(c.total), 1)

actor Slow
    on work(self, rounds)
        var k = 0

        for i in 0..<rounds
            k += i

        k

@test
async a_mailbox_past_its_soft_limit_refuses_rather_than_waiting() =
    val s = spawn(Slow, { mailbox: 2 })

    assertFaults(() -> onceEach(s, 200), "mailbox is full")

// **Written as a definition rather than inline**, a lambda's one-line body being an expression and a
// loop not being one.
onceEach(s, times)
    for i in 0..<times
        send(s.work, 200000)

actor Adder
    var base

    on plus(self, n) = self.base + n

@test
async a_hundred_actors_spawn_answer_and_stop_cleanly() =
    var made = []

    for i in 0..<100
        made.push(spawn(Adder, i))

    val answers = await all(made.map(a -> ask(a.plus, 1)))

    for a in made
        stop(a)

    assertEq(answers.reduce((sum, n) -> sum + n, 0), 5050)

// -- what `spawn` itself refuses ------------------------------------------------------------------

class NotAnActor
    var x

@test
spawn_takes_an_actor_declaration_and_says_so_about_anything_else() =
    assertFaults(() -> spawn(42), "`spawn` takes an actor declaration, and this is an integer")
    assertFaults(() -> spawn(NotAnActor, 1), "is a class -- an actor is declared with `actor`")

@test
spawn_refuses_an_option_it_does_not_have() =
    // **`Squarer` declares no state, which is what makes the object the OPTIONS** -- the options are
    // the last argument only where there is one more than the constructor takes, and an actor whose
    // own constructor wants an object still gets it.
    assertFaults(() -> spawn(Squarer, { hepa: 1 }),
        "`spawn` has no option called `hepa` -- it takes `heap`, `mailbox` and `name`")
    assertFaults(() -> spawn(Squarer, { mailbox: 0 }), "`mailbox` is a positive whole number, and this is 0")
