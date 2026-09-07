// What a contract and a range type do when the program RUNS, on whichever back end is running it.
//
// The checker's side of both -- what it refuses before the program starts -- is in sysl, in
// `tests_types.sysl`. What is here is the half a running program can see: a clause that faults, the
// sentence it faults with, and a range asked about a value nobody wrote down.

type Port = 1..65535

anything(v) = v

withdraw(balance, amount)
    require amount > 0
    require amount <= balance
    ensure result >= 0
    balance - amount

clamp(n)
    ensure result >= 0
    if n < 0
        return n
    n

answers(n) -> string
    if n > 0
        return 42
    "ok"

listenOn(p: Port) = "port " + string(p)

pct(x: 0..100) = x

fraction(x: 0.0..1.0) = x

@test
a_contract_that_holds_costs_a_program_nothing_it_can_see() =
    assertEq(withdraw(100, 30), 70)
    assertEq(clamp(5), 5)

@test
a_precondition_names_the_function_and_the_clause_that_refused() =
    val said = (withdraw(100, -1)) catch e -> e.message

    assertEq(said, "`withdraw` requires `amount > 0`, and this call does not meet it")

    val second = (withdraw(10, 30)) catch e -> e.message

    assertEq(second, "`withdraw` requires `amount <= balance`, and this call does not meet it")

@test
a_postcondition_names_what_the_function_answered() =
    // The value is in the sentence, which is what `-> type` already does and is most of what a
    // reader wants: the clause is written above and the number is not.
    val said = (clamp(-5)) catch e -> e.message

    assertEq(said, "`clamp` ensures `result >= 0`, and gave back -5")

@test
a_postcondition_is_checked_at_a_return_and_where_the_body_falls_out() =
    // `clamp` answers through a `return` and `withdraw` by falling out, so the two ways out are both
    // covered by the tests above -- what is asserted here is that the clause did not fire on the way
    // that holds.
    assertEq(clamp(0), 0)
    assertEq(withdraw(1, 1), 0)

@test
a_return_answers_so_it_meets_the_result_annotation_too() =
    assertEq(answers(0), "ok")

    val said = (answers(1)) catch e -> e.message

    assertEq(said, "this answers string, and gave back 42")

@test
a_range_annotation_is_checked_where_the_value_arrives() =
    assertEq(listenOn(8080), "port 8080")
    assertEq(pct(0), 0)
    assertEq(pct(100), 100)

    val said = (listenOn(anything(70000))) catch e -> e.message

    assertEq(said, "`p` was declared Port, and was given 70000")

@test
a_range_with_whole_ends_takes_whole_numbers_only() =
    assert(pct(anything(50)) == 50)
    assert(fraction(0.25) == 0.25)
    assert(fraction(1) == 1)

    val said = (pct(anything(2.5))) catch e -> e.message

    assertEq(said, "`x` was declared 0..100, and was given 2.5")

@test
a_range_tests_and_matches_like_any_other_pattern() =
    assert(9 is 0..<10)
    assert(!(10 is 0..<10))
    assert(10 is 0..10)
    assert(-4 is ..0)
    assert(4 is 3..)
    assert(!(2 is 3..))
    assert(!("8" is 0..100))

    grade(n) = n match
        0..59 -> "F"
        60..<70 -> "D"
        _ -> "A"

    assertEq(grade(12), "F")
    assertEq(grade(65), "D")
    assertEq(grade(95), "A")

@test
a_named_range_answers_the_three_questions_a_type_answers() =
    assertEq(Port.name(), "Port")
    assert(Port.test(80))
    assert(!Port.test(0))
    assertEq(Port.mismatch(0).length, 1)

@test
both_contract_words_are_still_ordinary_names() =
    val require = (path) -> "loaded " + path

    assertEq(require("./x"), "loaded ./x")

    val ensure = 3

    assertEq(ensure + 1, 4)
