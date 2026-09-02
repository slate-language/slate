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

// The same mistake written out is now caught while compiling -- the annotation is checked at both
// ends. What reaches the run-time check is a value the compiler could not see the shape of, which is
// exactly what the run-time check is there for: something that arrived from a file, a socket or a
// person. An unannotated function answers `any`, so this is one.
elsewhere(v) = v

print(distance(here, elsewhere({ x: 0 })) catch e -> s"caught: ${e.message}")

// A bare name that names no type is a binding, exactly as it always was.
print(42 match
    whatever -> s"bound ${whatever}")

// **A FIELD THE VALUE NEED NOT HAVE IS MARKED `?`.** Present, it must fit; absent, the shape still
// holds. A nullable union says something else: `tag: string | null` still requires the key to be
// there holding a null.
type Note = { title: string, pinned?: boolean }

print({ title: "a" } is Note, { title: "a", pinned: true } is Note, { title: "a", pinned: 1 } is Note)

// **`&` IS `|`'s DUAL and binds tighter.** Where `|` matches if any alternative does, an
// intersection matches only where every part does -- which is what a value that has accumulated
// fields on its way down through a stack of functions needs, each layer adding its own.
type Authed = { user: { id: integer } }
type Bodied = { body: string }

serve(req: Authed & Bodied) = s"${req.user.id} said ${req.body}"

print(serve({ user: { id: 7 }, body: "hello" }))

// **AND A TYPE IS A VALUE UNDER ITS OWN NAME**, so a function can be handed the shape to check
// against. That is what makes the declaration above the validator: nothing is written twice, and
// there is no schema library to keep in step with it.
print(Note)
print(Note.name())
print(Note.test({ title: "a" }))

// `mismatch` collects every reason rather than stopping at the first, because a person filling in a
// form wants to be told about all of it at once. `path` says where in the value the problem is.
print(Note.mismatch({ pinned: 1 }))

// So a checker is an ordinary function taking a shape.
validated(shape, v) =
    val wrong = shape.mismatch(v)

    if len(wrong) == 0 then s"a good ${shape.name()}" else s"bad ${shape.name()}: ${toJSON(wrong)}"

print(validated(Note, { title: "a" }))
print(validated(Point, { x: 1 }))
