// A point on the timeline, and an exact length of one.
//
// **Only the half both back ends have.** `date`, `time`, `dateTime`, `zone`, `zoned` and `period`
// need `Intl` and are not in the JavaScript back end yet, so a test naming one would fail there for
// a reason that is not about the language. The calendar's own tests are in `tests_time.sysl`, which
// drives the interpreter; what is here is what a program can rely on wherever it runs.

import { epochSeconds, epochMillis, epochMicros, instant, now, monotonic, micros, millis, seconds,
    minutes, hours } from slate:time

@test
an_instant_is_a_point_and_a_duration_is_a_length() =
    assert(epochSeconds(0) is instant)
    assert(seconds(1) is duration)
    assert(!(epochSeconds(0) is duration))
    assert(!(seconds(1) is instant))

@test
the_epoch_words_make_an_instant_and_read_one_back() =
    val t = epochMillis(1756900000000)

    assertEq(epochSeconds(t), 1756900000)
    assertEq(epochMillis(t), 1756900000000)
    assertEq(epochMicros(t), 1756900000000000)
    assertEq(epochSeconds(1756900000), t)
    assertEq(instant(t), t)

@test
an_instant_keeps_its_microseconds() =
    // **The clock is milliseconds and the value is not**, which is the distinction to keep: a
    // program that read a timestamp out of a database gets every digit back.
    assertEq(epochMicros(epochMicros(1000000001)), 1000000001)
    assertEq(string(epochMicros(1000000001)), "1970-01-01T00:16:40.000001Z")

@test
the_clock_reads_whole_milliseconds_on_every_back_end() =
    // **Not a statement about precision but about agreement.** JavaScript's `Date.now()` has nothing
    // finer, so slate's clock has nothing finer either -- rather than a timestamp that prints six
    // fractional digits under one back end and three under the other.
    assertEq(epochMicros(now()) % 1000, 0)

@test
an_exact_length_is_made_and_read_back_in_whole_units() =
    val d = hours(1) + minutes(30)

    assertEq(hours(d), 1)
    assertEq(minutes(d), 90)
    assertEq(seconds(d), 5400)
    assertEq(millis(d), 5400000)
    assertEq(micros(d), 5400000000)

@test
a_duration_moves_an_instant_and_two_instants_make_a_duration() =
    val t = epochSeconds(1000)

    assertEq(t + seconds(90), epochSeconds(1090))
    assertEq(t - seconds(90), epochSeconds(910))
    assertEq(seconds(90) + t, epochSeconds(1090))
    assertEq((t + hours(2)) - t, hours(2))
    assertEq(t - t, seconds(0))

@test
a_duration_scales_by_a_whole_number() =
    assertEq(minutes(30) * 2, hours(1))
    assertEq(2 * minutes(30), hours(1))
    assertEq(hours(1) / 4, minutes(15))

@test
monotonic_only_goes_forward() =
    // The wall clock can be set backwards, which is why an elapsed time is measured with this one.
    val began = monotonic()

    assert(monotonic() - began >= seconds(0))
    assert(monotonic() is duration)

@test
two_of_one_kind_are_ordered_and_two_kinds_are_not() =
    assert(epochSeconds(1) < epochSeconds(2))
    assert(epochSeconds(2) >= epochSeconds(2))
    assert(seconds(1) < minutes(1))
    assert(!(epochSeconds(1) == seconds(1)))

@test
each_kind_keys_a_table_by_its_own_value() =
    val t = {}

    t[epochSeconds(3)] = "moment"
    t[seconds(3)] = "length"

    assertEq(t[epochSeconds(3)], "moment")
    assertEq(t[seconds(3)], "length")
    assertEq(len(t), 2)

@test
both_kinds_print_the_way_a_reader_wants_them() =
    // ISO 8601 for the moment, which sorts as text in the order it sorts as time; and for the
    // length, what a person would write down.
    assertEq(string(epochSeconds(0)), "1970-01-01T00:00:00Z")
    assertEq(string(epochSeconds(-1)), "1969-12-31T23:59:59Z")
    assertEq(string(epochMillis(1756900000000)), "2025-09-03T11:46:40Z")
    assertEq(string(hours(1) + minutes(30)), "1h 30m")
    assertEq(string(seconds(0)), "0s")
    assertEq(string(millis(-1500)), "-1s 500ms")
    assertEq(string(micros(1500)), "1500us")
