// Annotations, which are checked while the program runs.
//
// **The fault is caught rather than left to end the program**, because what is being compared is the
// sentence: an uncaught fault is drawn as a caret diagram by the interpreter and thrown as an
// exception by a JavaScript engine, and neither of those is the thing under test.

g(x) = x

f(y: integer) = y

h() -> integer = g("a")

point(p: { x: number, y: number }) = p.x + p.y

val declared = try
    f(g("a"))
catch e
    e

print(declared.message)
print(declared.line)

val answered = try
    h()
catch e
    e

print(answered.message)

val shaped = try
    point(g(5))
catch e
    e

print(shaped.message)

// And an annotation that holds is worth nothing to look at, which is the point of it.
print(f(41) + 1)
print(point({ x: 1, y: 2.5 }))
