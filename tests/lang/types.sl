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

// A range with a step is a type the same way a range without one is: the numbers it covers.
type Even = 0..<10 by 2

// A generic type may stand for ANY type expression and not only for an object, so these are the four
// other shapes a substitution has to reach into.
type Twin[T] = [T, T]
type Coord = [string, integer]
type Opened = [string, ...]
type Answer[T] = { ok: true, value: T } | { ok: false, error: string }
type Bag[T] = array of T
type Wrap[T] = (T) -> T

// The `?` mark belongs to the shape rather than to the declaration, so it reads the same written
// straight into an annotation -- `takes_an_optional_field_written_in_the_annotation` does that.
type Aged = { name: string, age?: integer }

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
    keep(xs: array of (string | null)) = xs.length
    run(f: MaybeFn) = if f is null then 0 else f(2)
    show(p: Pair[string, integer]) = s"${p.first}=${p.second}"

    assertEq(apply(n -> n + 1), 2)
    assert(check((s, n) -> s.length == n))
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
    gathers(...rest) = rest.length

    assertEq(apply(anything(gathers)), 1)

@test
a_lambdas_parameter_may_be_annotated_and_is_checked_when_it_is_called() =
    val g = (n: integer) -> n + 1

    assertEq(g(2), 3)

    val said = (g(anything("x"))) catch e -> e.message

    assert(said.contains("was declared integer"))

@test
a_rest_parameter_is_annotated_as_the_array_it_gathers_into() =
    count(...rest: array of integer) = rest.length

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
    assertEq(Pair.mismatch({ first: 1 }).length, 1)

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

@test
A_RANGE_TYPE_HONOURS_ITS_STEP() =
    // `1..65535` says what a port is; `0..<10 by 2` says what an even digit is, and it is the same
    // range the expression grammar writes.
    assert(4 is Even)
    assert(!(5 is Even))
    assert(0 is Even)
    assert(!(10 is Even))

@test
a_generic_type_stands_for_any_shape_and_not_only_for_an_object() =
    // The substitution walks the whole type, so what is generic over may sit in an array, in an
    // alternative of a union, under `array of`, or at a function type's parameter. What comes out at
    // a use is the ordinary pattern for that shape, which is what is tested here.
    assert([1, 2] is Twin[integer])
    assert(!(["a", "b"] is Twin[integer]))
    assert(!([1] is Twin[integer]))

    // The count is part of the shape, so a THIRD element misses the same way a wrong one does --
    // which is what makes `Twin` read as a pair rather than as a floor of two.
    assert(!([1, 2, 3] is Twin[integer]))

    assert({ ok: true, value: "x" } is Answer[string])
    assert(!({ ok: true, value: 1 } is Answer[string]))
    assert({ ok: false, error: "e" } is Answer[string])

    assert([1, 2, 3] is Bag[integer])
    assert(!([1, "a"] is Bag[integer]))

    // A function type asks what it can ask, which is callable and the count -- so the `T` in it is
    // substituted and then says nothing further, exactly as a written one does.
    assert((n -> n) is Wrap[integer])
    assert(!(3 is Wrap[integer]))

@test
a_generic_type_reads_as_a_match_arm_with_the_types_it_was_given() =
    // A `match` arm is pattern position, and type ARGUMENTS are read there as well as in a type
    // position -- so the arm that runs is the shape the substitution produced.
    sort(v) = v match
        Twin[integer] -> "two integers"
        Twin[string]  -> "two strings"
        _             -> "something else"

    assertEq(sort([1, 2]), "two integers")
    assertEq(sort(["a", "b"]), "two strings")
    assertEq(sort([1, "a"]), "something else")

    read(r: Answer[string]) = r match
        { ok: true, value }  -> value
        { ok: false, error } -> "!" + error

    assertEq(read({ ok: true, value: "hi" }), "hi")
    assertEq(read({ ok: false, error: "no" }), "!no")

@test
a_generic_function_type_is_the_written_one_after_the_substitution() =
    // `(T) -> T` in a definition's own head, and the same thing given a name of its own.
    applyTo[T](f: (T) -> T, x: T) -> T = f(x)

    assertEq(applyTo(n -> n + 1, 41), 42)
    assertEq(applyTo(s -> upper(s), "hi"), "HI")

    val twice: Wrap[integer] = n -> n * 2

    assertEq(twice(21), 42)

    // And the machine still asks the one question it can: a value that is not callable at all does
    // not fit, wherever the type came from.
    val said = (declaredWrap(anything("no"))) catch e -> e.message

    assert(said.contains("was declared Wrap[integer]"))

declaredWrap(v) =
    val f: Wrap[integer] = v

    f

