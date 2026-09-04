// A method call per iteration: a name lookup for the receiver, a field lookup for the method, the
// receiver rule and a frame. This is the benchmark a change to how a local is found should move
// most, since a call is where the frames are.
//
// The loop is inside a function for the reason `arith.sl` says.
import { now } from slate:time

class Counter
    var n

    bump(self, by) = Counter(self.n + by)

run()
    var c = Counter(0)
    var i = 0

    while i < 400000
        c = c.bump(1)
        i = i + 1

    c.n

val started = now()

print(run())
print((now() - started).millis())
