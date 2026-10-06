import { pair, greet, count, loose, label } from "./sig_lib.sl"

print(pair(1, 2), greet("a"), greet("a", "?"), count(1), count(1, 2, 3), loose("s"), loose(2.5), label)