@test
takes_an_optional_field_written_in_the_annotation() =
    // The `?` is the shape's, so it reads the same inline as it does through a `type`: absent, the
    // shape still holds; present, it is checked.
    greet(person: { name: string, age?: integer }) =
        if has(person, "age") then s"${person.name} (${person.age})" else person.name

    assertEq(greet({ name: "ada" }), "ada")
    assertEq(greet({ name: "grace", age: 36 }), "grace (36)")

    // Through a declared name the run-time check says the same, and names the annotation as written.
    assertEq(greet(anything({ name: "ada" })), "ada")

    val said = (aged(anything({ name: "ada", age: "old" }))) catch e -> e.message

    assert(said.contains("was declared { name: string, age?: integer }"))

    // `mismatch` treats the two halves the same way the test does: a missing optional is no reason,
    // a present one that does not fit is.
    assert(Aged.test({ name: "a" }))
    assert(!Aged.test({ name: "a", age: "x" }))
    assertEq(Aged.mismatch({ name: "a" }).length, 0)
    assertEq(Aged.mismatch({ name: "a", age: "x" }).length, 1)
    assertEq(Aged.mismatch({ name: "a", age: "x" })[0].path, "age")

aged(p: { name: string, age?: integer }) = p.name

@test
a_bracketed_annotation_is_exactly_as_long_as_it_says() =
    // A bracketed shape says HOW MANY, so a surplus element misses the same way a wrong one does.
    // The value goes through `anything` so the check under test is the machine's, at the spot the
    // value arrives.
    assertEq(coord(anything(["a", 2])), ["a", 2])

    val tooLong = (coord(anything(["a", 2, 3]))) catch e -> e.message

    assert(tooLong.contains("was declared [string, integer]"))
    assert(tooLong.contains("[\"a\", 2, 3]"))

    val tooShort = (coord(anything(["a"]))) catch e -> e.message

    assert(tooShort.contains("was declared [string, integer]"))

    // A `...` is what opens it, and the elements written before one are still checked.
    assertEq(opened(anything(["a", 2, 3, 4])), ["a", 2, 3, 4])
    assertEq(opened(anything(["a"])), ["a"])

    val notEvenOne = (opened(anything([]))) catch e -> e.message

    assert(notEvenOne.contains("was declared [string, ...]"))

@test
a_bracketed_shape_counts_the_same_in_every_position() =
    // An annotation, an `is` test, a `match` arm, a destructuring binding and a `for` head are one
    // grammar read in two positions, so none of them may disagree about the length.
    assert(["a", 2] is Coord)
    assert(!(["a", 2, 3] is Coord))

    // A name a `type` declared carries the count with it, and a bracketed shape written at the spot
    // says the same thing -- the declaration is the very pattern the brackets are.
    assert(["a", 2] is [string, integer])
    assert(!(["a", 2, 3] is [string, integer]))

    named(v) = v match
        Coord -> "a coord"
        _     -> "not a coord"

    assertEq(named(["a", 2]), "a coord")
    assertEq(named(["a", 2, 3]), "not a coord")

    bare(v) = v match
        [string, integer] -> "a pair"
        _                 -> "not a pair"

    assertEq(bare(["a", 2]), "a pair")
    assertEq(bare(["a", 2, 3]), "not a pair")

    // A binding has no next arm to try, so a surplus element is a FAULT rather than a miss. What
    // each back end says about it is its own sentence, so what is asserted here is that both
    // refuse; the interpreter's wording is pinned in `tests_pattern.sysl`.
    val [first, second] = ["a", 2]

    assertEq(first, "a")
    assertEq(second, 2)

    assertEq(unpackedTwo(anything(["a", 2])), ["a", 2])
    assertEq((unpackedTwo(anything(["a", 2, 3]))) catch e -> "refused", "refused")

    // A `for` head is a binding once per row, and counts the same way.
    assertEq(overRows(anything([["a", 1], ["b", 2]])), 2)
    assertEq((overRows(anything([["a", 1, 9]]))) catch e -> "refused", "refused")

    // And a rest opens every one of them alike.
    val [head, ...rest] = ["a", 2, 3]

    assertEq(head, "a")
    assertEq(rest, [2, 3])

@test
mismatch_on_a_bracketed_type_reports_the_LENGTH_and_not_the_elements() =
    // The length is reported OR the elements are, never both: an array of the wrong length has
    // nothing useful to say about element three.
    assert(Coord.test(["a", 2]))
    assert(!Coord.test(["a", 2, 3]))

    assertEq(Coord.mismatch(["a", 2]).length, 0)
    assertEq(Coord.mismatch(["a", 2, 3]).length, 1)
    assertEq(Coord.mismatch(["a", 2, 3])[0].wanted, "[string, integer]")
    assertEq(Coord.mismatch(["a", 2, 3])[0].got, "an array of 3")

    // A RIGHT-length array that does not fit is reported per element, which is the other half of
    // that rule.
    assertEq(Coord.mismatch(["a", "b"]).length, 1)
    assertEq(Coord.mismatch(["a", "b"])[0].path, "1")

    // An open shape counts the elements it writes as a floor, so a longer array is no reason at all.
    assertEq(Opened.mismatch(["a", 2, 3]).length, 0)
    assertEq(Opened.mismatch([]).length, 1)

coord(p: [string, integer]) = p
opened(p: [string, ...]) = p

unpackedTwo(xs) =
    val [a, b] = xs

    [a, b]

overRows(rows) =
    var n = 0

    for [k, v] in rows
        n = n + 1

    n
