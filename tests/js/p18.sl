// The calendar, on both back ends.
//
// The two hold it entirely differently and that is the reason this file exists: the interpreter
// reads the IANA database off the host through `sysl.time.tzif` and does its calendar arithmetic in
// `sysl.time`, while the emitted program asks `Intl` what a zone's clocks showed and undoes the
// reading to get the offset. Nothing about those two arrangements makes them agree -- what they
// print is the only thing that says they do.
//
// **NOTHING HERE READS THE CLOCK AND NOTHING HERE IS IN THE FUTURE, and the second half is a
// measured constraint rather than caution.** The two back ends read two COPIES of tzdata: the
// interpreter reads `/usr/share/zoneinfo`, which this machine has at 2026c, and node reads the
// release bundled into its ICU, which is 2025c. Over 598 zones at six instants the two agree on all
// 2985 readings from 2000 through 2025 and disagree on 7 at 2038-01-01 -- America/Edmonton,
// America/Vancouver, America/Yellowknife and Africa/Casablanca, every one of them a zone whose
// FUTURE rules changed in the release between. Neither back end is wrong; each reads the database
// its host has. So a corpus that pinned a projection would be pinning the skew, and every instant
// below is settled history.
//
// **`abbrev` and `isDST` are not here**, being the two calendar names a JavaScript host cannot
// answer at all -- `Intl` carries CLDR display names rather than IANA abbreviations, and exposes no
// daylight-saving flag. A program whose two back ends print different things cannot be in this
// corpus by construction, so their refusals are checked in `tests_time.sysl` through `node_said`,
// which is what that helper exists for.

import { date, time, dateTime, zone, epochSeconds, epochMillis, instant, days, weeks, months,
    years, seconds, minutes, hours, parseDate, parseTime, parseDateTime, parseTimestamp } from slate:time

val toronto = zone("America/Toronto").value
val london = zone("Europe/London").value
val kolkata = zone("Asia/Kolkata").value
val chatham = zone("Pacific/Chatham").value
val lordHowe = zone("Australia/Lord_Howe").value
val utc = zone("UTC").value

// The six values, built and printed. A zoned reading writes its offset and then its zone in
// brackets, and a zone that is a fixed offset does not name itself twice.
val d = date(2024, 7, 1)
val t = time(9, 30, 5, 123456)
val dt = dateTime(2024, 7, 1, 9, 30, 5, 123456)
val moment = epochSeconds(1719792000)
val z = moment.at(toronto)
val p = months(14) + days(3)

print(d, t, dt, z, p)
print(utc, toronto, zone("+05:30").value, zone("GMT").value)
print(moment.at(kolkata), moment.at(chatham), moment.at(lordHowe), moment.at(utc))

// Every shape the renderers have: no fraction, whole milliseconds, microseconds to the last digit,
// a year that has to be padded, and one before the era.
print(time(0, 0), time(23, 59, 59), time(1, 2, 3, 500000), time(1, 2, 3, 1))
print(date(1, 1, 1), date(-44, 3, 15), date(9999, 12, 31))
print(dateTime(1969, 12, 31, 23, 59, 59), epochMillis(-86400000).at(utc))
print(days(0), days(-3), weeks(2), months(-14), years(2) + months(1) + days(-5))

// The parts, off each of the three kinds that carry them.
print(d.year(), d.month(), d.day(), d.weekday(), d.monthName(), d.dayOfYear(), d.daysInMonth(), d.isLeapYear())
print(dt.hour(), dt.minute(), dt.second(), dt.micros())
print(z.year(), z.month(), z.day(), z.hour(), z.minute(), z.second(), z.weekday())
print(z.date(), z.time(), z.dateTime(), z.zone(), z.instant())
print(z.epochSeconds(), z.epochMillis(), z.epochMicros())
print(date(2024, 2, 1).daysInMonth(), date(2023, 2, 1).daysInMonth(), date(1900, 2, 1).isLeapYear(),
    date(2000, 2, 1).isLeapYear())

// `at`, and the two awkward cases. **A wall reading a zone skips names no instant and one it repeats
// names two**, and each is a result rather than a silent pick.
print(d.at(t), moment.at(london), z.at(kolkata))
print(dateTime(2024, 3, 10, 2, 30).at(toronto))
print(dateTime(2024, 3, 10, 2, 30).at(toronto, "after"))
print(dateTime(2024, 11, 3, 1, 30).at(toronto))
print(dateTime(2024, 11, 3, 1, 30).at(toronto, "earlier"), dateTime(2024, 11, 3, 1, 30).at(toronto, "later"))

