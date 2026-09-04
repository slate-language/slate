// The same arithmetic loop at MODULE level, where every name is a module-level binding rather than
// a function's local.
//
// **It is here to be the control.** A module's names are read by name from outside it -- an import
// is a load per export -- so they cannot become slots in a frame, and what a change to name
// resolution can do for them is at most flatten the walk that finds them. Read beside `arith.sl`,
// this says how much of any improvement is slots and how much is the lookup itself.
import { now } from slate:time

val started = now()

var total = 0
var i = 0

while i < 3000000
    total = total + i * 2 - 1
    i = i + 1

print(total)
print((now() - started).millis())
