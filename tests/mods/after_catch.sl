// A fault raised in the other file, unwound through fifty frames of this one, and caught here.
//
// A `catch` carries on in the chunk the `try` was written in, so what the machine is given back is
// the handler's own -- and the statements after it are this file's. The second fault is what says
// so, and it must belong to this file and not to the one that raised the first.

import { raises, ladder } from "./frames_lib.sl"

deeper(n) = if n <= 0 then raises() else deeper(n - 1)

try
    deeper(50)
catch e
    print(s"caught ${e.message}")

// A call that crosses and comes back, so the fault below is stamped by a return out of the other
// file rather than by the catch alone.
print(s"carried on ${ladder(deeper, 0)}")

print(1 \ 0)
