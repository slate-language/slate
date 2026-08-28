// Types: a shape with a name.
//
// **A type is a named pattern and nothing else runs.** slate already tested object shapes -- `v is
// { x: number }` has always worked -- so a type is one of those given a name, resolved where it stands
// while the program is compiled.
//
// It is TypeScript's `type`, and deliberately so. What differs is that slate's is not erased: the
// same declaration is the pattern AND the check at a boundary. TypeScript cannot do the second, which
// is why a TS app that reads an API response writes the shape twice -- once as a `type` for the
// checker and once as a zod schema for the run.

type Point = { x: number, y: number }
type Circle = { centre: Point, radius: number }
type Named = { name: string }

val here = { x: 3, y: 4 }

print(here is Point)
print({ x: 1 } is Point)

// A record grows fields over its life, so a type asks for *at least* these -- a test that broke
// whenever a field was added would be one nobody could keep working.
print({ x: 1, y: 2, drawn: true } is Point)

// A type may be written in terms of another.
print({ centre: here, radius: 2 } is Circle)
print({ centre: { x: 1 }, radius: 2 } is Circle)

// It stands where a match arm does, which is where a discriminated union is read.
describe(v) = v match
    Circle -> s"a circle of radius ${v.radius}"
    Point -> s"the point ${v.x}, ${v.y}"
    Named -> s"something called ${v.name}"
    _ -> "no idea"

for v in [{ centre: here, radius: 1 }, here, { name: "origin" }, 42]
    print(describe(v))

// **And a parameter may say what it takes.** The complaint then lands where the value was handed
// over rather than wherever it was first used wrongly, which is most of what a type buys a language
// that has no checker.
distance(a: Point, b: Point) =
    val dx = a.x - b.x
    val dy = a.y - b.y

    dx * dx + dy * dy

print(distance(here, { x: 0, y: 0 }))
print(distance(here, { x: 0 }) catch e -> s"caught: ${e.message}")

// A bare name that names no type is a binding, exactly as it always was.
print(42 match
    whatever -> s"bound ${whatever}")
