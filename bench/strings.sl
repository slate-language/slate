// Building a string a piece at a time. The work per iteration is real -- a concatenation that grows
// -- so this is the benchmark where the loop's own names are the smallest share, and a change that
// speeds it up as much as the others is suspicious.
//
// The loop is inside a function for the reason `arith.sl` says.
import { now } from slate:time

run()
    var out = ""
    var i = 0

    while i < 80000
        out = out + "x" + string(i % 10)
        i = i + 1

    len(out)

val started = now()

print(run())
print((now() - started).millis())
