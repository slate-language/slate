// A number makes a length of time, on both back ends.
//
// `2.seconds()` is `seconds(2)`: the interpreter's number table carries the time names, and the
// emitted program's `number` table has to carry them too or the method is refused as something an
// integer cannot do. Every name `time.md` documents on a number is called here, as a method and
// beside the free function it must equal.

import { micros, millis, seconds, minutes, hours, days, weeks, months, years } from slate:time

// -- the exact lengths -------------------------------------------------------------------------

print(5.micros(), 5.millis(), 2.seconds(), 3.minutes(), 2.hours())
print(2.seconds() == seconds(2), 3.minutes() == minutes(3), 2.hours() == hours(2))
print(7.micros() == micros(7), 9.millis() == millis(9))
print(90.seconds(), 90.minutes(), hours(3).minutes())
print(2.hours() + 30.minutes(), (1500).millis())

// -- the calendar lengths ----------------------------------------------------------------------

print(3.days() == days(3), 2.weeks() == weeks(2), 3.months() == months(3), 2.years() == years(2))
print(2.weeks().days(), 1.months().days(), 24.months().years())

// -- the refusals keep their sentences --------------------------------------------------------

anything(v) = v

try
    print(anything(2).fortnights())
catch e
    print(e.message)

try
    print(anything(2.5).seconds())
catch e
    print(e.message)

try
    print(anything(2.5).days())
catch e
    print(e.message)
