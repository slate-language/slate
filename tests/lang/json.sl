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

// -- what a nominal value encodes as ---------------------------------------------------------------

// The declarations these tests encode. **At the top level because a class's name is a type as well
// as a value**, and one written inside a block would not be there for `is` to resolve against.

class Point
    var x
    var y

class Money
    var cents

    toJSON(self) = "$" + string(self.cents)

class Pair
    var a
    var b

    toJSON(self) = { first: self.a, second: self.b }

class Loop
    var n

    toJSON(self) = self

data Shape
    Circle(r)
    Rect(w, h)
    Empty

@test
a_class_instance_encodes_its_OWN_fields_and_not_the_chain_it_hangs_from() =
    // Every class instance and every data variant used to be unencodable: the walk reported `proto`
    // as a field, followed it to the class object, and complained about the constructor it found
    // there -- *"there is no JSON for a function"*, pointing at a function nobody wrote.
    assertEq(toJSON(Point.new(1, 2)), "{\"x\":1,\"y\":2}")
    assertEq(parseJSON(toJSON(Point.new(1, 2))).value, { x: 1, y: 2 })

@test
a_data_variant_encodes_the_fields_it_carries() =
    assertEq(toJSON(Circle(3)), "{\"r\":3}")
    assertEq(toJSON(Rect(2, 4)), "{\"w\":2,\"h\":4}")

    // One that declares no fields carries none, so it encodes as the empty document.
    assertEq(toJSON(Empty), "{}")

@test
a_nominal_value_encodes_the_same_way_at_every_depth() =
    assertEq(toJSON({ shapes: [Circle(1), Circle(2)] }), "{\"shapes\":[{\"r\":1},{\"r\":2}]}")

@test
a_class_writes_toJSON_to_say_what_it_encodes_as() =
    // The hook replaces everything below it, at every depth -- which is `toString`'s rule and node's
    // own. A value that IS a value reaches a response body as itself rather than as its fields.
    assertEq(toJSON(Money.new(150)), "\"$150\"")
    assertEq(toJSON({ paid: Money.new(150) }), "{\"paid\":\"$150\"}")
    assertEq(toJSON([Money.new(1), Money.new(2)]), "[\"$1\",\"$2\"]")

@test
a_toJSON_hook_may_answer_an_object_and_it_is_encoded_in_turn() =
    assertEq(toJSON(Pair.new(1, Pair.new(2, 3))), "{\"first\":1,\"second\":{\"first\":2,\"second\":3}}")

@test
a_toJSON_that_answers_the_value_back_is_a_FAULT_rather_than_a_hang() =
    val said = toJSON(Loop.new(1)) catch e -> e.message

    assert(said.contains("gave the value back"))

@test
a_CLASS_has_no_json_form_and_the_complaint_names_it() =
    // The class object's members are a constructor and a table of methods, so it has no more of a
    // JSON form than a function does. The complaint used to name the function it stumbled on.
    val said = toJSON(Point) catch e -> e.message

    assert(said.contains("Point"))
    assert(said.contains("class"))

@test
a_json_name_is_a_string_and_a_slate_key_is_any_value() =
    val t = {}

    t[1] = "a"

    // Rendering the key as text would make `{ 1: "a" }` and `{ "1": "a" }` the same document, which
    // they are not. The JavaScript back end used to write the first as the second.
    val said = toJSON(t) catch e -> e.message

    assert(said.contains("a JSON name is a string"))

    val u = {}

    u[{ v: 1 }] = "a"

    assert((toJSON(u) catch e -> e.message).contains("a JSON name is a string"))

@test
a_value_that_holds_itself_is_a_FAULT_on_both_back_ends() =
    val o = { a: 1 }

    o.self = o

    assert((toJSON(o) catch e -> e.message).contains("holds itself"))

    val xs = [1]

    xs[0] = xs

    // The JavaScript back end had no cycle guard at all and descended until node ran out of stack,
    // which arrives as a `RangeError` naming a line of the runtime rather than anything slate said.
    assert((toJSON(xs) catch e -> e.message).contains("holds itself"))

@test
the_two_back_ends_say_the_same_sentence_about_a_value_with_no_json() =
    val said = toJSON({ f: (x) -> x }) catch e -> e.message

    assert(said.contains("there is no JSON for"))
