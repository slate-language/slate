// How many arguments a call may give, and what happens to the ones the callee has no room for.
//
// **AT RUN TIME THE RULE IS JAVASCRIPT'S IN BOTH DIRECTIONS.** A surplus argument is dropped, and a
// parameter the call left out reads as the same absence a missing field reads as -- no count is
// refused by either machine, and both back ends have to agree about every one of these.
//
// **Where the checker can SEE the callee, a wrong count is refused before the program runs**, which
// is TypeScript's half of the same rule and is pinned in `tests_builtins.sysl` instead: a program
// the checker refuses never starts, so it is not something this suite can run. Every call below that
// gives the wrong number therefore goes through a value whose arity nothing wrote down, which is how
// the machine's own rule is asked for.

// A value whose type nobody wrote down, so a call through it reaches the machine rather than the
// checker.
anything(v) = v

one(a) = a
two(a, b) = a + b
second(a, b) = b
boxed(x) = [x]
optional(a, b?) = b ?? 1
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
    assertEq(anything(one)(1, 2, 3), 1)
    assertEq(anything(two)(1, 2, 3, 4), 3)

    // A lambda is the same function by another spelling, and a zero-parameter one is the case a
    // handler is written as.
    val ignores = () -> "hit"

    assertEq(anything(ignores)(1), "hit")
    assertEq(anything((a) -> a * 2)(5, 6, 7), 10)

@test
A_DEFAULT_IS_STILL_A_DEFAULT_AND_THE_SURPLUS_IS_STILL_DROPPED() =
    assertEq(defaulted(1), 11)
    assertEq(defaulted(1, 2), 3)
    assertEq(anything(defaulted)(1, 2, 3), 3)

@test
A_REST_PARAMETER_IS_UNCHANGED_AND_GATHERS_WHAT_IS_LEFT() =
    // **A gathering function has no surplus**: everything past its fixed parameters is what the rest
    // parameter is for, so nothing is dropped.
    assertEq(gathers(1), [1, []])
    assertEq(gathers(1, 2, 3), [1, [2, 3]])

@test
A_METHOD_AND_A_GENERATED_new_DROP_A_SURPLUS_TOO() =
    val c = Counter.new()

    assertEq(anything(c).bump(1, 2), 1)

    // Every field of a class is a parameter of the `new` it was given, and one with an initialiser is
    // optional -- so the arity is a range, and past its upper end the rule is the ordinary one.
    assertEq(anything(Counter).new(5, "spare").n, 5)

    // A data variant is a class from its data type, so it reads the same way.
    assertEq(anything(Circle)(3, 4).r, 3)

@test
A_NATIVE_HANDS_A_CALLBACK_AS_MANY_ARGUMENTS_AS_IT_DECLARES() =
    // `map` supplies three and the call binds what it declares; `callbacks.sl` is where what each
    // of the three IS gets pinned.
    assertEq(map([1, 2, 3], v -> v * 2), [2, 4, 6])
    assertEq(map([1, 2, 3], (v, i) -> v + i), [1, 3, 5])
    assertEq(map([1, 2, 3], (v, i, all) -> v + all.length), [4, 5, 6])
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
    assertEq(anything(defaulted)(1, 2, 3, 4), 3)

@test
A_PARAMETER_THE_CALL_LEFT_OUT_READS_AS_AN_ABSENCE() =
    // **It is the very value a missing field reads as**, so everything that resolves one resolves
    // this: it is `null` to `==`, `??` puts a value in its place, and a test reads it as false.
    assert(anything(second)(1) == null)
    assertEq(anything(second)(1) ?? "gone", "gone")
    assertEq(if anything(second)(1) then "yes" else "no", "no")

@test
AN_ABSENCE_A_CALL_LEFT_BEHIND_STILL_CANNOT_TRAVEL() =
    // **The absence is where the read was and goes no further**, which is slate's own rule and is
    // untouched by any of this: storing one or passing it on is refused where it is attempted.
    assertFaults(() -> anything(boxed)(), "cannot be put in an array")

    // And writing one out is refused in the same words, so a call cannot ask for the default by
    // handing over an absence the way JavaScript's `f(1, undefined)` does.
    assertFaults(() -> second(1, undefined), "cannot be passed to a function")

@test
A_QUESTION_MARK_MARKS_A_PARAMETER_OPTIONAL_WITH_NO_VALUE_OF_ITS_OWN() =
    // `b?` is `b = undefined` down to the bytecode: it drops out of the count the way a default
    // does, and what it binds where nobody gave it is the absence every other parameter now reads
    // as. What it buys over `b = undefined` is saying so in one character.
    assertEq(optional(1), 1)
    assertEq(optional(1, 5), 5)
    assertEq(anything(optional)(), 1)

@test
A_BUILTIN_REACHED_THROUGH_A_VALUE_DROPS_A_SURPLUS_TOO() =
    // A builtin's parameters are not slate's, so this is the one half of the rule it could have got
    // wrong -- the count it is given is its own to read, and reading it as a floor is what makes a
    // builtin behave like everything else.
    val g = anything(sqrt)

    assert(g(4, 5) == 2)
    assert(anything(abs)(-2, "spare") == 2)

@test
AN_ANNOTATED_FUNCTION_TYPE_ASKS_ONLY_WHETHER_A_CALL_OF_THAT_SIZE_IS_TAKEN() =
    // **Only the floor is a limit**, a call giving more than the function declares dropping the
    // surplus -- so a one-parameter function does take a call of two, and the machine's own check
    // on the annotation has to say so or it would refuse a program that runs.
    assertEq(twice(n -> n), 1)
    assertEq(twice((a, b) -> a + b), 3)
    assertEq(twice(() -> 9), 9)

    // A function declaring MORE than the annotation promises is still refused, which is
    // assignability rather than a count at a call: the annotation says a call of two is all this
    // ever gets.
    assertFaults(() -> twice(anything((a, b, c) -> a)),
        "`cb` was declared (integer, integer) -> integer")
