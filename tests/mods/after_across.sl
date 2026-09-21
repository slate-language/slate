// A hundred returns, every one of them crossing back into this file from the other one.
//
// `down` calls `ladder`, `ladder` calls `down` again, and each `Ret` has to put back the code buffer
// and the file of the chunk it is going back to. The answer says the code came back; the fault on
// the last line says the file did.

import { ladder } from "./frames_lib.sl"

down(n) = if n <= 0 then 0 else ladder(down, n)

// The OUTERMOST call is the other file's, so the last return of the ladder is one that crosses --
// without that the fault below is stamped by a return from a chunk of this file, and a file that
// was never put back would still read right.
print(ladder(down, 100))

// A fault raised HERE, after the ladder has unwound. It is stamped with the file the machine
// believes it is running, so a return that put back the wrong one quotes the other file at this
// file's offsets.
print(1 \ 0)
