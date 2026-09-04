// A function that takes an options object apart with defaults, called in a loop -- which is the
// shape `sluice` is written in and the one a binding pattern's defaults cost a chunk its cells for.
//
// **Half the calls leave a name out and half supply it**, and the two are interleaved rather than
// run in blocks: the guarded assignment after the unpack is a branch, and a benchmark that always
// took the same side of it would measure a predicted branch rather than the work.
import { now } from slate:time

sized(opts)
    val { width = 10, height, scale = 2 } = opts

    width * height * scale

run(given, partial)
    var total = 0
    var turns = 0

    while turns < 600000
        total = total + sized(given) + sized(partial)
        turns = turns + 1

    total

val started = now()

print(run({ width: 3, height: 4, scale: 5 }, { height: 4 }))
print((now() - started).millis())
