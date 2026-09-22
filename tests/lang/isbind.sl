// An `is` whose pattern BINDS, written at the top of a file.
//
// **THIS IS A FILE OF ITS OWN AND IT HAS TO BE.** Whether a module's blocks are asked what they
// declare is a fact about the WHOLE file — one binding `is` anywhere at its top level makes every
// block in it keep the scope it always kept. So an `is` written into `scopes.sl` would quietly put
// that file back on the old path and its tests would stop guarding the new one; the two questions
// need two files.
//
// **`v is n` binds `n` into the scope the match is RUNNING IN**, and it is written as an expression —
// the one name a block can gain that reading its statements never reveals. What these tests pin is
// that it still lands no further out than the block it was written in.

// -- a binding `is` in a one-line branch ----------------------------------------------------------

val tag = "outer"

var bound = []
var i = 0

while i < 3
    if i is tag then push(bound, "bound " + string(tag))
    i = i + 1

@test
A_BINDING_is_IN_A_BRANCH_AT_THE_TOP_OF_A_FILE_DOES_NOT_REACH_THE_FILE()
    // `tag` names a `val` and not a type, so the pattern binds rather than looking anything up — and
    // it binds the branch's own `tag`, which is the turn's number and not the string above it.
    assertEq(bound, ["bound 0", "bound 1", "bound 2"])

    // **The failure this catches is silent.** A branch that stopped opening a scope would land that
    // binding in the file's own, and `tag` would read `2` for the rest of the program.
    assertEq(tag, "outer")

// -- a binding `is` standing alone in a loop body --------------------------------------------------

var perTurn = []
var u = 0

while u < 2
    u is where

    push(perTurn, where)
    u = u + 1

val afterTheLoop = "still here"

@test
A_BINDING_is_IN_A_LOOP_BODY_AT_THE_TOP_OF_A_FILE_IS_READ_BACK_ON_THAT_TURN()
    // The binding is the loop body's, so the statement under it reads what this turn matched.
    assertEq(perTurn, [0, 1])

    // And the scopes balance: a level counted and never pushed would pop the file's own.
    assertEq(afterTheLoop, "still here")

// -- a binding `is` over the spelling of a DEFINITION ------------------------------------------------

// **A definition is the one top-level binding a read may be resolved to while compiling**, so a
// binding `is` that reuses its spelling has to put that read back -- and the names an `is` binds are
// the names no instruction says. The two tests above ask this of a `val`; this asks it of the form
// the resolution was built for.

labelled() = "the definition"

var seen = []
var turn = 0

while turn < 2
    if turn is labelled then push(seen, string(labelled))
    turn = turn + 1

@test
A_BINDING_is_OVER_A_DEFINITIONS_SPELLING_IS_THE_ONE_THAT_ANSWERS() =
    assertEq(seen, ["0", "1"])
    assertEq(labelled(), "the definition")
