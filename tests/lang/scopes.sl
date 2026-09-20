// What a block at the TOP OF A FILE does with the names it binds.
//
// **EVERY PROGRAM HERE IS WRITTEN AT MODULE LEVEL ON PURPOSE, AND THAT IS THE WHOLE POINT OF THE
// FILE.** A `@test` body is a function, so a loop written inside one asks a question about a
// function's chunk — which `frames.sl` already covers. A module is the other chunk: every name of it
// is one an import reads by name, so none of them can be a numbered cell, and the rule that a block
// opens a scope only where it declares a name into one reaches it by a different route. What these
// tests do is read back what the file's own top level already did.
//
// **NOTHING HERE IS NEW BEHAVIOUR.** Every answer below was the answer before a module's blocks were
// asked whether they declare anything, and that is what makes them worth writing down: the change
// they guard is invisible to a program except where it is wrong.

// -- a closure made on a turn reads that turn's binding -------------------------------------------

var perTurn = []
var shared = 0
var i = 0

while i < 3
    val turn = i

    push(perTurn, () -> turn + shared)
    i = i + 1

shared = 10

var headTurn = []

for k in 0..<3
    push(headTurn, () -> k)

@test
A_CLOSURE_MADE_IN_A_LOOP_AT_THE_TOP_OF_A_FILE_SEES_THE_TURN_IT_WAS_MADE_ON()
    // Three turns, three bindings, three closures — which is what `let` means in JavaScript and is
    // what a scope per turn buys. One scope for the whole loop would make all three read 2.
    assertEq(map(perTurn, (f) -> f()), [10, 11, 12])

    // And a loop HEAD binds per turn for the same reason, through the other question.
    assertEq(map(headTurn, (f) -> f()), [0, 1, 2])

// -- a block's own name is its own ----------------------------------------------------------------

val name = "outer"

var seenInside = ""
var s = 0

while s < 1
    val name = "inner"

    seenInside = name
    s = s + 1

@test
A_BLOCK_AT_THE_TOP_OF_A_FILE_SHADOWS_RATHER_THAN_OVERWRITES()
    // **The failure this catches is silent.** A body that declared into the file's own scope instead
    // of its own would leave `name` reading "inner" for the rest of the program.
    assertEq(seenInside, "inner")
    assertEq(name, "outer")

// -- leaving a block early, with and without a name in it -----------------------------------------

var kept = []
var b = 0

while b < 6
    b = b + 1

    if b == 2 then continue
    if b == 5 then break

    push(kept, b)

var keptDeclaring = []
var c = 0

while c < 6
    val here = c

    c = c + 1

    if here == 1 then continue
    if here == 4 then break

    push(keptDeclaring, here)

val stillHere = "after the loops"

@test
break_AND_continue_AT_THE_TOP_OF_A_FILE_LEAVE_THE_SCOPE_STACK_AS_THEY_FOUND_IT()
    assertEq(kept, [1, 3, 4])
    assertEq(b, 5)

    // The same loop with a name in its body, so the unwinding has a scope to pop rather than none.
    assertEq(keptDeclaring, [0, 2, 3])
    assertEq(c, 5)

    // **The read a pop too many makes fail.** Leaving a block emits one pop per level being left, so
    // a level counted and never pushed takes the FILE's own scope with it — and every name declared
    // at the top of the file stops being there, this one first.
    assertEq(stillHere, "after the loops")

// -- a fault raised and caught inside a loop at the top of a file ---------------------------------

boom(n) =
    if n == 1 then throw "bad"

    "ok " + string(n)

var tried = []
var t = 0

while t < 3
    val got = boom(t) catch e -> "caught " + string(t)

    push(tried, got)
    t = t + 1

val afterTheFault = "still here"

@test
A_try_INSIDE_A_LOOP_AT_THE_TOP_OF_A_FILE_LEAVES_THE_SCOPES_BALANCED()
    // A caught fault cuts the machine back to what the handler recorded, so a turn that raised one
    // has to leave the file exactly where a turn that did not leaves it.
    assertEq(tried, ["ok 0", "caught 1", "ok 2"])
    assertEq(t, 3)
    assertEq(afterTheFault, "still here")

// -- a `match` arm at the top of a file, binding and not binding -----------------------------------

var labels = []
var m = 0

while m < 3
    val label = m match
        0 -> "zero"
        other -> "n" + string(other)

    push(labels, label)
    m = m + 1

@test
A_match_ARM_AT_THE_TOP_OF_A_FILE_BINDS_INTO_ITS_OWN_ARM()
    // The first arm binds nothing and the second binds one name, so the two are the two answers the
    // question has — and an arm that bound into the file's scope would leave `other` behind.
    assertEq(labels, ["zero", "n1", "n2"])

// -- a generator stepped from a loop at the top of a file -------------------------------------------

counting() =
    var g = 0

    while g < 3
        yield g
        g = g + 1

var stepped = []
var gen = counting()
var at = gen.next()

while !at.done
    val v = at.value

    push(stepped, v * 2)
    at = gen.next()

@test
A_GENERATOR_STEPPED_FROM_A_LOOP_AT_THE_TOP_OF_A_FILE_COMES_BACK_TO_THE_RIGHT_SCOPE()
    // Each `next` parks this machine and runs another one, so what is under test is that the file's
    // own scope is the one execution comes back to, turn after turn.
    assertEq(stepped, [0, 2, 4])

// -- a name at the top of a file is still there for a function written below it --------------------

val declaredAtTop = 7

laterReads() = declaredAtTop + shared + b

@test
A_NAME_AT_THE_TOP_OF_A_FILE_IS_STILL_THERE_FOR_A_FUNCTION_WRITTEN_BELOW_IT()
    // A closure captures the scope the file is standing in, so every loop above having opened and
    // shut its own scopes must leave that one untouched.
    assertEq(laterReads(), 22)
