// A module whose own top level goes on writing its variables after binding them, imported by
// `modulevars.sl`. Under `lib/` because the harness walks the top of `tests/lang` only.

// Written by the loop below, so what an importer binds is the value the file FINISHED with -- not
// the `1` it was declared as.
export var settled = 1

var n = 1

while n < 5
    settled = settled * n
    n = n + 1

// Written by the file and read back by a closure it hands out, which reads the variable as it is now.
export var count = 0

step() =
    count = count + 1
    count

export stepper() = step

export peek() = () -> count

// Rebound to something else entirely after the file wrote it, so an import sees the last value's
// KIND as well as its value.
export var shape = [1, 2, 3]

shape = "gone"

// A spelling a function also binds for itself, so every one of the file's sites for it goes back to
// the lookup by name -- the other road the export can take, which has to arrive at the same value.
export var shadowed = 0

shadowed = 5

own() =
    var shadowed = 9
    shadowed

export ownShadowed() = own()
