import { boom } from "./faulty.sl"

val e = try
    boom(1)
catch e
    e

print(e.file)
print(e.line)

// And the file goes back to this one afterwards, which is the half a marker in the caller is for.
val f = try
    1 / 0
catch f
    f

print(f.file)
print(f.line)
