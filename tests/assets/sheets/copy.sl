// `sheets()` answers a fresh array each time, so changing one changes nothing anybody else reads.
import "./a.css"
import { sheets } from slate:style

val s = sheets()

s.push("x")
print(s.length)
print(sheets().length)
