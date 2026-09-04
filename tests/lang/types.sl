// What an annotation does when the program RUNS, on whichever back end is running it.
//
// The checker's side of all of this -- what it refuses before the program starts -- is in sysl, in
// `tests_types.sysl`. What is here is the half a running program can see: a check that fires where a
// value arrives, a function type asking what it can ask, and a type parameter that asks nothing
// because there is nothing at run time for it to ask.

type Handler = (string, integer) -> boolean
type Pair[A, B] = { first: A, second: B }
type MaybeFn = (integer -> integer) | null
type Spot = { x: number, y: number }
type Wrapper = { inner: object }

anything(v) = v

@test
a_binding_says_what_it_holds_and_is_checked_where_it_is_bound() =
    val x: number = 1
    var n: integer = 0

    n += 1

    assertEq(x, 1)
    assertEq(n, 1)

    // **The check is the annotation's pattern, tested where the value arrives** -- so a value the
    // checker could not see the type of is refused here rather than never.
    val said = (declared(anything("no"))) catch e -> e.message

    assert(said.contains("was declared integer"))

declared(v) =
    val n: integer = v

    n

@test
a_type_is_written_inline_wherever_a_type_is_wanted() =
    // Every form in one program: a bare one-parameter function type, a bracketed list, brackets that
    // group, a union holding a function, and a type given to a generic type.
    apply(f: integer -> integer) -> integer = f(1)
    check(h: Handler) = h("ab", 2)
    keep(xs: array of (string | null)) = len(xs)
    run(f: MaybeFn) = if f is null then 0 else f(2)
    show(p: Pair[string, integer]) = s"${p.first}=${p.second}"

    assertEq(apply(n -> n + 1), 2)
    assert(check((s, n) -> len(s) == n))
    assertEq(keep(["a", null]), 2)
    assertEq(run(null), 0)
    assertEq(run(n -> n * 10), 20)
    assertEq(show({ first: "a", second: 1 }), "a=1")

@test
a_function_type_tests_callability_and_the_count() =
    apply(f: (integer, integer) -> integer) = 1

    // A function that takes two is what it asks for; one that takes one is not, and neither is a
    // value that is not callable at all. **A type parameter's own types are not asked about** --
    // nothing about a function value could answer what it will do with what it is given.
    assertEq(apply(anything((a, b) -> a + b)), 1)
    assert(apply(anything(n -> n)) catch e -> true)
    assert(apply(anything("no")) catch e -> true)

    // A function with a default takes a call of either size, so it fits both.
    twoOrOne(a, b = 2) = a + b

    assertEq(apply(anything(twoOrOne)), 1)

    // And one that gathers takes a call of any size at all.
    gathers(...rest) = len(rest)

    assertEq(apply(anything(gathers)), 1)

@test
a_lambdas_parameter_may_be_annotated_and_is_checked_when_it_is_called() =
    val g = (n: integer) -> n + 1

    assertEq(g(2), 3)

    val said = (g(anything("x"))) catch e -> e.message

    assert(said.contains("was declared integer"))

@test
a_rest_parameter_is_annotated_as_the_array_it_gathers_into() =
    count(...rest: array of integer) = len(rest)

    assertEq(count(1, 2, 3), 3)
    assertEq(count(), 0)

    val said = (count(1, anything("a"))) catch e -> e.message

    assert(said.contains("was declared array of integer"))

@test
a_type_parameter_is_erased_so_it_tests_nothing() =
    // **This is what "solved in the checker" costs at run time, and it is the whole cost.** `T`
    // matches anything, so nothing here tests that the two arguments agreed -- which is why a call
    // that disagrees has to be refused while compiling or not at all.
    pair[T](a: T, b: T) -> array of T = [a, b]

    assertEq(pair(1, 2), [1, 2])

    // A union the PROGRAM declared is one type, so this agrees and runs.
    val mixed: integer | string = "x"

    assertEq(pair(mixed, "y"), ["x", "y"])

    first[T](xs: array of T) -> T = xs[0]

    assertEq(first(["a", "b"]), "a")
    assertEq(first([1, 2]), 1)

@test
a_generic_type_is_substituted_and_the_shape_that_comes_out_is_tested() =
    // `Pair[string, integer]` is the object shape both declarations describe, so the test at run
    // time is the ordinary shape test -- the substitution happened while compiling.
    assert({ first: "a", second: 1 } is Pair[string, integer])
    assert(!({ first: "a", second: "b" } is Pair[string, integer]))
    assert(!({ first: "a" } is Pair[string, integer]))

@test
a_type_is_a_value_and_a_generic_one_carries_the_shape_with_nothing_filled_in() =
    // **A type is a value, and a GENERIC type's value is the shape with every parameter standing
    // for anything** -- which is all a shape with no arguments given to it could ask. The arguments
    // are a compiling-time thing: `p is Pair[string, integer]` is substituted where it is written,
    // and there is no value to hand them to afterwards.
    assertEq(Handler.name(), "Handler")
    assertEq(Pair.name(), "Pair")
    assert(Pair.test({ first: "a", second: 1 }))
    assert(Pair.test({ first: 1, second: "a" }))
    assert(!Pair.test({ first: 1 }))
    assertEq(len(Pair.mismatch({ first: 1 })), 1)

@test
an_object_shape_is_still_at_least_its_fields_when_the_program_runs() =
    // **The excess-property check is the CHECKER's and the machine keeps none of it**, which is why
    // every program here runs. An object pattern matches on the fields it names and ignores the
    // rest, and that is what a value reaching a shape through a name relies on -- so a refusal of a
    // literal is a claim about where the literal was WRITTEN, never about what the value is.
    val big = { x: 2, y: 3, z: 4 }

    assertEq(area(big), 6)
    assert(big is Spot)

    // A literal built by a spread is a merge rather than a literal, so it carries the other
    // object's spare field here and is not refused for it.
    val some = { x: 2, z: 9 }

    assertEq(area({ ...some, y: 3 }), 6)
    assertEq(area({ y: 3, ...some }), 6)

    // And a literal nested inside one is the outer field's business, not the annotation's.
    assertEq(inner({ inner: { a: 1, b: 2 } }), 1)

area(p: Spot) = p.x * p.y

inner(o: Wrapper) = o.inner.a
