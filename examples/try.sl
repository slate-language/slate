// Handling a fault -- the other half of what a slate program does about failure.
//
// **Two channels, and which one a thing uses says what kind of failure it is.** A file that is not
// there answers a result, because the caller was always going to have to deal with it; a name that
// is not defined raises, because nothing could have anticipated it. Rust and Swift draw the same
// line. `files.sl` is the example for the first; this is the example for the second.

// The postfix form is an expression, so it stands where a value is wanted.
val n = 10 / 0 catch e -> -1

print(n)

// The handler may be a block, because `->` opens one where it ends the line.
val parsed = 1 / 0 catch e ->
    print("falling back, because:", e.message)
    0

print(parsed)

// The block form, for a run of statements rather than a value.
try
    print("this runs")
    print([1, 2, 3][99])
    print("this does not")
catch e
    print("caught at line", e.line, "of", e.file)

// A fault is an ordinary object, so it goes in an array and comes back out.
var trouble = []

for i in 1..4
    try
        if i == 2 then 1 / 0
        print("turn", i, "was fine")
    catch e
        push(trouble, e.message)

print(trouble)

// It carries across calls, however deep.
deep(k) = if k == 0 then 1 / 0 else deep(k - 1)

print(deep(6) catch e -> "came back from " + string(6) + " frames down")

// And across a suspension: a coroutine keeps its handlers while it is set aside, so a promise that
// fails later still raises inside the `try` that was written around the `await`.
async main()
    try
        await reject("the promise said no")
    catch e
        print("caught across an await:", e.message)

    // A result and a fault in the same function, each handled in its own way.
    val text = await readFile("nothing-is-here.txt")

    print(if text.ok then text.value else "no file, and that is not a fault: " + text.error)

main()
