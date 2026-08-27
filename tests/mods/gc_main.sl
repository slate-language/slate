import * as lib from "./gc_lib.sl"

var i = 0
while i < 400
    lib.make(200)
    i += 1

print(lib.tag)
print(lib.make(3))
