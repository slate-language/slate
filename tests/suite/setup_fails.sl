// A file whose `@setup` cannot do its job.
//
// **The `@teardown` faults too, deliberately.** What a teardown gives back is exactly what a setup
// that stopped halfway had already taken, so it runs however the setup went — and a teardown that
// faults is the only way to SEE that from outside, its own failure being a verdict of its own.
@setup
open_the_thing() =
    throw "the thing would not open"

@teardown
shut_the_thing() =
    throw "and it would not shut either"

@test
one_that_never_runs() =
    assert(false, "a test whose setup failed must not be reached")

@test
another_that_never_runs() =
    assert(false, "nor this one")
