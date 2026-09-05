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

**One thing `print` says differently, and it is not closable cheaply.** A promise prints as
`<promise pending>`, `<promise 5>` or `<promise failed: …>` in the interpreter and as `<promise>`
here: a JavaScript promise does not expose its state synchronously, and wrapping every promise in the
runtime so that `print` could read one would cost every `await` in every program to improve a
debugging accident. Printing a promise is not something a program's output should depend on either
way.

## What is not there yet

**`slate:net`, `slate:password`, `slate:llhttp`, `slate:process`'s `run`, and the modules written
over them.** Each is a name that says *"not in the JavaScript back end yet"* when a program reaches
it, rather than a name that is not there — so a program is told which half of the world it is in.
**No global is on that list any more**; `fetch` was the last and has its own section below.

**`slate:brotli` is NOT on that list, and the difference matters.** No JavaScript host has a brotli
encoder and none is coming, so *"not yet"* would be a promise nobody can keep. `compress` and
`decompress` say that they are brotli, that a JavaScript host has none, and that
[`slate:gzip`](../library/gzip.md) is the compression a browser does have. That is `abbrev`'s case
below, drawn the same way.

### `slate:gzip` is whole here, and the container is read by slate rather than by the host

**This is the module the parity rule was written for.** A browser has `CompressionStream` and
`DecompressionStream`, which speak gzip, zlib and raw deflate — so gzip and zlib are compression a
slate program can count on anywhere, where brotli is not.

```slate
import { gzip, gunzip } from slate:gzip

async main()
    val small = await gzip(repeat("<p>hello</p>", 40))
    val back = await gunzip(small, 1 << 20)

    print(back.ok, fromBytes(back.value).value == repeat("<p>hello</p>", 40))

main()
```

```output
true true
```

**All four names answer promises on BOTH hosts, and that is the whole shape decision.** A
`CompressionStream` is a `TransformStream`; there is no synchronous door to it, and slate's rule is
that a host with a thing only in a different SHAPE does not have it. Nothing held the signature yet —
the module is new — so it was written promise-shaped everywhere rather than synchronous in one place
and refusing in the other. The interpreter compresses with miniz and answers a promise it has already
settled.

**The gzip header and trailer are parsed by slate on both back ends**, and only the deflate body goes
to the host's stream. That is what makes the refusals the same sentence wherever a program runs: the
magic bytes, the compression method, a header that ends early, the limit, the stated length and the
CRC-32 are all slate's own checks, and the CRC is computed here rather than taken from anybody.

**One sentence is not shared, and it is the body itself.** miniz says whether a stream that would not
inflate was truncated or corrupt; a host's decompressor throws one `TypeError` for both, and for a
wrong checksum too. So where the interpreter says *this compressed stream ends in the middle* or
*this is not a compressed stream at all*, a JavaScript host says *this compressed stream could not be
read* — a plain statement rather than a guess dressed as a finding. **zlib's own two-byte header is
checked here as well**, so the common case — something that is not a zlib stream at all — does read
the same on both.

### `slate:crypto` is whole here, and WebCrypto is not how

The five digests, `hmac`, `pbkdf2`, `randomBytes` and `timingSafeEqual` all work, and answer what the
interpreter answers:

```slate
import { md5, sha1, sha256, sha512, hmac, pbkdf2, randomBytes, timingSafeEqual } from slate:crypto

val digits = "0123456789abcdef"

hex(bs) = join(map(bs, b -> digits[b / 16] + digits[b % 16]), "")

print(hex(sha256("abc")))
print(hex(md5("abc")), hex(sha1("abc")))
print(hex(hmac("SHA-256", "key", "message")))
print(hex(pbkdf2("SHA-1", "password", "salt", 4096, 20)))
print(len(randomBytes(32)), timingSafeEqual("abc", "abc"), timingSafeEqual("abc", "abd"))
```

