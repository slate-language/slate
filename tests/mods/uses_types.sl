import { Point, origin, isSecret } from "./shapes.sl"

area(p: Point) = p.x * p.y

print(origin() is Point)
print({ x: 1 } is Point)
print(area({ x: 3, y: 4 }))

// `Secret` was not exported, so here it is an ordinary binding rather than a test.
print(5 match
    Secret -> s"bound ${Secret}"
    _ -> "tested")

print(isSecret({ hidden: true }), isSecret(5))