// Lord Howe moves its clocks by THIRTY minutes, which is the case a gap worked out in whole hours
// gets wrong.
print(dateTime(2024, 10, 6, 2, 15).at(lordHowe))
print(dateTime(2024, 10, 6, 2, 15).at(lordHowe, "after"))
print(dateTime(2024, 4, 7, 1, 45).at(lordHowe, "earlier"), dateTime(2024, 4, 7, 1, 45).at(lordHowe, "later"))

// **READINGS OLD ENOUGH TO REACH TWO THINGS NOTHING ELSE HERE DOES**, and both were put here by a
// negative control rather than by design: breaking the era handling in the JavaScript runtime
// changed nothing above, which said the corpus had no reading before year 1 in it.
//
// The first is the era itself -- `Intl` reports a year before 1 as a positive number with `era: BC`,
// so a reading that ignored the era would be off by twice the year. The second is local mean time:
// before a place kept railway time its offset is its longitude, which has SECONDS in it --
// Toronto's is -5:17:32 -- and `sysl.time`'s offset is whole minutes, so the two back ends have to
// truncate that the same way or every reading before 1883 differs by a minute.
val ancient = [-62167219200, -62135596800, -3786825600, -2208988800, -1830384000]

for secs in ancient
    val old = epochSeconds(secs)

    print(old.at(toronto), old.at(london), old.at(kolkata))

// An offset is a duration, so reading one is ordinary duration arithmetic.
print(z.offset(), toronto.offset(moment), kolkata.offset(moment), chatham.offset(moment))
print(z.offset().hours(), kolkata.offset(moment).minutes())

// `startOf`, over each unit and each kind.
print(z.startOf("year"), z.startOf("month"), z.startOf("week"), z.startOf("day"))
print(z.startOf("hour"), z.startOf("minute"), z.startOf("second"))
print(dt.startOf("month"), dt.startOf("week"), dt.startOf("hour"))
print(d.startOf("year"), d.startOf("month"), d.startOf("week"))
print(date(2024, 1, 1).startOf("week"), date(2024, 12, 31).startOf("week"))

print(d.onOrAfter("monday"), d.onOrAfter("Monday"), d.onOrAfter("sunday"), date(2024, 7, 7).onOrAfter("sunday"))

// The arithmetic. **A duration moves a reading along the timeline and a period moves its calendar**,
// which is the whole reason there are two length types: an hour after 01:30 on a night the clocks go
// forward is 03:30, and a day after Saturday at 09:00 is Sunday at 09:00 whatever happened in
// between.
print(d + days(1), d - days(1), d + months(1), d + years(1))
print(date(2024, 1, 31) + months(1), date(2023, 1, 31) + months(1), date(2024, 1, 31) + months(13))
print(date(2024, 3, 1) - date(2024, 1, 31), date(2024, 1, 1) - date(2025, 1, 1))
print(dt + hours(2), dt - minutes(90), dt + days(1), dt + months(1))
print(dt - dateTime(2024, 7, 1, 0, 0), dateTime(2024, 7, 2, 0, 0) - dateTime(2024, 7, 1, 0, 0))
print(z + days(1), z + hours(24), z - hours(1), z + months(1))
print(z - moment.at(london), z - z)
print(p + days(4), p - months(2), p * 2, 2 * days(3))

// The one that earns the two types: over the spring change in Toronto, a day and twenty-four hours
// are different answers.
val night = dateTime(2024, 3, 9, 20, 0).at(toronto).value

print(night + days(1), night + hours(24))

// Ordering and equality. **A zoned reading orders by the INSTANT and is equal on the instant AND the
// zone**, so two readings of one moment in two zones are neither before nor after each other and are
// not equal either.
print(d < date(2024, 7, 2), d == date(2024, 7, 1), d == dateTime(2024, 7, 1, 0, 0))
print(t < time(9, 30, 6), t == time(9, 30, 5, 123456), dt >= dt)
print(z == moment.at(toronto), z == moment.at(london), z < moment.at(london), z <= moment.at(london))
print(toronto == zone("America/Toronto").value, toronto == london, utc == zone("Z").value)
print(days(30) == months(1), months(1) == months(1), weeks(2) == days(14))

// A table keys by value, and each kind is salted so two of different kinds holding one number do not
// collide.
val tbl = {}

tbl[d] = "a day"
tbl[t] = "a reading"
tbl[dt] = "both"
tbl[toronto] = "a zone"
tbl[z] = "a moment somewhere"
tbl[p] = "a length by the calendar"
print(tbl[date(2024, 7, 1)], tbl[time(9, 30, 5, 123456)], tbl[toronto], tbl[z], len(tbl))

// The words a program annotates with.
print(d is date, t is time, dt is dateTime, toronto is zone, z is zoned, p is period)
print(d is dateTime, z is instant, z.instant() is instant, p is duration, days(1) is period)