```output
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
900150983cd24fb0d6963f7d28e17f72 a9993e364706816aba3e25717850c26c9cd0d89d
6e9ef29b75fffc5b7abae527d58fdadb2fe42e7219011976917343065f58ed4a
4b007901b765489abead49d926f721d065a429c1
32 true false
```

**`crypto.subtle` IS NOT USED, AND THAT IS THE DECISION EVERYTHING HERE FOLLOWS FROM.** The web
platform's only digest is asynchronous and always has been — there is no synchronous hash in a browser
at all — so a `sha256` built on it would answer a *promise* here and a byte array under the
interpreter. **Two back ends disagreeing about the shape of an answer is worse than either being
slow**, and it would have taken a breaking change to the interpreter to fix, over a call that costs
microseconds. So the digests are written out in JavaScript and stay synchronous. `md5` would have had
to be anyway — WebCrypto has never carried it — so four asynchronous digests and one synchronous was
never on offer.

**What that costs, measured on node:** PBKDF2-HMAC-SHA256 at 100,000 iterations is 176 ms here against
7 ms for a native library, and SHA-256 runs at about 280 MiB/s against 3 GiB/s. Roughly 25× either
way. It matters for exactly one call — **a key derivation, which is the one thing here designed to be
slow** — so an iteration count is worth choosing with a browser in mind: 600,000, which is OWASP's
current recommendation for SHA-256, is about a second of a page's main thread.

**`randomBytes` is the one name that reaches for the host, and the host has it.**
`crypto.getRandomValues` is synchronous everywhere, which is what lets the whole module stay
synchronous — the half of `slate:crypto` that cannot be written out at any price is the half a browser
does supply.

**The asymmetric half of JWS is the one thing that refuses.** `slate:jwt`'s `HS256`, `HS384` and
`HS512` are HMAC under a JOSE name and work here in full; `RS*`, `PS*` and `ES*` are RSA and ECDSA,
whose only implementation in a browser is `crypto.subtle`'s and answers a promise where `jwsSign`
answers bytes. That refusal names the algorithm and the reason, so a reader knows the fix is a choice
rather than a wait.

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

### `slate:regex` is whole here, and a pattern is TRANSLATED rather than handed over

`RegExp` is not PCRE2. slate's patterns are Perl's — that is the whole reason `regex.sysl` is on
`sh.sysl.pcre2` rather than on POSIX — and a browser has one regular expression engine. So every
pattern is read through a translator on its way in, and what a construct gets depends on how the two
engines differ over it: an exact equivalent is **translated**, something `RegExp` does not have is
**refused naming the construct**, and something both engines accept while meaning different things is
**translated too**, because that is the one kind a program could get wrong with nothing refusing it.

```slate
import { regex } from slate:regex

print(regex("(?<y>\\d{4})-(\\d{2})").find("on 2026-08").named.y)
print(regex("[[:alpha:]]+").find("42abc!").text)
print(regex("\\p{Greek}+").find("ab\u{3b1}\u{3b2}!").text)
print(regex("\\s").test("\u{a0}"), regex("a.b").test("a\rb"))
print(regex("(\\w+)@(\\w+)").replace("a@b and c@d", "$2 at $1"))
print(len(regex("$").findAll("abc")), regex("a*").split("bb").join("|"))
```

```output
2026
abc
αβ
false true
b at a and d at c
1 |b|b|
```

**Three constructs mean different things in the two engines, and every one is a silent wrong answer
rather than an error.** They were measured through this project's own PCRE2 and through node:

- **`\s`.** PCRE2 here is not in UCP mode, so `\s` is the six ASCII spaces; `RegExp` reads it as
  every Unicode space, twenty-five of them. A record split on `\s` would cut on a no-break space in a
  browser and not in the interpreter. `\s`, `\S`, `\h`, `\H`, `\v`, `\V` and every POSIX class are
  written out as their ranges.
- **`.`.** PCRE2's excludes the newline. `RegExp`'s also excludes the carriage return and the two
  Unicode line separators, so it becomes `[^\n]`.
- **`^` and `$` under `m`**, for the same reason and in the same three characters. They become
  lookarounds, and `RegExp`'s own `m` is never set.

