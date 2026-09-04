// A tight arithmetic loop: two locals read and written every iteration and nothing else.
//
// **The loop is inside a function, and that is the whole point of the file.** A name written at the
// top of a module is a module-level binding that an importer reads by name, so it stays in a table
// however locals are resolved; a name inside a function is the one that can become a numbered slot.
// A benchmark at the margin would measure the half this work does not change.
import { now } from slate:time

run()
    var total = 0
    var i = 0

    while i < 3000000
        total = total + i * 2 - 1
        i = i + 1

    total

val started = now()

print(run())
print((now() - started).millis())
