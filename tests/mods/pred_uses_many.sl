import { isThere } from "./pred_lib.sl"

count(m: object | null) = if isThere(m) then keys(m).length else 0

print(count(null))
