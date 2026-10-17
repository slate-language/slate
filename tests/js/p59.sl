// `utc` on both back ends: the one zone that is a VALUE and not a call.
//
// It is the zone `zone("UTC")` answers, so it prints as `UTC`, tests as a `zone`, compares equal to
// the zone asked for by name, and is accepted wherever a zone is: `at`, a zoned reading's own
// functions, `zone(v)` given a reading, and `format`. Everything pinned here is a fixed instant in
// settled history, so no zone database is being asked about a projection.

import { utc, zone, date, time, dateTime, epochSeconds, epochMillis, hours, days, months } from slate:time

print(utc)
print(utc is zone, string(utc), zone("UTC").value == utc, zone("GMT").value == utc)

val moment = epochSeconds(1700000000)
val z = moment.at(utc)

print(z)
print(z.zone() == utc, zone(z) == utc, zone(utc) == utc)
print(z.year(), z.month(), z.day(), z.hour(), z.minute(), z.second())
print(z.date(), z.time(), z.dateTime(), z.instant())

// A wall reading placed in `utc`, and the arithmetic that stays in it.
val wall = dateTime(2024, 2, 29, 23, 30, 0)
val placed = wall.at(utc).value

print(placed, placed + hours(1), placed + days(1), placed + months(12))
print(date(2026, 8, 28).at(time(9, 0)).at(utc).value)
print(placed.startOf("day"), placed.startOf("month"))
print(placed.format("YYYY-MM-DD hh:mm z"))
print(epochMillis(-86400000).at(utc), epochSeconds(0).at(utc).string())

// A zone is not a function: calling `utc` is refused rather than answering a zone, and both back
// ends say so in one sentence.
var refused = ""

try
    utc()
catch e
    refused = e.message

print(refused)
