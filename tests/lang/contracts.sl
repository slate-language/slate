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

// `old(e)` -- what `e` was on ENTRY, kept for the postcondition. What is worth running on both back
// ends is that the snapshot is taken in the right place and that it is a VALUE: the interpreter
// hoists it into a slot and node writes it into a `let`, and the two have to agree about both.

class Tally
    var count

    bump(self)
        ensure self.count == old(self.count) + 1
        self.count += 1
        self.count

increment(n)
    ensure result == old(n) + 1
    n + 1

spans(lo, hi)
    ensure result == old(hi) - old(lo)
    hi - lo

grew(items)
    ensure items.length == old(items.length) + 1
    ensure old(items).length == items.length
    push(items, 9)
    items

countDown(n, seen)
    require n >= 0
    ensure result == old(n)
    push(seen, n)
    if n == 0
        return 0
    countDown(n - 1, seen)
    n

old(v) = "kept " + v

@test
old_is_the_value_a_function_was_given_and_not_the_one_it_leaves() =
    assertEq(increment(4), 5)
    assertEq(increment(-1), 0)

@test
old_reads_the_object_a_mutating_method_was_called_on() =
    val t = Tally.new(0)

    assertEq(t.bump(), 1)
    assertEq(t.bump(), 2)
    assertEq(t.count, 2)

@test
old_keeps_a_value_and_not_a_place_so_the_expression_says_which() =
    // `old(items.length)` is the length on entry; `old(items)` is the array itself, which the body
    // is changing under the snapshot -- so a length read off it afterwards is the length it has now.
    val xs = [1, 2]

    assertEq(grew(xs), [1, 2, 9])
    assertEq(xs.length, 3)

@test
two_olds_in_one_clause_are_two_independent_snapshots() =
    assertEq(spans(2, 9), 7)

@test
a_postcondition_that_fails_quotes_the_clause_with_its_old_as_written() =
    broken(n)
        ensure result == old(n) + 1
        n + 2

    val said = (broken(1)) catch e -> e.message

    assertEq(said, "`broken` ensures `result == old(n) + 1`, and gave back 3")

@test
every_call_takes_its_own_snapshots_so_recursion_means_what_it_looks_like() =
    val seen = []

    assertEq(countDown(3, seen), 3)
    assertEq(seen, [3, 2, 1, 0])

@test
a_snapshot_that_faults_faults_on_the_way_in_and_not_on_the_way_out() =
    // The snapshot is taken where the body begins, so a fault in one is reported before a single
    // statement of the body has run -- which is what `told` proves.
    val told = []

    tracked(xs)
        ensure result == old(xs.at(9))
        push(told, "ran")
        0

    val said = (tracked([1, 2, 3])) catch e -> e.message

    assert(said.contains("this array has 3 of them"))
    assertEq(told, [])

@test
a_program_that_names_its_own_old_keeps_working() =
    assertEq(old("it"), "kept it")

    val shadow = (v) -> old(v) + "!"

    assertEq(shadow("that"), "kept that!")

@test
a_postcondition_shows_the_answer_and_not_whatever_local_was_declared_last() =
    // The sentence names what the function gave back, on both ways out. The fall-out path reads it
    // by name: a run of statements has discarded the answer by the time the clause runs, so a
    // reading off the top of the stack finds the last local the body declared instead.
    keeps(n)
        ensure result == 99
        val other = 777
        n + other

    val said = (keeps(1)) catch e -> e.message

    assertEq(said, "`keeps` ensures `result == 99`, and gave back 778")
