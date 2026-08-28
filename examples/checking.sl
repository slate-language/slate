// What the compiler can say about a program without running it.
//
// slate is dynamically typed and stays that way. The static pass moves a fault from the run that
// finds it to the compile that could have, and never invents one: everything it is not sure of is
// `any`, which fits everything. That is TypeScript's bargain, and the reason an unannotated
// parameter says nothing at all.

// An annotated parameter is checked at both ends. Written out, the mistake is caught while
// compiling; arriving from outside, it is caught where the value is handed over.
area(width: number, height: number) = width * height

print(area(3, 4))
print(area(2.5, 4))

// Uncomment either of these and the program will not compile:
//
//     print(area(3))              `area` takes 2 arguments and this gives it 1
//     print(area("3", 4))         `area` takes number here, and this is string

// An integer does not fit a `real`, because a type test does not promote where arithmetic does --
// the checker mirrors the machine and may not drift from it.
halve(x: real) = x / 2

print(halve(9.0))
print(halve(3.0 * 3))

// A shape written at the call is checked; the same shape reached through a name is not, because an
// object is mutable and a shape recorded when it was built goes out of date with nothing local
// saying so. A stale shape is too narrow, and refusing a program that runs is the one mistake this
// pass may not make.
type Point = { x: number, y: number }

distance_from_origin(p: Point) = p.x * p.x + p.y * p.y

print(distance_from_origin({ x: 3, y: 4 }))

//     print(distance_from_origin({ x: 3 }))
//         `distance_from_origin` takes { x: number, y: number } here, and this is { x: integer }

// An operator whose two sides cannot meet is refused now rather than then.
//
//     print(1 + "a")              `+` does not apply to integer and string

// And everything the pass cannot see is left alone. A `var` may hold anything over its life, a
// builtin has no signature here, and a name a pattern bound is unknown -- so none of these is
// checked, and all of them run.
var holds = 1

holds = "text"
print(area(len(holds), 2))

print("done" match
    whatever -> whatever)

// A test narrows the name it tested, so a call inside the branch is checked against what the test
// proved. `&&` narrows by both, and a negated test narrows the other branch.
describe(v) =
    if v is string
        upper(v)
    elif v is number
        v * 2
    else
        "something else"

print(describe("shout"), describe(21), describe(true))

// A `var` is never narrowed, because the branch may write to it -- and a stale narrowing would be
// too narrow, which is refusing a program that runs.
