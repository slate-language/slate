import { isPresent, isText } from "./pred_lib.sl"
import { present } from "./pred_reexport.sl"

count(m: object | null) = if isPresent(m) then keys(m).length else 0
size(v: string | integer) = if isText(v) then v.length else v + 1
again(m: object | null) = if present(m) then keys(m).length else -1

print(count({ a: 1 }), count(null), size("abc"), size(4), again({ a: 1, b: 2 }), again(null))
