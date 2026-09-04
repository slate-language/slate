# JavaScript

```
$ slate js hello.sl -o hello.js
```

`slate js` reads the same tree the interpreter walks and writes **one self-contained JavaScript file** —
the runtime, any framework, and the program. There is no bundler, no `node_modules`, and nothing to
install beside it. The output runs under node, under quickjs, and in a browser.

`slate test --js .` compiles a whole directory into one program and runs it under node, reporting in the
same words `slate test` does. **A test is written about the language rather than about an implementation
of it**, so the same file is the check that the two back ends have not drifted apart — which is worth more
than it sounds, since a test driving the interpreter says nothing whatever about `slate js`.

## The value model

**An integer is a `BigInt` and a real is a `number`, and every operator goes through the runtime.** This is
the decision everything else follows from, and it is not caution: slate's integer is 64 bits, wraps,
divides towards zero and shifts to 63 places, and a double does none of those — nor could it be told from
a real afterwards, so `2.5 is integer` would answer whatever the value happened to look like.

The operators follow because the two languages disagree too often for the exceptions to be worth tracking:

| | slate | JavaScript |
|---|---|---|
| `7 / 2` | `3` | `3.5` |
| `0` in a condition | true | false |
| `[1] == [1]` | true | false |
| `1 << 40` | 2^40 | 256 |

## What is not there yet

**`slate:net`, `slate:regex`, `slate:crypto`, `slate:password`, `slate:brotli`,
`slate:llhttp`, `slate:process`'s `run`, `fetch`, and the modules written over them.** Each is a name that
says *"not in the JavaScript back end yet"* when a program reaches it, rather than a name that is not
there — so a program is told which half of the world it is in.

### `slate:time` is whole, except for two things a JavaScript host does not have

An instant, a duration, the clock that reads one and the arithmetic over both work exactly as they do
under the interpreter:

```slate
import { epochMillis, epochSeconds, seconds, minutes, hours, now } from slate:time

val t = epochMillis(1756900000000)

print(t)
print(t + minutes(90), (t + hours(2)) - t)
print(hours(1) + minutes(30), minutes(hours(1) + minutes(30)))
print(epochSeconds(t), now() is instant)
```

```output
2025-09-03T11:46:40Z
2025-09-03T13:16:40Z 2h
1h 30m 90
1756900000 true
```

**And so does the calendar.** `date`, `time`, `dateTime`, `zone`, `zoned` and `period` are built over
`Intl` — the value model, the arithmetic, `startOf`, `onOrAfter`, `format` and the four parsers — and
answer what the interpreter answers:

```slate
import { date, dateTime, zone, epochSeconds, days, hours, months, parseDate } from slate:time

val toronto = zone("America/Toronto").value
val t = epochSeconds(1719792000).at(toronto)

// The Saturday evening before the clocks go forward, which is where a day and twenty-four hours
// stop being the same length.
val night = dateTime(2024, 3, 9, 20, 0).at(toronto).value

print(t)
print(t.year(), t.monthName(), t.weekday(), t.hour())
print(t.format("WWWW, MMMM D, Y |at| h12:mm a"))
print(date(2024, 1, 31) + months(1), night + days(1), night + hours(24))
print(dateTime(2024, 3, 10, 2, 30).at(toronto).error)
print(parseDate("2024-02-30").error)
```

```output
2024-06-30T20:00:00-04:00[America/Toronto]
2024 June Sunday 20
Sunday, June 30, 2024 at 8:00 pm
2024-02-29 2024-03-10T20:00:00-04:00[America/Toronto] 2024-03-10T21:00:00-04:00[America/Toronto]
2024-03-10T02:30:00 never happens in America/Toronto -- the clocks go from -05:00 to -04:00 -- say `.at(zone, "after")` to take the reading past the gap
cannot read "2024-02-30" as a date: day is out of range
```

The worry that kept the calendar out was that a zone read from `Intl` and a zone read from the IANA
database are two answers to one question, and a program saying what time a meeting is in Toronto may
not get a different answer for having been compiled rather than interpreted. **That was a worry rather
than a measurement, and it has been measured**: every zone this machine has, 598 of them, at six
instants. The two agree on **all 2985 readings from 2000 through 2025**.

**Two names still refuse, and neither is owed work — they are things the host does not have.**

**`abbrev`, because `Intl` has no IANA abbreviation at all.** What its `timeZoneName` options carry is
CLDR's English *display* data, which agrees with tzdata for American zones by coincidence and nowhere
else. Measured on one instant:

| zone | IANA | `short` | `long` |
|---|---|---|---|
| `America/Toronto` | `EDT` | `EDT` | Eastern Daylight Time |
| `Europe/London` | `BST` | `GMT+1` | British Summer Time |
| `Asia/Kolkata` | `IST` | `GMT+5:30` | India Standard Time |
| `Africa/Cairo` | `EEST` | `GMT+3` | Eastern European Summer Time |

67 of 84 readings disagree, and `shortGeneric` is worse — "United Kingdom Time". `zzz` in a `format`
pattern is the same name under another spelling and refuses with the same sentence.

**`isDST`, because `Intl` exposes no daylight-saving flag**, and the offset-comparison rule every
JavaScript date library uses instead is unsound in *both* directions. Over 3582 readings it is wrong at
31 of them:

- it **misses** a zone that is permanently on daylight time. `Africa/Casablanca` and `Africa/El_Aaiun`
  are `+01` all year with tzdata's flag set, and every Argentine zone was in 2000. No comparison of
  offsets can see a flag that never changes.
- it **invents** one for a zone that moved its *standard* offset mid-year. `Asia/Almaty` and
  `Asia/Qostanay` went `+06` to `+05` in March 2024, so January's offset exceeds May's and the rule
  reads January as daylight time.

The second half is what settles it: the failure is an ordinary permanent offset change rather than an
exotic zone, so there is no version of the rule that under-reports safely.

**The alternative to both — a table of zone rules carried in slate's own JavaScript runtime — was
considered and refused.** It would answer them, which is what makes it a decision rather than an
oversight. It is refused because it is a *second copy of tzdata*: an authority the runtime would hold
against the one the interpreter reads from the system database, kept in step by hand, in a place nobody
looks until a zone changes and only one of the two back ends notices. The measurement above is exactly
the drift that copy would reintroduce.

**One thing the measurement DID find, and it is nobody's defect.** The two back ends read two copies of
tzdata — the interpreter reads the host's `/usr/share/zoneinfo` and a JavaScript engine reads the
release bundled into its ICU — and those are not always the same release. On this machine they were
2026c and 2025c, and the seven readings out of 3582 where the offsets disagreed were all at 2038-01-01,
in zones whose *future* rules changed in the release between. Each back end reads the database its host
has, which is what both are supposed to do; a program that pins a projected offset decades out is
pinning the skew rather than the calendar.

**An instant is a whole number of milliseconds from the clock on both back ends**, `Date.now()` having
nothing finer — the interpreter drops its microseconds to match. An instant a program *builds* keeps
every digit: `epochMicros(1000000001)` is exact wherever it runs.

**`slate:dom` is the other way round**: it works only here. Under the interpreter every one of its names
faults with a sentence naming the *command* rather than the code, because the same program is correct in a
browser and it is the command that is wrong.

## Blocks and order

JavaScript has no block expression, so `val x = if c then 1 else 2` becomes an `if` statement over a
temporary. **An immediately-called function would have been the other way and is wrong**: `return`,
`break`, `await` and `yield` all mean the enclosing function, and a wrapper takes every one of them away.
The one place a wrapper is written is a default parameter, where there is no statement position to hoist
into and nothing of the enclosing function to lose.
