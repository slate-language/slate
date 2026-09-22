// What a name written at a file's own top level means, wherever in the file it is read.
//
// **A CALL OF ONE OF THESE IS RESOLVED WHILE COMPILING**, so the rule it follows is worth asking of
// the machine rather than reading off the emitter: a definition is in scope from the first line of
// the file, a nearer binding of the same spelling wins wherever there is one, and neither answer
// depends on where in the file the read stands.

add3(a, b, c) = a + b + c

// **Reached from a function written ABOVE it**, which is what hoisting a definition means and is the
// case a read resolved while compiling has to get right: the value is not there when the reading
// function is compiled, and it is there before the reading function is ever called.
early() = later(2)
later(n) = n * 3

// Each reaches the other, so neither can be resolved by having been seen already.
isEven(n) = if n == 0 then true else isOdd(n - 1)
isOdd(n) = if n == 0 then false else isEven(n - 1)

// A definition the file ALSO uses as the spelling of a local. The read below it is compiled before
// the local is reached, so a read resolved eagerly has to be put back to a lookup after the fact.
picked() = "the definition"
readsPicked() = picked()

shadowsPicked() =
    val picked = () -> "the local"

    picked()

// The same through a parameter, which is a binding the machine makes and no instruction names.
named() = "the definition"
readsNamed() = named()
takesNamed(named) = named()

// And through a pattern, whose names the matcher puts down at run time.
grabbed() = "the definition"
readsGrabbed() = grabbed()

destructures(fns) =
    var answer = ""

    for grabbed in fns
        answer = grabbed()

    answer

// A definition inside a FUNCTION is that function's and is bound where it stands.
wraps() =
    helper() = 7

    helper() + 1

// A closure reads the file's definitions through the scope it captured, which is a second way to the
// same value and has to answer the same thing.
doubles(n) = n * 2

inLambda() =
    val f = () -> doubles(21)

    f()

@test
A_DEFINITION_IS_REACHED_FROM_A_FUNCTION_ABOVE_IT() =
    assertEq(early(), 6)
    assertEq(add3(1, 2, 3), 6)

@test
MUTUALLY_RECURSIVE_DEFINITIONS_REACH_EACH_OTHER() =
    assertEq(isEven(10), true)
    assertEq(isOdd(7), true)
    assertEq(isEven(7), false)

@test
A_LOCAL_OF_THE_SAME_SPELLING_IS_THE_ONE_THAT_ANSWERS() =
    assertEq(readsPicked(), "the definition")
    assertEq(shadowsPicked(), "the local")

@test
A_PARAMETER_OF_THE_SAME_SPELLING_IS_THE_ONE_THAT_ANSWERS() =
    assertEq(readsNamed(), "the definition")
    assertEq(takesNamed(() -> "the argument"), "the argument")

@test
A_NAME_A_PATTERN_BOUND_IS_THE_ONE_THAT_ANSWERS() =
    assertEq(readsGrabbed(), "the definition")
    assertEq(destructures([() -> "the element"]), "the element")

@test
A_DEFINITION_INSIDE_A_FUNCTION_IS_THAT_FUNCTIONS_OWN() =
    assertEq(wraps(), 8)

@test
A_CLOSURE_READS_THE_FILES_DEFINITIONS_TOO() =
    assertEq(inLambda(), 42)

@test
A_DEFINITION_IS_A_VALUE_AND_MAY_BE_PASSED_ON() =
    // Reading one without calling it is the same read, so it has to answer the closure rather than
    // anything the resolution happens to be carrying.
    val f = add3

    assertEq(f(1, 2, 3), 6)
    assertEq(map([1, 2], doubles), [2, 4])

// -- a `val` and a `var` at the file's own top level -------------------------------------------------

// **These are read and written through the same table a definition is**, so what they mean is worth
// asking of a running program for the reason the definitions above are: a variable's cell is empty
// until its own statement is reached, a nearer binding of the spelling wins, and a write has to be
// seen by every other way to the same binding.

var counted = 0
val fixedAt = 5

countUp(n)
    var k = 0

    while k < n
        counted = counted + 1
        k = k + 1

    counted

readsFixed() = fixedAt

// Written ABOVE the variable it reads, which is the case the cell has to get right: nothing is in
// the cell when this is compiled and something is by the time it is called.
readsLate() = lateOne

var lateOne = 11

// A lambda that writes the file's own variable, which is a second way to one binding.
bumper() = () ->
    counted = counted + 10
    counted

var pickedVar = "the file's"

shadowsPickedVar()
    var pickedVar = "the local"

    pickedVar = pickedVar + "!"
    pickedVar

@test
A_MODULE_VARIABLE_IS_READ_AND_WRITTEN_FROM_A_LOOP() =
    val before = counted

    assertEq(countUp(3), before + 3)
    assertEq(countUp(2), before + 5)
    assertEq(counted, before + 5)

@test
A_MODULE_VALUE_IS_READ_FROM_A_FUNCTION() =
    assertEq(readsFixed(), 5)
    assertEq(fixedAt, 5)

@test
A_FUNCTION_WRITTEN_ABOVE_A_MODULE_VARIABLE_STILL_READS_IT() =
    assertEq(readsLate(), 11)

@test
A_CLOSURE_WRITES_THE_FILES_OWN_VARIABLE() =
    val before = counted
    val f = bumper()

    assertEq(f(), before + 10)
    assertEq(counted, before + 10)
    assertEq(f(), before + 20)

@test
A_LOCAL_OF_A_MODULE_VARIABLES_SPELLING_IS_THE_ONE_WRITTEN() =
    val before = pickedVar

    assertEq(shadowsPickedVar(), "the local!")
    assertEq(pickedVar, before)
