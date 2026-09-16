// Top-level `await` on both back ends.
//
// A file's body is an async context, as an ES module's is: `await` and `for await` are legal at the
// top level, what follows one runs after it has settled, and the program ends when the top level has
// settled and nothing is pending.
//
// The two back ends reach that by different routes, which is what makes this worth running rather
// than reading. The interpreter compiles the file's chunk with the flag an `async` definition's body
// carries and starts it as a coroutine, turning the loop until its promise settles. `slate js` emits
// the file into an `async` function and writes `await` where the program did, which is JavaScript's
// own top-level await under a wrapper rather than at a module's top level.
//
// What could disagree, and is why every ordering below is asserted rather than described: whether a
// statement under an `await` runs after it or before it, whether a timer armed under one is armed at
// the right moment, and whether a `for await` walks its source once.

// -- the value, and the order ------------------------------------------------------------------

print("first")

val plain = await 5

print("awaited a plain value", plain)

async later(ms, v)
    await sleep(ms)
    v

val waited = await later(2, "waited")

print(waited)

// A statement between two `await`s happens between them, which is what writing it there means.
await sleep(2)
print("between")
await sleep(2)
print("after both")

// -- a timer armed below an `await` -------------------------------------------------------------

// **Armed in the resumption, not before it**, so it fires after the line under it rather than
// before. A top level that ran straight through would print these the other way round.
setTimeout(() -> print("timer"), 0)
print("armed it")

await sleep(4)

// -- `for await` ---------------------------------------------------------------------------------

counted(n)
    var i = 0
    val it = {}

    it.next = async () ->
        if i >= n then { done: true, value: null }
        else
            i += 1
            { done: false, value: i * 10 }

    it

for await v in counted(3)
    print("counted", v)

// A generator is the same protocol with the answer already settled, `await` of a plain value being
// that value.
steps()
    yield "a"
    yield "b"

for await s in steps()
    print("step", s)

print("done")
