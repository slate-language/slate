// Bytes: the buffer kind, its operations, its two encodings, and the shapes that still take an
// array of numbers where one was written before there was a kind at all.

import { monotonic, millis } from slate:time

@test
a_buffer_is_made_from_a_count_an_array_or_another_buffer() =
    assertEq(bytes(3).length, 3)
    assertEq(bytes(3).toArray(), [0, 0, 0])
    assertEq(bytes([1, 2, 255]).toArray(), [1, 2, 255])
    assertEq(bytes(bytes([7])).toArray(), [7])
    assertEq(bytes(0).length, 0)

@test
a_copy_is_a_different_buffer_and_the_original_does_not_see_its_writes() =
    val a = bytes([1, 2])
    val b = bytes(a)

    push(b, 3)

    assertEq(a.length, 2)
    assertEq(b.length, 3)

@test
two_names_for_one_buffer_see_each_others_writes() =
    val a = bytes([1, 2])
    val b = a

    push(b, 3)

    assertEq(a.toArray(), [1, 2, 3])
    assert(a.eq(b))

@test
toBytes_answers_a_buffer_of_the_utf8_bytes() =
    assertEq(toBytes("héllo").length, 6)
    assertEq(toBytes("héllo").toArray(), [104, 195, 169, 108, 108, 111])
    assertEq(toBytes("hi", "utf8").toArray(), [104, 105])
    assert(toBytes("hi") is bytes)

@test
latin1_is_one_byte_per_character_by_code() =
    assertEq(toBytes("ÿ", "latin1").toArray(), [255])
    assertEq(toBytes("ÿ").length, 2)
    assertEq(toBytes("", "latin1").length, 0)

@test
a_character_past_255_has_no_latin1_byte_and_the_fault_names_it() =
    val said = toBytes("Ā", "latin1") catch e -> e.message

    assert(contains(said, "character 256"))
    assert(contains(said, "has no byte"))

@test
a_third_encoding_is_refused_by_name() =
    val out = toBytes("a", "utf16") catch e -> e.message
    val back = fromBytes(bytes(1), "utf16") catch e -> e.message

    assert(contains(out, "`utf8` and `latin1`"))
    assert(contains(back, "`utf8` and `latin1`"))

@test
fromBytes_reads_a_buffer_or_an_array_and_answers_a_result() =
    assertEq(fromBytes(toBytes("héllo")).value, "héllo")
    assertEq(fromBytes([104, 105]).value, "hi")
    assertEq(fromBytes(bytes([0xff])).ok, false)
    assert(contains(fromBytes(bytes([0xff])).error, "not valid UTF-8"))

@test
latin1_always_decodes_where_utf8_may_refuse() =
    assertEq(fromBytes(bytes([0xff]), "latin1").ok, true)
    assertEq(fromBytes(bytes([0xff]), "latin1").value, "ÿ")
    assertEq(fromBytes([0, 255], "latin1").value.length, 2)

@test
length_is_bytes_and_an_index_reads_an_integer() =
    val b = toBytes("héllo")

    assertEq(b.length, 6)
    assertEq(b[0], 104)
    assertEq(b[1], 195)
    assert(b[0] is integer)

@test
an_index_outside_the_buffer_faults_both_ways() =
    val b = bytes(2)

    assert(contains(b[2] catch e -> e.message, "outside 2 bytes"))
    assert(contains(b[-1] catch e -> e.message, "outside 2 bytes"))
    assert(contains(putByte(b, 2, 0) catch e -> e.message, "outside 2 bytes"))

// A write is a statement, so a test about one that faults needs somewhere to put it.
putByte(b, i, v)
    b[i] = v

@test
a_write_stores_a_byte_and_anything_outside_the_range_faults() =
    val b = bytes(2)

    b[0] = 255
    b[1] = 0

    assertEq(b.toArray(), [255, 0])
    assert(contains(putByte(b, 0, 256) catch e -> e.message, "a byte is between 0 and 255"))
    assert(contains(putByte(b, 0, -1) catch e -> e.message, "a byte is between 0 and 255"))
    assert(contains(putByte(b, 0, "x") catch e -> e.message, "a byte is a whole number"))
    assertEq(b.toArray(), [255, 0])

