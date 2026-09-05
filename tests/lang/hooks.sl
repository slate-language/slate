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
// differently** — `len(1)` is refused by both and not in the same sentence, so a test naming part of
// the message has to name part of a message slate itself wrote.
raises_plainly() =
    throw "the pump has no handle"

async will_not_settle_well() =
    await sleep(0)

    throw "not this time"

async answers_a_number() =
    await sleep(0)

    42

@test
A_CALL_THAT_RAISES_IS_WHAT_assertFaults_WANTED() =
    assertFaults(() -> len(1))

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
