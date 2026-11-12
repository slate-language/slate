// Functions defined by clauses: what a run of them answers, on every back end.
//
// What the compiler refuses about a run -- arity, a signature, a clause out of place, a guard after
// `| _` -- is `tests_clauses.sysl`; what is here is what a program that compiled DOES.

data Shape
    Circle(r)
    Rect(w, h)
    Empty

fact(0) = 1
fact(n) = n * fact(n - 1)

classify(0) = "zero"
classify(n)
    | n < 0 = "negative"
    | n < 10 = "small"
classify(_) = "large"

sign(n)
    | n < 0 = -1
    | n == 0 = 0
    | _ = 1

fib(n: integer) -> integer
fib(n) | n < 2 = n
fib(n) = fib(n - 1) + fib(n - 2)

area(s: Shape) -> number
area(Circle(r)) = 3 * r * r
area(Rect(w, h)) = w * h
area(Empty) = 0

measure({ kind: "circle", r }) = 3 * r * r
measure({ kind: "rect", w, h }) = w * h

kind(null) = "null"
kind(true | false) = "boolean"
kind(integer) = "integer"
kind(string) = "string"
kind([]) = "empty"
kind([x, ...rest]) = s"array from ${x}"
kind(_) = "something else"

grade(90..) = "A"
grade(n @ 50..<90) = s"pass at ${n}"
grade(_) = "fail"

pair(0, 0) = "origin"
pair(0, y) = s"on the y axis at ${y}"
pair(x, 0) = s"on the x axis at ${x}"
pair(x, y) = x + y

grow(n, by = 10) -> integer
grow(0, by) = by
grow(n, by) = n + by

constant() | false = "never"
constant() = "always"

ends(x)
    | x is string
        val shout = x + "!"
        shout
    | _ = "not text"

anything(v) = v

// -- what a run answers ------------------------------------------------------------------------

@test
A_CALL_RUNS_THE_FIRST_CLAUSE_WHOSE_PATTERNS_MATCH() =
    assertEq(fact(0), 1)
    assertEq(fact(5), 120)
    assertEq(kind(null), "null")
    assertEq(kind(true), "boolean")
    assertEq(kind(3), "integer")
    assertEq(kind("a"), "string")
    assertEq(kind([]), "empty")
    assertEq(kind([7, 8]), "array from 7")
    assertEq(kind({}), "something else")

@test
OBJECT_AND_VARIANT_PATTERNS_TAKE_A_VALUE_APART() =
    assertEq(measure({ kind: "circle", r: 2 }), 12)
    assertEq(measure({ kind: "rect", w: 2, h: 3 }), 6)
    assertEq(area(Circle(1)), 3)
    assertEq(area(Rect(2, 5)), 10)
    assertEq(area(Empty), 0)

@test
RANGES_AND_AT_PATTERNS_READ_AS_THEY_DO_IN_A_MATCH() =
    assertEq(grade(95), "A")
    assertEq(grade(60), "pass at 60")
    assertEq(grade(10), "fail")

@test
SEVERAL_PARAMETERS_ARE_MATCHED_TOGETHER_IN_ORDER() =
    assertEq(pair(0, 0), "origin")
    assertEq(pair(0, 4), "on the y axis at 4")
    assertEq(pair(3, 0), "on the x axis at 3")
    assertEq(pair(3, 4), 7)

@test
NAMES_A_CLAUSE_BINDS_ARE_ITS_OWN() =
    // The `n` the second clause binds is not the first's, and neither leaks to the third.
    assertEq(classify(0), "zero")
    assertEq(classify(-3), "negative")

// -- guards ------------------------------------------------------------------------------------

@test
AN_INLINE_GUARD_TAKES_THE_CLAUSE_ONLY_WHEN_IT_HOLDS() =
    assertEq(fib(0), 0)
    assertEq(fib(1), 1)
    assertEq(fib(10), 55)

@test
A_BLOCK_OF_GUARDS_IS_TRIED_IN_ORDER() =
    assertEq(classify(4), "small")
    assertEq(sign(-5), -1)
    assertEq(sign(0), 0)
    assertEq(sign(9), 1)

@test
WHEN_EVERY_GUARD_FAILS_THE_NEXT_CLAUSE_IS_TRIED() =
    assertEq(classify(40), "large")
    assertEq(constant(), "always")

@test
A_GUARDED_BODY_MAY_BE_A_BLOCK() =
    assertEq(ends("hi"), "hi!")
    assertEq(ends(3), "not text")

// -- a signature -------------------------------------------------------------------------------

@test
A_SIGNATURES_DEFAULT_IS_FILLED_BEFORE_THE_CLAUSES_MATCH() =
    assertEq(grow(0), 10)
    assertEq(grow(3), 13)
    assertEq(grow(3, 1), 4)
    assertEq(grow(by = 5, n = 0), 5)

@test
A_SIGNATURES_ANNOTATION_IS_CHECKED_WHERE_THE_ARGUMENT_ARRIVES() =
    assertFaults(() -> fib(anything("x")), "`n` was declared integer, and was given \"x\"")

// -- no clause matching ------------------------------------------------------------------------

@test
A_VALUE_NO_CLAUSE_TAKES_IS_A_FAULT_NAMING_THE_FUNCTION() =
    assertFaults(() -> measure(anything({ kind: "triangle" })), "no clause of `measure` applies to {kind: \"triangle\"}")
    assertFaults(() -> fact(anything("x")), "`-` does not apply")

@test
SEVERAL_ARGUMENTS_NO_CLAUSE_TAKES_ARE_SHOWN_TOGETHER() =
    only(1, 2) = "yes"

    assertFaults(() -> only(anything(3), 4), "no clause of `only` applies to [3, 4]")

// -- local functions and methods ---------------------------------------------------------------

@test
A_LOCAL_FUNCTION_MAY_BE_DEFINED_BY_CLAUSES_AND_RECUR() =
    count(0) = []
    count(n) = [...count(n - 1), n]

    assertEq(count(3), [1, 2, 3])

@test
A_LOCAL_FUNCTION_SEES_THE_NAMES_AROUND_IT() =
    val base = 100

    offset(0) = base
    offset(n) = base + n

    assertEq(offset(0), 100)
    assertEq(offset(5), 105)

class Counter
    new(var label) = null

    describe(self) | self.label == "" = "unnamed"
    describe(self) = s"counter ${self.label}"

    times(self, 0) = "never"
    times(self, 1) = "once"
    times(self, n) = s"${n} times"

@test
A_METHOD_MAY_BE_DEFINED_BY_CLAUSES() =
    assertEq(Counter("").describe(), "unnamed")
    assertEq(Counter("a").describe(), "counter a")
    assertEq(Counter("a").times(0), "never")
    assertEq(Counter("a").times(1), "once")
    assertEq(Counter("a").times(4), "4 times")

// -- what a run is not -------------------------------------------------------------------------

@test
A_SINGLE_ORDINARY_DEFINITION_IS_UNCHANGED() =
    // `f(n)` with nothing beside it is the function it always was: a missing argument is an absence,
    // not a value no clause takes.
    plain(n) = n ?? "absent"

    assertEq(plain(anything(1)), 1)

@test
A_GENERATOR_MAY_BE_DEFINED_BY_CLAUSES() =
    upTo(0) = yield 0
    upTo(n)
        for i in 0..n
            yield i

    assertEq(array(upTo(0)), [0])
    assertEq(array(upTo(2)), [0, 1, 2])
