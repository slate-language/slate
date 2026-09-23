// An absence may not be kept in a LOCAL, and both back ends refuse it in the same words.
//
// `undefined` is only ever the immediate answer to a read that found nothing (`docs/reference/
// values.md`), so binding one to a `val`, a `var` or a `for` head, or writing one over a local, is
// refused where it is attempted. The sentence names the local the way the interpreter holds it: "a
// local" for one in a frame slot, and the name itself for one a closure can reach, which lives in a
// scope. `slate js` has to say the same thing, which is what running this file under both is for.

// The sentence, with the one phrase that differs between the refusals left for the caller.
refused(what) = s"this field is not there, and `undefined` cannot be ${what} -- give it a value with `??`, or ask `has` first"

// A counter a test writes to from inside a function, so the write names it rather than a slot.
var tally = 0

// A generator whose one value is an absence, which a `for` then binds.
absent(o) =
    yield o.nope

@test
A_val_OR_A_var_REFUSES_AN_ABSENCE() =
    val o = {}

    assertFaults(() -> boundByVal(o), refused("bound to a local"))
    assertFaults(() -> boundByVar(o), refused("bound to a local"))

boundByVal(o) =
    val x = o.nope
    x

boundByVar(o) =
    var x = o.nope
    x

@test
A_PARAMETER_NOBODY_GAVE_MAY_BE_READ_BUT_NOT_BOUND_AGAIN() =
    // The parameter itself holds the absence -- that is the one binding the rule allows -- and the
    // `val` that tries to keep it is what is refused.
    assertFaults(() -> rebinds(), refused("bound to a local"))
    assertEq(fallsBack(), 7)

rebinds(b?) =
    val y = b
    y

fallsBack(b?) =
    val y = b ?? 7
    y

@test
WRITING_AN_ABSENCE_OVER_A_LOCAL_IS_REFUSED() =
    val o = {}

    assertFaults(() -> writes(o), refused("written to a local"))
    assertFaults(() -> writesTwo(o), refused("written to a local"))
    assertFaults(() -> fillsIn(o), refused("written to a local"))
    assertFaults(() -> writesParameter(o, 1), refused("written to a local"))

writes(o) =
    var x = 1
    x = o.nope
    x

writesTwo(o) =
    var a = 1
    var b = 2
    a, b = o.nope, 3
    a

fillsIn(o) =
    var a = null
    a ??= o.nope
    a

writesParameter(o, b) =
    b = o.nope
    b

@test
A_for_HEAD_REFUSES_AN_ABSENCE_A_GENERATOR_YIELDED() =
    assertFaults(() -> walks({}), refused("bound to a local"))

walks(o) =
    var n = 0

    for x in absent(o)
        n += 1

    n

@test
A_LOCAL_A_CLOSURE_REACHES_IS_REFUSED_BY_ITS_NAME() =
    // A name a closure reads is kept in a scope rather than a slot, and the machine names it.
    val o = {}

    assertFaults(() -> capturedVal(o), refused("bound to `x`"))
    assertFaults(() -> capturedWrite(o), refused("written to `x`"))
    assertFaults(() -> capturedHead(o), refused("bound to `x`"))

capturedVal(o) =
    val x = o.nope
    val read = () -> x
    read()

capturedWrite(o) =
    var x = 1
    val read = () -> x
    x = o.nope
    read()

capturedHead(o) =
    for x in absent(o)
        val read = () -> x
        read()

@test
A_WRITE_TO_A_NAME_OUTSIDE_THE_FUNCTION_IS_REFUSED_BY_ITS_NAME() =
    assertFaults(() -> writesOuter({}), refused("written to `tally`"))
    assertEq(tally, 0)

writesOuter(o) =
    tally = o.nope

@test
WHAT_THE_RULE_ALLOWS_STILL_RUNS() =
    // The read itself, `??` and `has` are how an absence is resolved where it appears, and none
    // of them keeps one.
    val o = {}
    val filled = o.nope ?? "default"
    var later = 1

    later = o.nope ?? 2

    assertEq(filled, "default")
    assertEq(later, 2)
    assertEq(has(o, "nope"), false)
    assertEq(o.nope == undefined, true)

    // A pattern's own binding may take one; only a `val`, a `var`, a write or a `for` head keeps.
    val seen = o.nope match
        x -> "matched"

    assertEq(seen, "matched")
