// Dates and times: eight types, because JavaScript's one type is where its every date bug comes from.
//
// A `Date` in node is an instant that will answer calendar questions, reading the host's zone to do
// it -- so the same program says one thing on your machine and another on the server, and nothing in
// it names a zone. Here an instant has no year at all until you say where you are standing.

// The temporal names are a module rather than globals, so a program says which of them it wants.
// `at`, `offset`, `format`, `day` and `second` are words a program has every right to for itself.
import { now, monotonic, instant, date, time, dateTime, zone, hours, days, weeks, months, year, month, day, hour, second, at, offset, format, parseDate } from slate:time

val t = now()

print("a point on the timeline:", t.string())

// A zone comes back as a result, because which zones a host has is the host's business and the name
// usually arrives from a configuration file rather than from the program.
val found = zone("America/Toronto")

if !found.ok
    print(found.error)
else
    val here = t.at(found.value)

    print("read there:", here.string())
    print(here.format("WWWW, MMMM D, Y |at| h12:mm a zzz"))
    print("offset:", here.offset().hours(), "hours,", if here.isDST() then "on summer time" else "on standard time")

// The two kinds of length, and the difference between them is a whole class of bug.
//
// A duration is exact timeline; a period is a step through the calendar. On the night the clocks go
// forward, a day later is the same wall clock and 23 hours later -- and 24 hours later is an hour
// further on. Both are right, and the type says which one was meant.
val z = zone("America/Toronto").value
val saturday = dateTime(2026, 3, 7, 9, 0).at(z).value

print("a day later: ", (saturday + days(1)).string())
print("24 hours later:", (saturday + hours(24)).string())

// A month is not a number of days, so the two scales never convert -- and adding a month clamps to
// the end of the month it lands in rather than overflowing into the next one.
print(months(1).days(), "days in a month;", weeks(2).days(), "in a fortnight")
print((date(2026, 1, 31) + months(1)).string(), "is a month after the 31st of January")

// A wall reading may name no instant at all, or two of them. Every mainstream library answers
// anyway; this one hands the choice back.
val skipped = dateTime(2026, 3, 8, 2, 30).at(z)

print(if skipped.ok then skipped.value.string() else skipped.error)
print(dateTime(2026, 3, 8, 2, 30).at(z, "after").value.string())

// Text is the boundary, so it is a result -- there is no `Invalid Date` here to spread NaN through
// three functions before anybody notices.
print(parseDate("2026-02-30").error)
print(parseDate("2026-08-28").value.weekday())

// Measuring how long something took is a different clock: the wall clock can be set backwards, and
// this one cannot.
val started = monotonic()
var total = 0

for i in 1..1000
    total = total + i

print("summed to", total, "in under", (monotonic() - started).millis() + 1, "ms")