**What is refused, and why none of it is work owed.** A browser's regular expressions have no
possessive quantifier `a*+`, no atomic group `(?>…)`, no branch reset `(?|…)`, no recursion `(?R)`, no
conditional `(?(1)…)`, no `\K`, `\G`, `\C` or `\X`, and no modifier that runs to the end of a pattern
(`(?i)` — the scoped `(?i:…)` does work). Each is refused where the pattern is written, in a sentence
naming the construct.

**A lookbehind is the one place `RegExp` is the LOOSER engine**, and it is refused here so that the two
agree: PCRE2 will not compile a lookbehind whose length is unlimited — `(?<=ab*)c` is *"length of
lookbehind assertion is not limited"* — and `RegExp` takes anything. A **bounded** one compiles on both,
`(?<=ab?)c` and `(?<=a{2,3})c` included. The other place `RegExp` used to be looser closed itself: a
range with a class at one end, `[\d-x]`, is refused by the `u` flag exactly as PCRE2 refuses it.

**`u` is always set, and that is what makes an offset a character.** Without it `RegExp` counts a
subject in UTF-16 code units, so `^.$` says an emoji is two and every offset after one is too big;
PCRE2 is in UTF mode and counts characters. The offsets a match reports are converted back in one walk
of the subject, which is what `regex.sysl` does for the other back end.

**Three differences are left standing and are named here rather than closed.**

- **A backreference to a group that took no part in the match** fails under PCRE2 and matches the empty
  string under `RegExp` — `(?:(?<n>a)|b)\k<n>` is false against `"b"` in the interpreter and true here.
  It is a property of the run rather than of the pattern text, so nothing could be scanned for; refusing
  every pattern with a backreference in it would refuse most real ones.
- **Under `i`, a JavaScript host counts `U+017F` and `U+212A` as word characters**, its `u` mode folding
  them into `s` and `k` where PCRE2's `\w` stays ASCII. That is exactly two code points and only under
  `i`. Closing it would mean rewriting every character class through the `v` flag's set subtraction,
  which is a much newer thing to require of a browser than the difference is worth.
- **There is no backtracking budget here.** PCRE2 gives up on a pattern that would backtrack forever and
  raises a fault naming it; `RegExp` has no such limit in any browser, so `(a+)+$` against a subject that
  does not match stops answering rather than complaining. That is a thing a JavaScript host does not
  have.

### `slate:ws` is a CLIENT here, and the server half is what a browser cannot have

A browser has no socket, so nothing that listens can exist there: `accept` and the upgrade seam it
sits on refuse under `slate js`, because `listen` does. **What a page can have is a client**, and it
has one already — the `WebSocket` object — so that is what `open(url)` becomes here.

**It is the same `Connection` either way** and the module chooses which implementation answers.
Everything about the protocol that needs no socket is slate's on both hosts: the framing, the
masking, the fragment reassembly, the accept value and the reading of a url. What differs is only who
owns the bytes.

**`ping` refuses here, and it is the shape case rather than a missing feature.** The protocol has a
ping and the browser's object does not expose one: a page cannot write a control frame at all, the
browser answering the server's pings on the page's behalf. So `ping` says that, and a program needing
a round trip sends an ordinary message.

**A `Blob` is never handed to a program.** A browser's `message` event carries binary as a `Blob` by
default and a Blob is read *asynchronously*, which would make `onBinary` answer at some later turn
here and at once in the interpreter; the connection sets `binaryType` to `arraybuffer` on the way in.

**`hostHas(name)` is how the module asks, and it is not a name a program can write.** It is declared
into the scope a built-in module's source compiles in — the same place `sha1` and `jwsSign` live — and
answers whether the host provides a thing ITSELF, which is a different question from whether slate has
one. The interpreter answers no to all of them: it speaks WebSocket over its own socket, compresses
with miniz and fetches over OpenSSL, and in each case there is nobody else's implementation to use.

