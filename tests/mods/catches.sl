import { boom } from "./raises.sl"

val said = boom() catch e -> s"${e.file}:${e.line} ${e.message}"

print(said)
