// The order `sheets()` answers in is the order the loader first meets each sheet: `widget.sl` is
// followed before the next line, so its two come first, and `a.css` asked for again is not moved.
import { name } from "./widget.sl"
import "./c.css"
import "./a.css"
import { sheets } from slate:style

print(sheets().map(s -> s.trim()).join(" | "))
