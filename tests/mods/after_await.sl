// An `await` on something the other file is computing, resumed twice: once with a value and once
// with a rejection.
//
// A parked machine's frame is what says where the loop picks up, so both resumptions read the code
// and the file out of it rather than out of the chunk table. The answers say the code came back and
// the fault on the last line says the file did.

import { waiting, refusing } from "./frames_lib.sl"

print(await waiting(21))

try
    await refusing()
catch e
    print(s"caught ${e.message}")

print("carried on")

print(1 \ 0)
