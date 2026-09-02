import { Point, isSecret } from "./shapes.sl"

// The type is a VALUE the import bound, so it answers here.
print(Point.name())
print(Point.test({ x: 1, y: 2 }))
print(Point.mismatch({ x: 1 }))

// And it is still a SHAPE the compiler resolved, which is what `is` was emitted against.
print({ x: 1, y: 2 } is Point)

// `Secret` was not exported, so the file that declared it is the only one that can name it.
print(isSecret({ hidden: true }), isSecret(5))
