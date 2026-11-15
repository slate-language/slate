// A sheet imported bare and by name is one file read once: `sheets()` holds it once, and its text is
// the string the name was bound to.
import "./a.css"
import a from "./a.css"
import { sheets } from slate:style

print(sheets().length)
print(sheets()[0] == a)
