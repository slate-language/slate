// A file whose `@setupAll` cannot do its job, and a `@teardownAll` that runs anyway.
@setupAll
open_the_file() =
    throw "the file would not open"

@teardownAll
shut_the_file() =
    throw "and it would not shut either"

@test
one_that_never_runs() =
    assert(false, "a test whose file was never prepared must not be reached")
