import { Box, isBox, ensureBox } from "./claim_lib.sl"
import { boxed } from "./claim_reexport.sl"

need(b: Box) -> integer = b.size

measure(v: Box | string) = if isBox(v) then need(v) else v.length
again(v: Box | string) = if boxed(v) then need(v) else -1

sure(v: Box | string)
    ensureBox(v)
    need(v)

print(measure({ size: 3 }), measure("abcd"), again({ size: 5 }), again("x"), sure({ size: 7 }))
