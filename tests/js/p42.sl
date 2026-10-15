// A builtin's spelling taken by a local, a parameter, a loop head or an import somewhere in the file.
//
// **A binding shadows only within its own scope, from its declaration on**, so every read anywhere
// else in the file is still the builtin. The interpreter resolves a builtin read through a cell the
// file claims for the spelling (`LoadFree`, `defs.sysl`) and puts every such read back to a lookup
// by name once something in the file turns out to bind it; the JavaScript back end hands each
// builtin in as a parameter of the program's wrapper. Each section reads the builtin both before and
// after the function that takes its name, and calls that function in between.

import { regex } from slate:regex

// -- a `val` -------------------------------------------------------------------------------------

sortedAbove() = sorted([3, 1, 2])

takesSorted()
    val sorted = "mine"
    sorted

sortedBelow() = sorted(["b", "a"])

print(sortedAbove(), takesSorted(), sortedBelow())

// -- a `var`, written to -------------------------------------------------------------------------

maxAbove() = max(3, 4)

takesMax()
    var max = 1
    max = max + 1
    max

maxBelow() = max(-1, -2)

print(maxAbove(), takesMax(), maxBelow())

// -- a parameter ---------------------------------------------------------------------------------

keysAbove() = keys({ a: 1, b: 2 })

takesKeys(keys) = keys * 2

keysBelow() = keys({ c: 3 })

print(keysAbove(), takesKeys(21), keysBelow())

// -- a parameter named for a builtin that is called --------------------------------------------

printsThrough(print) = print("through")

print(printsThrough(s -> s"<${s}>"))

// -- a loop head ---------------------------------------------------------------------------------

upperAbove() = upper("a")

takesUpper()
    var said = ""

    for upper in ["x", "y"]
        said = said + upper

    said

upperBelow() = upper("b")

print(upperAbove(), takesUpper(), upperBelow())

// -- a name an import brought in -----------------------------------------------------------------

regexAbove() = regex("a+").test("caab")

takesRegex()
    val regex = 9
    regex

regexBelow() = regex("z").test("caab")

print(regexAbove(), takesRegex(), regexBelow())

// -- the binding's own scope ends where its block does -------------------------------------------

blockScoped()
    var said = []

    if true
        val values = "inner"
        said.push(values)

    said.push(values({ v: 1 }))
    said

print(blockScoped())
