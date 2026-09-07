// What a file may write AROUND its tests, and the assertion for a call that is supposed to fail.
//
// **The order is the whole claim**, so every hook and every test writes a word into one list and the
// tests read it back — which is also the shape a real suite has: `@setupAll` opens something once,
// `@setup` hands each test a clean copy of it, and the teardowns give both back.
var steps = []
var freshEachTime = 0

@setupAll
open_the_file() =
    push(steps, "all")

@setup
before_each() =
    freshEachTime = freshEachTime + 1
    push(steps, "up")

@teardown
after_each() =
    push(steps, "down")

@teardownAll
shut_the_file() =
    push(steps, "shut")

@test
THE_FIRST_TEST_SEES_setupAll_AND_THEN_ITS_OWN_setup() =
    assertEq(freshEachTime, 1)
    assertEq(steps, ["all", "up"])

@test
THE_SECOND_TEST_SEES_THE_FIRST_ONES_teardown() =
    assertEq(freshEachTime, 2)
    assertEq(steps, ["all", "up", "down", "up"])

@test
async A_HOOK_MAY_BE_async_AND_IS_WAITED_FOR() =
    await sleep(0)

    assertEq(freshEachTime, 3)

// -- `assertFaults` --------------------------------------------------------------------------------

// **A fault of the file's own, because the two back ends word their BUILTINS' complaints
// differently** — `anything(1).length` is refused by both and not in the same sentence, so a test
// naming part of the message has to name part of a message slate itself wrote.
raises_plainly() =
    throw "the pump has no handle"

async will_not_settle_well() =
    await sleep(0)

    throw "not this time"

async answers_a_number() =
    await sleep(0)

    42

// A value whose type the checker cannot see, so `.length` below is a run-time fault and not a
// compile-time refusal of the whole file.
anything(v) = v

@test
A_CALL_THAT_RAISES_IS_WHAT_assertFaults_WANTED() =
    assertFaults(() -> anything(1).length)

@test
THE_PART_OF_THE_MESSAGE_MAY_BE_NAMED() =
    assertFaults(raises_plainly, "no handle")

@test
A_CALL_THAT_ANSWERS_IS_A_FAILURE_AND_THE_VALUE_IS_SHOWN() =
    assertFaults(() -> assertFaults(() -> 42), "expected a fault, got a value: 42")

@test
A_MESSAGE_THAT_DOES_NOT_MATCH_IS_A_FAILURE_NAMING_BOTH() =
    assertFaults(() -> assertFaults(raises_plainly, "a socket"), "wanted it to contain \"a socket\"")

@test
async AN_async_CALLS_FAULT_ARRIVES_A_TURN_LATER_AND_IS_AWAITED() =
    await assertFaults(will_not_settle_well)
    await assertFaults(will_not_settle_well, "not this")

@test
async AN_async_CALL_THAT_ANSWERS_IS_A_FAILURE_TOO() =
    val said = try
        await assertFaults(answers_a_number)
        "no complaint at all"
    catch e
        e.message

    assertEq(said, "expected a fault, got a value: 42")

// -- a fault raised BELOW the callback's own frame --------------------------------------------------

// **The call `assertFaults` entered is not the call that faulted**, which is the case a tail call and
// a `catch` both miss. Unwinding leaves the machine standing where the fault was raised, so a native
// that turns a fault into an answer -- which is the whole of what this assertion does -- returns into
// a machine still carrying the frames of a call that is over. What it costs is not this assertion but
// the NEXT return in the test, which reads a frame belonging to something long gone; so each of these
// asserts again afterwards, that being the line the defect actually broke.

thrower() =
    throw "gone"

one_frame_down() =
    val n = thrower()

    n + 1

two_frames_down() =
    val n = one_frame_down()

    n + 1

through_a_closure() =
    val add = n -> thrower() + n

    add(1)

@test
A_FAULT_ONE_FRAME_BELOW_THE_CALLBACK_IS_STILL_THE_FAULT() =
    assertFaults(one_frame_down, "gone")
    assertEq(freshEachTime > 0, true)

@test
A_FAULT_TWO_FRAMES_BELOW_THE_CALLBACK_IS_STILL_THE_FAULT() =
    assertFaults(two_frames_down, "gone")
    assertEq(freshEachTime > 0, true)

@test
A_FAULT_INSIDE_A_CLOSURE_THE_CALLBACK_CALLED_IS_STILL_THE_FAULT() =
    assertFaults(through_a_closure, "gone")
    assertEq(freshEachTime > 0, true)

// **The machine is put back for a CAUGHT fault as well**, the callback having handled it and answered
// -- so this is the same depth arriving through the other door.
answers_after_catching() =
    try
        one_frame_down()
    catch e
        e.message

@test
A_CALLBACK_THAT_CATCHES_BELOW_ITSELF_ANSWERS_AND_THE_TEST_RETURNS() =
    assertFaults(() -> assertFaults(answers_after_catching), "expected a fault, got a value: \"gone\"")
    assertEq(freshEachTime > 0, true)
