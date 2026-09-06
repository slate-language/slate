// The eighteen library additions a JavaScript person reaches for, on both back ends.
//
// **Every one of them is written twice** — once for the interpreter in `text.sysl`, `value.sysl`,
// `reshape.sysl` and `combine.sysl`, and once for the JavaScript back end in `js_rt_builtins.sysl`
// and `js_rt_host.sysl` — so this file is what says the two readings are one language. Nothing
// here is shared between the halves but the tree this program parses to.
//
// **The refusals are here for the same reason the answers are.** A sentence is what a program's
// reader gets, so two back ends faulting in different words about one mistake is a disagreement
// like any other; several of the lines below are the shortest input that produces one.
//
// **`toFixed` and `formatNumber` are the pair worth reading twice.** JavaScript's `toFixed` rounds
// a tie away from zero and C's `printf` rounds one to the even digit, so the interpreter does that
// arithmetic exactly rather than handing it to the host — and `2.5` at nought places is where the
// two rules disagree.

// -- text ------------------------------------------------------------------------------------------

print("[" + padStart("7", 3) + "]", "[" + padEnd("7", 3) + "]")
print("[" + padStart("42", 6, "0") + "]", "[" + padEnd("ab", 7, "-") + "]")

// A filler of more than one character repeats and is CUT where it does not fit.
print("[" + padStart("x", 6, "ab") + "]", "[" + padEnd("x", 6, "ab") + "]")

// **The width is in CHARACTERS**, which is why neither back end may hand this to JavaScript's own
// `padStart`: that one counts UTF-16 units, so a name with an emoji in it comes out a column short.
print("[" + padStart("🙂", 4, "-") + "]", "[" + padEnd("café", 6, ".") + "]")

// A string already at the width, or past it, is itself.
print("[" + padStart("hello", 5) + "]", "[" + padStart("hello", 2) + "]")

// **`replaceAll` IS `replace`**, slate's having always changed every occurrence.
print(replaceAll("a,b,c", ",", ";"), replace("a,b,c", ",", ";"))
print("1,234,567".replaceAll(",", ""))

// **`includes` IS `contains`**, and it answers about a string and about an array.
print(includes("hello", "ell"), includes("hello", "xyz"))
print(includes([1, 2, 3], 2), includes([1, 2, 3], 9))
print("hello".includes("he"), [1, 2, 3].includes(3))

// -- numbers ---------------------------------------------------------------------------------------

print(toFixed(3.14159, 2), toFixed(1.5, 0), toFixed(2.5, 0), toFixed(-2.5, 0))
print(toFixed(0.1, 5), toFixed(1234.5678, 2), toFixed(1.005, 2))
print(toFixed(7, 2), toFixed(7, 0), toFixed(-1.45, 1))
print((3.14159).toFixed(3), (42).toFixed(1))

print(formatNumber(1234567), formatNumber(-1234567), formatNumber(0), formatNumber(123))
print(formatNumber(1000), formatNumber(999), formatNumber(1000000))
print(formatNumber(toFixed(1234.5, 2)), formatNumber(toFixed(-1234.5, 2)))
print(formatNumber(1234567, { separator: " " }), formatNumber(1234567, { separator: ".", decimal: "," }))
print((1234567).formatNumber())

// -- arrays ------------------------------------------------------------------------------------------

val nums = [1, 2, 3, 4, 5, 6, 7]

// **The key is `string(f(x))`**, so the answer is an ordinary record: its keys are text, `keys`
// walks it and `toJSON` writes it.
val parity = groupBy(nums, n -> n % 2)

print(keys(parity))
print(parity["0"], parity["1"])
print(groupBy(["apple", "avocado", "beet"], s -> s[0]))

// A group is an array even where it holds one element.
print(groupBy([5], n -> n))

print(zip([1, 2, 3], ["a", "b", "c"]))

// **The SHORTEST array decides the length**, so nothing in the answer was in none of the inputs.
print(zip([1, 2, 3], ["a"]), zip([1, 2], ["a", "b"], [true, false]))
print(zip([1, 2, 3]), zip([], [1, 2]))

print(unique([1, 2, 2, 3, 1, 3]), unique(["a", "a", "b"]), unique([]))

// Equality is `==`, which is the question `contains` asks, so two objects with the same fields are
// one element.
print(unique([{ a: 1 }, { a: 1 }, { a: 2 }]))

print(chunk(nums, 2), chunk(nums, 3), chunk(nums, 10), chunk([], 2))