takesDate(v: date) = v
takesZoned(v: zoned) = v
takesPeriod(v: period) = v

print(takesDate(d), takesZoned(z), takesPeriod(p))

// `format` -- every element the pattern language has except `zzz`, which is the abbreviation.
print(z.format("YYYY-MM-DD hh:mm:ss z"))
print(z.format("Y YY YYYY M MM MMM MMMM D DD DDD"))
print(z.format("WWW WWWW h hh h12 hh12 a A m mm s ss"))
print(dt.format("f ff fff ffff fffff ffffff"))
print(z.format("zzzz"), z.format("zz"), moment.at(utc).format("z"))
print(dt.format("WWWW, MMMM D, Y |at| h12:mm a"))
print(dateTime(2024, 7, 1, 0, 30).format("h12 a"), dateTime(2024, 7, 1, 12, 30).format("h12 a"))
print(d.format("YYYY-MM-DD"), t.format("hh:mm:ss.ffffff"))

// The four readers. **Text is a condition and not a fault**, so each answers a result.
print(parseDate("2024-07-01"), parseTime("09:30"), parseTime("09:30:05.5"))
print(parseDateTime("2024-07-01T09:30"), parseDateTime("2024-07-01 09:30:05"))
print(parseTimestamp("2024-07-01T00:00:00Z"), parseTimestamp("2024-06-30T20:00:00-04:00"))
print(parseDate("2024-02-30"), parseDate("2024-13-01"), parseDate("nope"), parseDate("2024-07-01x"))
print(parseTime("24:00"), parseTime("09:60"), parseTime("09:30:60"), parseTime("09:30:05."))
print(parseDateTime("2024-07-01"), parseTimestamp("2024-07-01T09:30:00"))
print(zone("Nowhere/Nothing"), zone("/etc/passwd"), zone("../x"), zone(""), zone("-0400"))

anything(v) = v

// The error paths, which are half of what a differential corpus is for: a diagnostic written twice
// is a diagnostic written differently.
say(f)
    try
        f()
    catch e
        print(e.message)

say(() -> date(2024, 2, 30))
say(() -> date(2024, 13, 1))
say(() -> date(2024, 7))
say(() -> date(2024, 7, 1.5))
say(() -> date(anything(3)))
say(() -> time(24, 0))
say(() -> time(9, 60))
say(() -> time(9, 30, 60))
say(() -> time(9, 30, 0, 1000000))
say(() -> time(9))
say(() -> time(anything(3)))
say(() -> dateTime(anything(3)))
say(() -> dateTime(2024, 7, 1))
say(() -> dateTime(d, d))
say(() -> dateTime(t, t))
say(() -> zone(anything(3)))
say(() -> anything(d).hour())
say(() -> anything(t).year())
say(() -> anything(t).at(toronto))
say(() -> anything(d).at(toronto))
say(() -> anything(z).at(t))
say(() -> anything(moment).at(t))
say(() -> anything(p).at(toronto))
say(() -> anything(d).at(toronto, "earlier", "later"))
say(() -> anything(d).at())
say(() -> dateTime(2024, 11, 3, 1, 30).at(toronto, "sooner"))
say(() -> anything(d).startOf("year", "month"))
say(() -> d.startOf("day"))
say(() -> d.startOf("bogus"))
say(() -> anything(p).startOf("year"))
say(() -> anything(moment).format("Y"))
say(() -> anything(p).format("Y"))
say(() -> d.format("hh:mm"))
say(() -> t.format("YYYY"))
say(() -> dt.format("zz"))
say(() -> d.format("YYY"))
say(() -> d.format("MMMMM"))
say(() -> d.format("DDDD"))
say(() -> d.format("WW"))
say(() -> t.format("hhh"))
say(() -> t.format("mmm"))
say(() -> t.format("sss"))
say(() -> t.format("fffffff"))
say(() -> t.format("aa"))
say(() -> z.format("zzzzz"))
say(() -> d.format("|never closed"))
say(() -> d.format(anything(3)))
say(() -> anything(d).onOrAfter("nope"))
say(() -> anything(t).onOrAfter("monday"))
say(() -> anything(moment).offset())
say(() -> toronto.offset(anything(3)))
say(() -> anything(d).offset(moment))
say(() -> anything(toronto).offset())
say(() -> anything(d).days())
say(() -> anything(p).seconds())
say(() -> parseDate(anything(3)))
say(() -> anything(parseDate)())
say(() -> anything(days(1)).hours())
say(() -> anything(d) + hours(1))
say(() -> anything(moment) + days(1))
say(() -> anything(z) - moment)
say(() -> anything(t) + days(1))
say(() -> anything(d) < anything(z))
