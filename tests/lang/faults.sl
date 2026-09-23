// Faults that carry a VALUE, and the `catch` clauses that sort them by what they are.
//
// **The rule in one line: a thrown STRING is a sentence and everything else is itself.** A string has
// nothing in it a handler could sort on, so it arrives as the `{message, line, file}` object every
// `catch` has always been handed; a data variant, a class instance or a number arrives as the value
// the program threw. Both back ends have to answer the same here, which is the point of this file
// being written in slate rather than in sysl: the interpreter's fault travels as a `Signal` and the
// emitted program's as a JavaScript `Error`, and nothing but a test like this says they agree.

data Failure
    NotFound(id)
    Denied(who)

class Money
    var cents

    toString(self) = s"${self.cents} cents"

// The three ways the tests below raise one.
read(id)
    if id == 0 then throw NotFound(id)
    if id == 1 then throw Denied("guest")

    "row " + string(id)

@test
A_THROWN_VARIANT_IS_CAUGHT_BY_THE_CLAUSE_THAT_NAMES_IT() =
    look(id)
        try
            read(id)
        catch NotFound(which)
            "no row " + string(which)
        catch Denied(who)
            who + " may not"

    assertEq(look(0), "no row 0")
    assertEq(look(1), "guest may not")
    assertEq(look(2), "row 2")

@test
THE_FIRST_CLAUSE_THAT_DOES_NOT_WANT_IT_STANDS_ASIDE_FOR_THE_NEXT() =
    said() =
        try
            read(1)
        catch NotFound(which)
            "first"
        catch Denied(who)
            "second"

    assertEq(said(), "second")

@test
WHAT_A_CLAUSE_BINDS_IS_THE_VALUE_ITSELF() =
    val caught = try
        read(0)
    catch e
        e

    assert(caught is NotFound)
    assertEq(caught.id, 0)

    // And a field of it is read where the clause took it apart, which is what makes the value worth
    // carrying at all.
    val which = try
        throw NotFound(41)
    catch NotFound(n)
        n + 1

    assertEq(which, 42)

@test
A_VALUE_NO_CLAUSE_WANTED_IS_THROWN_AGAIN_AND_THE_OUTER_HANDLER_GETS_IT() =
    said() =
        try
            try
                read(1)
            catch NotFound(which)
                "swallowed"
        catch Denied(who)
            "outer saw " + who

    assertEq(said(), "outer saw guest")

    // With nothing around it, it is the program's fault again.
    unwanted() =
        try
            read(1)
        catch NotFound(which)
            "swallowed"

    assertFaults(unwanted)

@test
A_THROWN_STRING_MEANS_WHAT_IT_ALWAYS_MEANT() =
    gone() =
        throw "gone"

    val e = try
        gone()
    catch e
        e

    assertEq(e.message, "gone")
    assert(e.file is string)
    assert(e.line is integer)

    // A clause naming a type does not want it, and the object's own shape is what a clause matches.
    said() =
        try
            gone()
        catch NotFound(which)
            "a variant"
        catch { message: "gone" }
            "the object"

    assertEq(said(), "the object")

@test
A_FAULT_THE_LANGUAGE_RAISED_IS_NEVER_A_THROWN_VALUE() =
    // **What the runtime raises is not something a program threw**, so no pattern over a program's
    // own types may match one: it arrives as the fault object, whatever the host underneath was
    // holding. Under `slate js` that host error is a JavaScript one and this is what says it is not
    // handed over as a slate value.
    said() =
        try
            1 \ 0
        catch NotFound(which)
            "a variant"
        catch Money(cents)
            "a class"
        catch e
            "fault object: " + e.message

    assertEq(said(), "fault object: this divides by zero")

@test
A_CAUGHT_VALUE_IS_PUT_BACK_WHOLE_BY_throw() =
    said() =
        try
            try
                read(0)
            catch e
                throw e
        catch NotFound(which)
            "again " + string(which)

    assertEq(said(), "again 0")

@test
async A_REJECTED_PROMISE_CARRIES_ITS_VALUE_ACROSS_AN_await() =
    async missing()
        throw NotFound(5)

    val said = try
        await missing()
    catch NotFound(which)
        "no row " + string(which)

    assertEq(said, "no row 5")

    // `reject` raises the same fault from a promise that has already settled, and `fail` from one
    // that had not.
    val rejected = try
        await reject(Denied("guest"))
    catch Denied(who)
        who

    assertEq(rejected, "guest")

    val p = pending()

    fail(p, NotFound(9))

    val failed = try
        await p
    catch NotFound(which)
        which

    assertEq(failed, 9)

@test
async A_STRING_REJECTION_IS_STILL_THE_FAULT_OBJECT() =
    val said = (await reject("no")) catch e -> e.message

    assertEq(said, "no")

@test
AN_UNCAUGHT_VALUE_SAYS_WHAT_THE_VALUE_SAYS() =
    // `assertFaults` compares the sentence an uncaught fault would be reported with, which for a
    // value is the value written the way `print` writes it -- a class's own `toString` included.
    // **`throw` is a statement**, so each of these is a function rather than a one-line lambda.
    variant() =
        throw NotFound(3)

    money() =
        throw Money(150)

    assertFaults(variant, "NotFound(3)")
    assertFaults(money, "150 cents")

    // A `toString` that faults in turn may not replace the fault the program actually threw: the
    // ordinary rendering is what is left, and the hook's own words are nowhere in it.
    raiser() =
        throw "the hook went wrong"

    hooked() =
        throw { toString: raiser }

    assertFaults(hooked, "toString")
