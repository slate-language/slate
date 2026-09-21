// Three more ways out of this file and back: a constructor, a builtin running a callback the other
// file wrote, and a generator stepped from here.
//
// A constructor enters the class's `new` where a closure would have been entered; `map` runs its
// callback on a machine of its own and returns into the middle of this chunk; a generator's machine
// is parked and put back. Each answer says the caller's code came back, and the last line says its
// file did.

import { Box, doubled, counting } from "./frames_lib.sl"

print(Box(21).holding())
print([1, 2, 3].map(doubled).join(","))

val g = counting(3)

print(g.next().value)
print(g.next().value)

print(1 \ 0)
