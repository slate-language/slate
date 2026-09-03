// An instant and a duration, on both back ends.
//
// The two hold them differently and the difference is the reason this file exists: the interpreter
// carries `sysl.time`'s own arithmetic and renders through `time.sysl`, while the emitted program
// carries a `BigInt` of microseconds and renders with a calendar written out in JavaScript. Nothing
// here reads the clock -- what `now()` answers is not a thing two runs agree about, let alone two
// back ends -- so every instant below is one the program built itself.
//
// **The calendar half is deliberately absent**, and `javascript.md` says so: `date`, `zone`,
// `format` and the rest refuse under `slate js`, so a program using one cannot be in this corpus at
// all.

import { epochSeconds, epochMillis, epochMicros, instant, micros, millis, seconds, minutes,
    hours } from slate:time

val t = epochMillis(1756900000000)

print(t, string(t), t.string())
print(epochSeconds(t), epochMillis(t), epochMicros(t))
print(instant(t) == t)

// Every fractional shape the renderer has: none, whole milliseconds, and microseconds down to the
// last digit -- which is where a rendering written twice is most likely to have been written
// differently.
print(epochMicros(1000000000), epochMicros(1000500000), epochMicros(1000000001))
print(epochMicros(1000123456), epochMicros(1000000010))

// Before the epoch, which is where truncating division and flooring division part company.
print(epochSeconds(-1), epochSeconds(0), epochMicros(-1), epochMillis(-86400000))

// A year the four-digit form has to pad, and one before the era.
print(epochMicros(-62135596800000000), epochSeconds(-62167219200))

val d = hours(1) + minutes(30)

print(d, string(d), d.string())
print(micros(d), millis(d), seconds(d), minutes(d), hours(d))

// Every part of the duration's own rendering: the sign, the zero, whole milliseconds, and a
// remainder that is not.
print(seconds(0), micros(1), millis(-1500), millis(1) + micros(1), hours(-2) - minutes(3))
print(micros(1500), micros(1000), seconds(90), hours(25))

// The arithmetic, in both orders where it commutes.
print(t + seconds(90), t - hours(1), seconds(90) + t)
print(t - t, (t + hours(2)) - t)
print(d * 2, 2 * d, d / 3, d - minutes(30))

// Ordering and equality. **An instant and a duration are never equal and never ordered**, one being
// a moment and the other a length.
print(t == epochMillis(1756900000000), t == t + micros(1), d == minutes(90), d == t)
print(t < t + micros(1), t >= t, d > minutes(89), d <= d)

// A table keys by value, and each kind is salted so two of different kinds holding one number do not
// collide.
val tbl = {}

tbl[t] = "moment"
tbl[seconds(3)] = "length"
tbl[micros(3000000)] = "again"
tbl[epochMicros(3000000)] = "three seconds past the epoch"
print(tbl[t], tbl[epochMillis(1756900000000)], tbl[seconds(3)], tbl[epochMicros(3000000)], len(tbl))

// The words a program annotates with, and the six calendar kinds that answer false because nothing
// can be one.
print(t is instant, d is duration, t is duration, d is instant)
print(t is date, t is time, t is dateTime, t is zone, t is zoned, t is period)

takesInstant(x: instant) = x
takesDuration(y: duration) = y

print(takesInstant(t), takesDuration(d))

// The four universal methods, which a temporal value answers like any other.
print(t.eq(epochMillis(1756900000000)), t.equals(epochMillis(1756900000000)), t.ne(d))
print([t, d], { at: t, took: d })

anything(v) = v

// The error paths, which are half of what a differential corpus is for: a diagnostic written twice
// is a diagnostic written differently.
say(f)
    try
        f()
    catch e
        print(e.message)

say(() -> anything(t) + anything(t))
say(() -> anything(t) < anything(d))
say(() -> anything(d) / 0)
say(() -> seconds("x"))
say(() -> epochMillis(true))
say(() -> instant(3))
say(() -> anything(t).minutes())
say(() -> anything(d).epochMillis())
