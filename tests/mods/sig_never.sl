import { parsed, refuse } from "./sig_lib.sl"

doubled(s)
    val n = parsed(s)

    if n == null then refuse("not a number")

    n * 2

print(doubled("a"))
