// `.length` on a string, an array and the bytes under text -- on both back ends.
//
// A property is a name read with a `.` that answers a value, with no call, and this is what says the
// two back ends agree about one: `method.sysl`'s `properties_of` is the interpreter's table and
// `js_rt_method.sysl`'s `PROPERTIES` is the JavaScript one, so the corpus is what stops the two
// drifting.
//
// The astral string is the reason this is a corpus file rather than only a unit test. A JavaScript
// host's own `.length` counts UTF-16 units and slate counts CHARACTERS, so an emitted `.length`
// written as the host's would answer 3 for `"a👋"` where the interpreter answers 2 -- and every
// ASCII string in every other test would have hidden it.

// **What hands the machine a value the checker cannot see**, an unannotated function answering `any`
// by design -- without it the refusals below are caught at the compile and the fault is never
// reached.
anything(v) = v

// A write to a property, which is a statement and so needs a body to stand in.
writesLength(v)
    v.length = 5

main()
    // -- what a length is ----------------------------------------------------------------------

    print("abc".length, [1, 2, 3].length)
    print("".length, [].length)

    // Bytes are an array of numbers in slate, so they have one already.
    print(toBytes("héllo").length, toBytes("").length)

    // **Characters, not UTF-16 units.**
    print("a👋".length)
    print("日本語".length, "👋👋👋".length)

    // A property is read through `?.` and by a placeholder exactly as any member is.
    print(map(["a", "bb", "ccc"], _.length))
    print(null?.length ?? "nothing")

    // It is a value like any other, so it counts and compares.
    print([1, 2].length + "abcd".length, "abc".length == 3)

    // -- what a length is not ------------------------------------------------------------------

    // **A property of a builtin kind is read-only**, and the complaint names the property rather
    // than saying the kind has no fields.
    print(writesLength(anything("abc")) catch e -> e.message)
    print(writesLength(anything([1])) catch e -> e.message)

    // **A property is not a method**, and the sentence sends the reader to the property.
    print(anything("abc").length() catch e -> e.message)
    print(anything([1, 2]).length() catch e -> e.message)

    // A kind with no property of that name reads as any missing name on a builtin does.
    print(anything(5).length catch e -> e.message)
    print(anything(null).length catch e -> e.message)

    // **An object is untouched**, its names belonging to the program: a missing one is absent rather
    // than a fault.
    print(anything({ n: 1 }).length ?? "nothing")

main()
