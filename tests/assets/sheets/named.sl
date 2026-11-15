// Naming a sheet is not bringing it in: only a bare import adds to `sheets()`.
import a from "./a.css"
import { sheets } from slate:style

print(a.trim())
print(sheets().length)
