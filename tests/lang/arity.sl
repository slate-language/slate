// How many arguments a call may give, and what happens to the ones the callee has no room for.
//
// **A call may give MORE than the function declares and the surplus is dropped**, which is
// JavaScript's rule and TypeScript's; too FEW is still a fault, there being nothing to bind a
// required parameter to and slate storing no absence. Both back ends have to agree about every one
// of these, which is what this file is for -- the JavaScript host drops extras of its own accord and
// would have agreed here by accident rather than by rule, and its own arity guard used to refuse
// them outright.

// A value whose type nobody wrote down, so a call through it reaches the machine rather than the
// checker. It is how the run-time refusals below are asked for.
anything(v) = v

one(a) = a
two(a, b) = a + b
defaulted(a, b = 10) = a + b
gathers(a, ...rest) = [a, rest]

twice(cb: (integer, integer) -> integer) = cb(1, 2)

class Counter
    var n = 0

    bump(self, by) = self.n + by

data Shape
    Circle(r)

@test
A_CALL_MAY_GIVE_MORE_THAN_THE_FUNCTION_DECLARES() =
    assertEq(one(1, 2, 3), 1)
    assertEq(two(1, 2, 3, 4), 3)

    // A lambda is the same function by another spelling, and a zero-parameter one is the case a
    // handler is written as.
    val ignores = () -> "hit"

    assertEq(ignores(1), "hit")
    assertEq(((a) -> a * 2)(5, 6, 7), 10)

@test
A_DEFAULT_IS_STILL_A_DEFAULT_AND_THE_SURPLUS_IS_STILL_DROPPED() =
    assertEq(defaulted(1), 11)
    assertEq(defaulted(1, 2), 3)
    assertEq(defaulted(1, 2, 3), 3)

@test
A_REST_PARAMETER_IS_UNCHANGED_AND_GATHERS_WHAT_IS_LEFT() =
    // **A gathering function has no surplus**: everything past its fixed parameters is what the rest
    // parameter is for, so nothing is dropped.
    assertEq(gathers(1), [1, []])
    assertEq(gathers(1, 2, 3), [1, [2, 3]])

@test
A_METHOD_AND_A_GENERATED_new_DROP_A_SURPLUS_TOO() =
    val c = Counter.new()

    assertEq(c.bump(1, 2), 1)

    // Every field of a class is a parameter of the `new` it was given, and one with an initialiser is
    // optional -- so the arity is a range, and past its upper end the rule is the ordinary one.
    assertEq(Counter.new(5, "spare").n, 5)

    // A data variant is a class from its data type, so it reads the same way.
    assertEq(Circle(3, 4).r, 3)

@test
A_NATIVE_HANDS_A_CALLBACK_AS_MANY_ARGUMENTS_AS_IT_DECLARES() =
    // `map` supplies three and the call binds what it declares; `callbacks.sl` is where what each
    // of the three IS gets pinned.
    assertEq(map([1, 2, 3], v -> v * 2), [2, 4, 6])
    assertEq(map([1, 2, 3], () -> 9), [9, 9, 9])

    // `sorted` hands its comparator two values; one that declares fewer takes the first and is
    // handed nothing else. What such a comparator ORDERS is nobody's business -- that it runs at all
    // is the whole of what is being asked.
    assertEq(sorted([2, 1], a -> a > 0).length, 2)
    assertEq(sorted([2, 1], (a, b) -> a < b), [1, 2])

    val ticks = []

    forEach([1, 2], () -> push(ticks, "tick"))
    assertEq(ticks.length, 2)

@test
A_NAMED_ARGUMENT_CALL_DROPS_A_SURPLUS_POSITIONAL_ONE() =
    // A name says which parameter it fills; a positional argument past the last parameter has none
    // to fill and goes the way it goes in a call with no names in it at all.
    assertEq(defaulted(1, b = 2), 3)
    assertEq(defaulted(1, 2, 3, 4), 3)

@test
TOO_FEW_ARGUMENTS_IS_STILL_A_FAULT_AND_THE_SENTENCE_NAMES_THE_FUNCTION() =
    assertFaults(() -> anything(two)(1), "`two` takes 2 arguments and was given 1")
    assertFaults(() -> anything(two)(), "`two` takes 2 arguments and was given 0")

    // A function with a default takes a RANGE, and the complaint says both ends.
    assertFaults(() -> anything(defaulted)(), "`defaulted` takes from 1 to 2 arguments and was given 0")

    // A gathering function has no upper end at all, so the only thing to say is the floor.
    assertFaults(() -> anything(gathers)(), "`gathers` takes at least 1 argument and was given 0")

    // A lambda has no name to give and the caret is already on it.
    assertFaults(() -> anything((a, b) -> a)(1), "this function takes 2 arguments and was given 1")

@test
A_CALLBACK_THAT_DECLARES_MORE_THAN_THE_NATIVE_SUPPLIES_NAMES_THE_NATIVE() =
    // The reader's function is not wrong; the surface they attached it to cannot feed it. `map`
    // supplies three -- the element, its position and the array -- so a fourth has nothing to fill
    // it.
    assertFaults(() -> map([1], anything((a, b, c, d) -> a)),
        "`map` calls this with 3 arguments and it takes 4 arguments")

@test
AN_ANNOTATED_FUNCTION_TYPE_ASKS_ONLY_WHETHER_A_CALL_OF_THAT_SIZE_IS_TAKEN() =
    // **Only the floor is a limit**, a call giving more than the function declares dropping the
    // surplus -- so a one-parameter function does take a call of two, and the machine's own check
    // on the annotation has to say so or it would refuse a program that runs.
    assertEq(twice(n -> n), 1)
    assertEq(twice((a, b) -> a + b), 3)
    assertEq(twice(() -> 9), 9)

    // Too few is still refused, the annotation promising a call of two and the function requiring
    // three.
    assertFaults(() -> twice(anything((a, b, c) -> a)),
        "`cb` was declared (integer, integer) -> integer")