@test
a_range_subscript_and_slice_both_answer_a_new_buffer() =
    val b = toBytes("abcdef")

    assertEq(b[1..<3].toArray(), [98, 99])
    assertEq(slice(b, 2).toArray(), [99, 100, 101, 102])
    assertEq(slice(b, 1, 3).toArray(), [98, 99])
    assertEq(slice(b, 0, 100).length, 6)
    assertEq(slice(b, 4, 2).length, 0)
    assertEq(slice(b, -2).toArray(), [101, 102])
    assert(b[0..<2] is bytes)

@test
a_slice_is_a_copy_so_writing_through_it_leaves_the_source_alone() =
    val b = toBytes("abc")
    val piece = slice(b, 0, 2)

    piece[0] = 122

    assertEq(b[0], 97)

@test
a_slice_of_bytes_does_not_step() =
    val said = toBytes("abcd")[0..<4 by 2] catch e -> e.message

    assert(contains(said, "does not step"))

@test
concat_joins_buffers_and_takes_an_array_of_numbers_beside_one() =
    assertEq(concat(toBytes("ab"), toBytes("c")).toArray(), [97, 98, 99])
    assertEq(concat(toBytes("ab"), [99]).toArray(), [97, 98, 99])
    assertEq(concat(bytes(0)).length, 0)
    assertEq(toBytes("a").concat(toBytes("b"), toBytes("c")).length, 3)
    assert(concat(toBytes("ab"), toBytes("c")) is bytes)

@test
concat_answers_a_new_buffer_and_changes_neither_side() =
    val a = toBytes("ab")
    val joined = concat(a, toBytes("c"))

    push(joined, 100)

    assertEq(a.length, 2)
    assertEq(joined.length, 4)

@test
push_takes_a_byte_or_a_whole_buffer() =
    val b = bytes(0)

    push(b, 104)
    push(b, toBytes("ello"))

    assertEq(fromBytes(b).value, "hello")
    assertEq(b.length, 5)

@test
push_of_a_buffer_onto_itself_appends_what_was_there() =
    val b = toBytes("ab")

    push(b, b)

    assertEq(fromBytes(b).value, "abab")

@test
push_refuses_a_byte_outside_the_range_and_a_value_that_is_not_one() =
    val b = bytes(0)

    assert(contains(push(b, 256) catch e -> e.message, "a byte is between 0 and 255"))
    assert(contains(push(b, anything("x")) catch e -> e.message, "a byte or more bytes"))
    assertEq(b.length, 0)

// **A NAME STATICALLY KNOWN TO BE `bytes` USED TO REFUSE `push` AT COMPILE TIME**, which stopped
// this program before either back end got to run it -- so a checker defect here is a differential
// test by construction, both hosts failing alike until `signatures.sysl`'s `push` accepted `bytes`.
@test
push_TAKES_A_PARAMETER_ANNOTATED_bytes() =
    putBytes(out: bytes, s) = push(out, toBytes(s, "latin1"))
    val out = bytes(0)

    putBytes(out, "hi")

    assertEq(fromBytes(out).value, "hi")

@test
indexOf_finds_a_byte_or_a_run_and_answers_null_for_a_miss() =
    val head = toBytes("GET / HTTP/1.1\r\n\r\n")

    assertEq(indexOf(head, toBytes("\r\n\r\n")), 14)
    assertEq(indexOf(head, 47), 4)
    assertEq(indexOf(head, 255), null)
    assertEq(indexOf(head, toBytes("nope")), null)
    assertEq(indexOf(head, bytes(0)), 0)
    assertEq(indexOf(bytes(0), toBytes("a")), null)

@test
contains_is_indexOf_asked_as_a_question() =
    val b = toBytes("abc")

    assertEq(contains(b, 98), true)
    assertEq(contains(b, 122), false)
    assertEq(contains(b, toBytes("bc")), true)
    assertEq(b.includes(toBytes("ac")), false)

@test
at_counts_a_negative_position_back_from_the_end() =
    val b = toBytes("abc")

    assertEq(b.at(0), 97)
    assertEq(b.at(-1), 99)
    assert(contains(b.at(3) catch e -> e.message, "these bytes have 3 of them"))

