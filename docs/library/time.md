# `slate:time`

**Eight types, because one type is where a date library's bugs come from.** A `Date` that is an instant
answering calendar questions by silently reading the host's zone is the conflation every famous defect
follows from, so slate splits it:

| type | what it is |
|---|---|
| `instant` | a point on the timeline, with no calendar |
| `duration` | an exact length — micros to weeks |
| `date` | a calendar date, with no time of day |
| `time` | a time of day, with no date |
| `dateTime` | a wall reading, with no zone |
| `zone` | a zone |
| `zoned` | a wall reading in a zone |
| `period` | months and days |

Each has a [type word](../reference/patterns.md) that tests for it, so `date`, `time` and `zone` in
pattern position test rather than bind. Ordinary `val date = …` is unaffected.

## Making one

```slate
import { now, monotonic, date, time, dateTime, zone, localZone, utc } from slate:time

now()                       // an instant
monotonic()                 // a DURATION -- it names no point in time
date(2026, 9, 2)
time(14, 30, 0)
dateTime(2026, 9, 2, 14, 30, 0)
zone("America/Toronto")
localZone()
utc                         // a VALUE, not a call -- the one zone that cannot fail to be found
```

`instant`, `epochSeconds`, `epochMillis` and `epochMicros` cross to and from a count.

**The clock reads whole milliseconds and an instant holds microseconds.** `now()` is a millisecond
reading on every back end — JavaScript's has nothing finer, and a timestamp that printed six fractional
digits in one program and three in another would be a difference nobody asked for. An instant a program
builds is exact: `epochMicros(1000000001)` keeps its last digit, and `monotonic()`, which is what an
elapsed time is measured with, is finer than a millisecond wherever the host clock is.

**Durations** are `micros millis seconds minutes hours days weeks`; **periods** are `months years`.

```slate
seconds(90)                 // a duration
months(3)                   // a period
2.hours()                   // the same length, as a method
```

## Duration against period

**This is the distinction that earns the type count.** A duration is exact timeline and may be added to
anything; a period is months and days and may be added only to a calendar reading.

```slate
import { date, days, months, weeks } from slate:time

val d = date(2026, 3, 7)

print(d + days(1))
print(d + months(1))
print(months(1).days(), weeks(2).days())
```

```output
2026-03-08
2026-04-07
0 14
```

`zoned + days(1)` keeps the wall clock across a daylight-saving change and `zoned + hours(24)` does
not — both right, and the program says which. `instant + days(1)` is **refused**, an instant having no
calendar.

Both are right, and the program says which.

**Months and days never convert.** `months(1).days()` is 0; `weeks(2).days()` is 14. A month is 28 to 31
days, so any other answer is wrong somewhere. There is deliberately no `days` on a duration.

## Reading one

**One word per unit, and the receiver decides the question. Plural is a length, singular is a part.**

```slate
import { date, hours, seconds, year, month, day, weekday, daysInMonth, isLeapYear } from slate:time

val d = date(2026, 9, 2)

print(year(d), month(d), day(d))
print(d.year(), weekday(d), daysInMonth(d), isLeapYear(d))
print(2.hours(), seconds(90))
print(hours(3).minutes())       // how many whole minutes it is
```

```output
2026 9 2
2026 Wednesday 30 false
2h 1m 30s
180
```

`year month day hour minute second weekday monthName dayOfYear daysInMonth isLeapYear`.

## `at`

**`at` is the one word for reading one thing in terms of another:**

```slate
instant.at(zone)
zoned.at(zone)
date.at(time)
dateTime.at(zone)           // a RESULT
```

**A wall reading that a zone skips or repeats is handed back, not guessed at.** `dateTime.at(zone)` answers
an error naming the gap or the ambiguity, and `.at(zone, "earlier" | "later" | "after")` makes the choice
explicitly. Every mainstream library picks one silently.

`offset`, `isDST` and `abbrev` ask a zone about a moment. `startOf` truncates and `onOrAfter` moves to the
next weekday.

## The two channels

```slate
import { parseDate } from slate:time

print(parseDate("2026-09-02"))
print(parseDate("2026-02-30"))      // text from outside is a RESULT
```

```output
{ok: true, value: 2026-09-02}
{ok: false, error: "cannot read \"2026-02-30\" as a date: day is out of range"}
```

Three numbers the program wrote are a **fault**, the other half of the same rule:

```slate
import { date } from slate:time

print(date(2026, 2, 30))
```

```error
there is no such date
```

`parseDate`, `parseTime`, `parseDateTime` and `parseTimestamp`. **There is no `Invalid Date` and nothing
spreads `NaN`.**

## Comparison

**`==` on a zoned reading needs the same instant and the same zone, where `<` compares only the instant.**
09:00 in Toronto and 09:00 in Tokyo are different readings and neither is before the other. Java draws the
line in the same place.

## `format`

moment-flavoured, with `|bars|` around literal text and `WWWW` where moment writes `dddd`:

```slate
import { dateTime, utc } from slate:time

val t = dateTime(2026, 9, 2, 14, 30, 0).at(utc).value

print(t.format("YYYY-MM-DDThh:mm:ssZ"))
print(t.format("|on| WWWW, MMMM D, YYYY"))
```

```output
2026-09-02T14:30:00Z
on Wednesday, September 2, 2026
```

An element the value does not have is refused, never zero-filled:

```slate
import { date } from slate:time

print(date(2026, 9, 2).format("hh:mm"))
```

```error
hh
```

**An element the value does not have is refused, never zero-filled.** `date.format("hh:mm")` says a date
has no time of day — a date rendered as `00:00` is a midnight the program never meant, and that is exactly
the value that then gets stored and reported on. `format` is in the *instant's* table for the same reason,
so the refusal can say "read it in a zone first".

`f` caps at six digits, a reading being microseconds. `a`/`A` are `am`/`AM`. The zone elements are
lower-case `z`, so `Z` stays a literal.

## Timers

**`sleep` and `setTimeout` take a duration as well as a number**, so `await sleep(2.seconds())` reads as
what it is.

**`monotonic()` answers a duration, not an instant**: it names no point in time, and elapsed measurement is
the one thing it is for.