print(count(nums, n -> n > 4), count(nums, n -> false), count([], n -> true))

val [even, odd] = partition(nums, n -> n % 2 == 0)

print(even, odd)
print(partition([], n -> true))

val people = [{ name: "ann", age: 31 }, { name: "bo", age: 24 }, { name: "cy", age: 31 }]

// **The ELEMENT and not the key**, and the FIRST of two equal keys wins.
print(minBy(people, p -> p.age), maxBy(people, p -> p.age))
print(minBy([], p -> p), maxBy([], p -> p))
print(minBy(["bbb", "a", "cc"], s -> s.length))

// Every one of them is a method too, `xs.chunk(2)` being `chunk(xs, 2)`.
print(nums.chunk(4), nums.unique(), nums.count(n -> n < 3))
print([1, 2].zip(["a", "b"]), people.maxBy(p -> p.age).name)
print(nums.partition(n -> n > 5), [3, 1, 2].minBy(n -> n))

// **The CHECKER refuses most of these where they are written**, which is the pass working -- so a
// value whose type it cannot see is what makes the machine.s own sentence reachable at all. An
// unannotated function answers `any` by design and permanently, which is the established way here.
anything(v) = v

// -- what each of them refuses -----------------------------------------------------------------------

print(chunk(nums, 0) catch e -> e.message)
print(chunk(nums, -1) catch e -> e.message)
print(chunk(nums, anything("two")) catch e -> e.message)
print(groupBy(anything(5), n -> n) catch e -> e.message)
print(count(anything("abc"), n -> n) catch e -> e.message)
print(zip() catch e -> e.message)
print(zip([1], 2) catch e -> e.message)
print(padStart("x", -1) catch e -> e.message)
print(padStart("x", 3, "") catch e -> e.message)
print(padEnd("x", 3, "") catch e -> e.message)
print(replaceAll("abc", "", "!") catch e -> e.message)
print(toFixed(1.5, -1) catch e -> e.message)
print(toFixed(1.5, 200) catch e -> e.message)
print(formatNumber(anything(1.5)) catch e -> e.message)
print(formatNumber("twelve") catch e -> e.message)
print(formatNumber(12, { seperator: "," }) catch e -> e.message)
print(formatNumber(12, { separator: 5 }) catch e -> e.message)

// **A SPREAD IS NOT COUNTED BY THE CHECKER**, which is what makes a wrong-arity refusal reachable
// from a program at all: written out, `unique(a, b)` is refused where it stands and this file would
// not compile. So the count arrives at run time, which is the check both back ends are making.
val two = [[1, 2], 3]
val one = [[1, 2]]
val none = []

print(unique(...two) catch e -> e.message)
print(chunk(...none) catch e -> e.message)
print(minBy(...one) catch e -> e.message)

// -- waiting on many promises at once ------------------------------------------------------------------

// **A plain value in the array is a value that has already arrived**, which is `resolve`'s own
// reading and is what makes `all([cached, fetched()])` a line a program can write.
async slow(ms, v)
    await sleep(ms)
    v

async bad(ms, why)
    await sleep(ms)
    await reject(why)

async main()
    print(await all([slow(10, 1), slow(1, 2), 3]))
    print(await all([]))
    print((await all([slow(1, 1), bad(1, "no good")])) catch e -> e.message)
    print((await all([bad(1, "first"), bad(5, "second")])) catch e -> e.message)

    val settled = await allSettled([slow(1, "yes"), bad(1, "nope")])

    // **slate's RESULT shape and not JavaScript's `{ status, value | reason }`**, which is what
    // `parseJSON`, every `Sync` call in `slate:fs` and `run` already answer.
    print(settled)
    print(settled[0].ok, settled[0].value, settled[1].ok, settled[1].error)
    print(await allSettled([]))

    print(await race([slow(1, "quick"), slow(50, "slow")]))
    print((await race([bad(1, "lost"), slow(50, "won")])) catch e -> e.message)
    print(await race([7, slow(1, "later")]))

    print(await any([bad(1, "one"), slow(5, "two")]))
    print((await any([bad(1, "one"), bad(5, "two")])) catch e -> e.message)

    // **`race([])` and `any([])` FAULT rather than answering a promise that never settles**, which
    // is what JavaScript does and is a program that hangs and says nothing.
    print(race([]) catch e -> e.message)
    print(any([]) catch e -> e.message)
    print(all(anything(5)) catch e -> e.message)
    print(allSettled(anything("no")) catch e -> e.message)
    print(race(...two) catch e -> e.message)

main()