@test
clear_empties_a_buffer_in_place() =
    val b = toBytes("abc")

    clear(b)

    assertEq(b.length, 0)
    assertEq(b.toArray(), [])

@test
a_for_walks_the_bytes_as_integers() =
    var total = 0

    for b in toBytes("abc")
        total = total + b

    assertEq(total, 294)

@test
equality_is_by_contents_and_a_buffer_is_not_the_array_of_its_numbers() =
    assertEq(toBytes("abc") == toBytes("abc"), true)
    assertEq(toBytes("abc") == toBytes("abd"), false)
    assertEq(toBytes("ab") == toBytes("abc"), false)
    assertEq(toBytes("abc") == anything([97, 98, 99]), false)
    assertEq(bytes(0) == bytes(0), true)

@test
eq_asks_whether_two_names_hold_the_same_buffer() =
    val a = toBytes("abc")

    assertEq(a.eq(a), true)
    assertEq(a.eq(toBytes("abc")), false)
    assertEq(a.equals(toBytes("abc")), true)

@test
a_buffer_prints_as_its_count_and_then_its_bytes_in_hex() =
    assertEq(string(toBytes("héllo")), "<bytes 6: 68 c3 a9 6c 6c 6f>")
    assertEq(string(bytes(0)), "<bytes 0>")
    assertEq(string(bytes(17)),
        "<bytes 17: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ...>")
    assertEq(string([toBytes("a")]), "[<bytes 1: 61>]")

@test
json_encodes_a_buffer_as_the_array_of_its_numbers() =
    assertEq(toJSON(bytes([1, 2, 255])), "[1,2,255]")
    assertEq(toJSON(bytes(0)), "[]")
    assertEq(toJSON({ b: toBytes("hi") }), "{\"b\":[104,105]}")

@test
bytes_is_a_type_word_that_tests_and_annotates() =
    assertEq(toBytes("hi") is bytes, true)
    assertEq(anything([1, 2]) is bytes, false)
    assertEq(anything("hi") is bytes, false)
    assertEq(counting(toBytes("hi")), 2)

counting(b: bytes) = b.length

@test
a_buffer_is_truthy_even_when_it_is_empty() =
    assertEq(if bytes(0) then "true" else "false", "true")

@test
the_constructor_refuses_a_negative_count_and_a_value_that_is_neither() =
    assert(contains(bytes(-1) catch e -> e.message, "a count that is not negative"))
    assert(contains(bytes(anything("hi")) catch e -> e.message,
        "a count, an array of numbers or bytes"))
    assert(contains(bytes([256]) catch e -> e.message, "a byte is between 0 and 255"))

@test
a_name_a_buffer_does_not_carry_says_so() =
    val mapped = anything(toBytes("a")).map(x -> x) catch e -> e.message
    val sized = anything(toBytes("a")).size catch e -> e.message

    assert(contains(mapped, "bytes"))
    assert(contains(sized, "bytes"))

@test
a_megabyte_is_built_by_doubling_rather_than_a_byte_at_a_time() =
    val started = millis(monotonic())
    var out = bytes(0)
    val block = bytes(1024)

    for i in 0..<1024
        push(out, block)

    assertEq(out.length, 1048576)
    assert(millis(monotonic()) - started < 2000)

@test
concat_of_a_megabyte_is_a_copy_of_a_run_of_memory() =
    val half = bytes(524288)
    val started = millis(monotonic())

    assertEq(concat(half, half).length, 1048576)
    assert(millis(monotonic()) - started < 2000)

// The shape mimic's RESP encoder is: a long string turned into latin1 bytes and appended to a
// buffer, over and over. It was 0.7 microseconds a byte as an array of numbers.
@test
the_encoder_shape_is_four_million_bytes_in_well_under_a_second() =
    val piece = toBytes(repeat("x", 20000), "latin1")
    val started = millis(monotonic())
    var out = bytes(0)

    for i in 0..<200
        push(out, piece)

    assertEq(out.length, 4000000)
    assert(millis(monotonic()) - started < 2000)

anything(v) = v
