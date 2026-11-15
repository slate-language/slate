// One sheet imported twice by one file is one sheet.
import "./a.css"
import "./a.css"
import { sheets } from slate:style

print(sheets().length)
