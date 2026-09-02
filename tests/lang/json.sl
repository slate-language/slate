// JSON, which is two conversions and no design, slate's value model already being JSON's.

@test
a_value_round_trips_through_json() =
    val v = { a: 1, b: [true, null, "x"], c: { d: 1.5 } }

    assertEq(parseJSON(toJSON(v)).value, v)

@test
the_two_kinds_of_number_survive_the_round_trip_because_the_TEXT_says_which() =
    assertEq(toJSON(1), "1")
    assertEq(toJSON(1.0), "1.0")
    assert(parseJSON("1").value is integer)
    assert(parseJSON("1.0").value is real)
    assert(parseJSON("1e2").value is real)

    // The rendering is the shortest text that reads back as the same number, and it gets a `.0`
    // where neither a point nor an exponent was written -- `1` is an integer to a JSON reader.
    assertEq(toJSON(0.0), "0.0")
    assertEq(toJSON(-0.0), "-0.0")
    assertEq(toJSON(100.0), "100.0")
    assertEq(toJSON(0.0001), "0.0001")
    assertEq(toJSON(1e-5), "1e-05")
    assertEq(toJSON(1e15), "1e+15")
    assertEq(toJSON(0.1 + 0.2), "0.30000000000000004")

    // A NaN or an infinity is `null`: JSON's grammar has no spelling for either.
    assertEq(toJSON(1.0 / 0.0), "null")

@test
an_indent_is_the_second_argument_rather_than_a_second_name() =
    assertEq(toJSON({ a: 1 }), "{\"a\":1}")
    assertEq(toJSON({ a: 1 }, 2), "{\n  \"a\": 1\n}")

@test
a_document_that_will_not_parse_is_a_RESULT() =
    val r = parseJSON("{\"a\": 1,}")

    assert(!r.ok)
    assert(r.error is string)
    assert(len(r.error) > 0)

@test
a_value_with_no_json_form_is_a_FAULT_and_is_named_rather_than_dropped() =
    // Text from a file, a socket or a person is a condition every caller was going to handle; a
    // function in a value the program built itself is a defect in that program.
    val said = toJSON({ f: (x) -> x }) catch e -> e.message

    assert(len(said) > 0)

@test
the_seven_things_json_has_are_the_seven_slate_has() =
    assertEq(parseJSON("null").value, null)
    assertEq(parseJSON("true").value, true)
    assertEq(parseJSON("[1,2]").value, [1, 2])
    assertEq(parseJSON("\"a\\nb\"").value, "a\nb")
    assertEq(parseJSON("{\"a\":{\"b\":[]}}").value, { a: { b: [] } })

@test
a_string_is_escaped_on_the_way_out_and_read_back_on_the_way_in() =
    val awkward = "a\"b\\c\nd\te"

    assertEq(parseJSON(toJSON(awkward)).value, awkward)

@test
text_outside_the_document_is_refused() =
    assert(!parseJSON("1 2").ok)
    assert(!parseJSON("").ok)
    assert(!parseJSON("tru").ok)