**`compression` is two globals and one question.** A host with a `CompressionStream` and no
`DecompressionStream` does not compress, so `hostHas("compression")` wants both.

### `fetch` is the host's own, and two things about it are the host's too

A browser *has* `fetch`, so this was work owed rather than something the host lacks. What had to be
written is the shaping: the host answers a `Response` and slate answers `{ ok, value }` with a
`status`, a `headers` object of lower-cased names, and a `body`. A server that cannot be reached is
`{ ok: false, error }`, never a rejection — which is `fetch`'s rule in slate whichever host answers.

**The URL is read here and not left to the host.** `gopher://x/` is a mistake neither host has
anything to do with, so both back ends answer *"`gopher://x/` is not an http or https URL"* rather
than slate's sentence in one place and the browser's in the other. That is `slate:ws`'s rule for
`open`, drawn the same way.

**`trust` refuses**, and it is the shape case rather than a missing feature. It names a certificate to
trust as well as the machine's own, and no JavaScript host lets a program add a trust anchor for one
request. A refusal is the only safe answer: a program that believes it pinned a certificate and did
not is worse off than one told it cannot.

**The redirect rule is the host's here.** The interpreter follows at most five and refuses one that
leaves `https` for `http`. A browser follows redirects itself, and `redirect: "manual"` does not hand
a page the location back — a cross-origin redirect comes back opaque, with no status and no headers
to read — so a page cannot implement that rule at all, and doing it on node alone would make the two
JavaScript hosts disagree with each other. This is `ping`'s case in `slate:ws`: the host does the
thing and gives the program no way in.

**A body that is not UTF-8 is `""` on both**, which took a decision here: a host's `text()` replaces
every bad byte with U+FFFD, so the response would come back as replacement characters here and as
`""` there. The bytes are decoded strictly instead and the failure is caught.

**A response header that repeats is joined with `", "` on both, and the interpreter changed to
match.** It used to keep the last, which silently threw one away — an object has one value per name
and HTTP does not. A `Headers` object is what a JavaScript host hands over, already combined and with
no way to ask for the lines back, so combining is the only reading both can give; RFC 9110 allows it
in as many words.

**`Set-Cookie` is excluded from that by the same section, and is a list of the lines on both.** A
cookie carries commas of its own, so a joined value cannot be taken apart again; `Headers` has
`getSetCookie()` for exactly this reason and that is what is read here. **In a browser it is absent
however many arrived** — `Set-Cookie` is a forbidden response-header name and a page never reads one,
though the browser still applies the cookie. That is `ping`'s case again: the host does the thing and
gives the program no way in.

Which response headers are readable at all in a browser is CORS's decision and not slate's.

## A builtin is a parameter, not a name taken from the host

**The emitted program is a function whose parameters are the builtins**, applied to the runtime's own
table. It is not a script that installs two hundred names into the host's global scope, which is what
it used to be.

That change is a browser-parity decision rather than a tidying. A page's other scripts and the
browser's own APIs share `setTimeout`, `fetch` and `close`; a slate program that took those names took
them from everybody, for as long as the page lived. **node's own `WebSocket` is what found it**: its
handshake calls `setTimeout` and calls `.unref()` on what comes back, and slate answers its own
integer id — which has no such method, so the socket never opened and nothing anywhere named a timer.

**A program may still declare a name a builtin has.** The builtins are the outer function's parameters
and the program is an inner function, so `val print = 1` shadows exactly as it did when the names were
globals — two scopes are what keeps that from being a redeclaration.

**The names come from the same scope the interpreter's builtins are installed into**, so a builtin
added to the language is a parameter on the next build and there is no second list to go stale.

## Blocks and order

JavaScript has no block expression, so `val x = if c then 1 else 2` becomes an `if` statement over a
temporary. **An immediately-called function would have been the other way and is wrong**: `return`,
`break`, `await` and `yield` all mean the enclosing function, and a wrapper takes every one of them away.
The one place a wrapper is written is a default parameter, where there is no statement position to hoist
into and nothing of the enclosing function to lose.
