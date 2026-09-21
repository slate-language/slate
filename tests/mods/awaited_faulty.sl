// A module whose faults are raised while a coroutine is running, which is the case a rejection
// reported after the loop has drained gets wrong. THE LINE AND COLUMN OF BOTH FAULTS BELOW ARE
// ASSERTED by `tests_modules.sysl`, so anything added above one of them moves it.
export async fails_after_parking(x) =
    val waited = await x

    waited \ 0

export fails_at_once(x) = x \ 0

// A generator is the other way a machine is set aside and picked up again, and its driver is
// whoever asks for the next value rather than the scheduler.
export counts_then_fails(n)
    yield 1
    yield n \ 0
