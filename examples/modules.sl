// Several files, one program.
//
// An import is resolved and compiled before anything runs, so a path is written out in full and
// cannot be computed. What that buys is a circle of imports being refused with the chain named, one
// file being read once however many files import it, and no program having to be `async` merely
// because it imports something.

import { area, measure, howManyMeasured } from "./lib/geometry.sl"
import { title, bullet } from "./lib/text.sl"

// The other form takes the whole module under one name. It is an ordinary object, so `shapes.area`
// is an ordinary field selection.
import * as shapes from "./lib/geometry.sl"

print(title("circles"))

for r in 1..3
    val m = measure(r)

    print(bullet(s"radius ${m.radius}: area ${m.area}"))

print(s"measured ${howManyMeasured()} of them")

// `pi` is not exported, so it is not here -- and asking for it in the import would have been a
// complaint before the program ran.
print(s"the same function, reached both ways: ${area(2) == shapes.area(2)}")
