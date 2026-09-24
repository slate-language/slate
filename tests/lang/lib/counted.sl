// A module whose top level is a counted loop over its own variables, imported by `moduleloop.sl`.
// Under `lib/` because the harness walks the top of `tests/lang` only.

// The loop's head, its increment and a difference all run over cells, so what an importer binds is
// what the loop left there.
export var steps = 0
export var drift = 100

while steps < 40
    drift = drift - 3
    steps = steps + 1
