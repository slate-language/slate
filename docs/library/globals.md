---
title: Globals
weight: 10
---

# Globals

The names a program has in scope with no import.

## Printing and tests

| | |
|---|---|
| `print(…)` | any number of values, separated by a space |
| `assert(condition)`, `assert(condition, message)` | raises where the condition is false |
| `assertEq(got, wanted)` | renders both sides, quoting a string |

The two assertions raise rather than answer, because a failed assertion is not a condition the test was
going to handle. See [Tests](../reference/tests.md).

## Kinds and conversions

`string  number  integer  real  boolean`

**The type words are the conversions**, and the same word [tests in a pattern](../reference/patterns.md).
An array, a string and a range each answer `.length`; an object counts its own keys through
`keys(o).length` instead, `.length` being a [property](../reference/values.md) of arrays, strings and
ranges and not of objects.

```slate
print(string(123) + "!")
print(number("42"), number("nonsense"))
print(integer(2.9))
print(boolean(0))           // only false and null are false
print("日本語".length)        // in characters
```

```output
123!
42 null
2
true
3
```

## Text

`chars  split  join  contains  includes  indexOf  lastIndexOf  startsWith  endsWith`
`trim  trimStart  trimEnd  upper  lower  normalize  casefold  replace  replaceAll  repeat`
`padStart  padEnd`

Every position is **in characters**, never in bytes.

- **`indexOf` answers `null`** rather than `-1`, because slate has a null and the operators that go with
  it: `indexOf(s, x) ?? 0` says what a sentinel makes a reader work out.
- **A search may be told where to start.** `indexOf(s, x, from)` and `lastIndexOf(s, x, from)` take a
  third position, and a negative one counts back from the end.
- **`split` on an empty separator splits into characters.**
- **Case is the whole Unicode database**, so `upper("Straße")` is `STRASSE` and `lower("ΟΔΟΣ")` ends in
  a final sigma. A case mapping may change a string's length; both back ends answer the same thing.
- **`trim` is Unicode's `White_Space`**, so a no-break space comes off and a zero-width no-break space
  — which the database does not call a space — stays.
- **`normalize(s, form)` takes one of `"NFC"`, `"NFD"`, `"NFKC"` and `"NFKD"`** and faults on anything
  else rather than falling to a default.
- **`casefold` is not `lower`.** It is the key to store beside a name somebody will search for: `ß`
  folds to `ss`, folding is idempotent, and what it answers is composed.
- **`includes` is `contains` and `replaceAll` is `replace`, under the names JavaScript gave them.**
  `replace` has always changed every occurrence, so `replaceAll` is not a second behaviour — the
  JavaScript habit of reaching for the "all" name is simply right here.
- **`padStart` and `padEnd` bring a string up to a width, in characters.** The filler REPEATS and is
  cut to fit, so `padStart("7", 5, "ab")` is `"abab7"`; a string already at or past the width is
  answered unchanged.

```slate
print(upper("Straße"), lower("ΟΔΟΣ"))
print(casefold("STRASSE") == casefold("Straße"), lower("STRASSE") == lower("Straße"))
print(normalize("e\u{301}", "NFC") == "é")
print(padStart("7", 3), padEnd("7", 3, "0"))
print(replaceAll("a,b,c", ",", "-"), includes("hello", "ell"))
```

```output
STRASSE οδος
true false
true
  7 700
a-b-c true
```

**`length` is a property, not a method** — `s.length` counts characters, never UTF-16 units, so
`"a👋".length` is 2. Writing to it is refused.

As methods, a string answers: `chars split contains includes indexOf lastIndexOf startsWith
endsWith trim trimStart trimEnd upper lower normalize casefold replace replaceAll repeat padStart
padEnd number integer real boolean string`.

## Numbers

`abs  floor  ceil  round  trunc  sqrt  pow  min  max  toFixed  formatNumber`

- **The four roundings leave an integer alone**, an integer already being whole.
- **`min` and `max` take as many arguments as they are given** and answer an integer when every one of
  them was — a `min` that answered a real for two integers would make every use of it in an index a
  conversion.
- `pow` of two integers with a non-negative exponent answers an **integer**.
- **`toFixed(x, places)` writes a number to exactly that many decimal places, as text.** It is
  byte-identical with JavaScript's, ties included: a tie rounds AWAY from zero, which is not what
  C's `printf` does.
- **`formatNumber` groups the digits in threes**, taking a whole number or the text `toFixed`
  answered — never a `real`, which has no one written form of its own. `formatNumber(toFixed(total,
  2))` is a price. The defaults are a comma and a full stop; `{ separator: " ", decimal: "," }` is
  the French convention, said with the same two strings rather than a locale name.

```slate
print(toFixed(1234.5, 2), toFixed(2.5, 0))
print(formatNumber(1234567), formatNumber(toFixed(1234.5, 2)))
print(formatNumber(toFixed(1234.5, 2), { separator: " ", decimal: "," }))
```

```output
1234.50 3
1,234,567 1,234.50
1 234,50
```

As methods, a number answers: `abs floor ceil round trunc sqrt integer real boolean string toFixed
formatNumber`.

## Arrays

`push  pop  shift  unshift  insert  removeAt  clear`
`map  filter  flatMap  forEach  reduce  find  findIndex  findLast  findLastIndex  every  some`
`sort  sorted  reverse  reversed  slice  at  concat  flat  sum  join  contains  indexOf  lastIndexOf`

```slate
print([4, 1, 3, 2].sorted().slice(1, 3).flatMap(n -> [n, n]).at(-1))
print([1, 2, 3].sum(), [1, [2, [3]]].flat())
print(indexOf([1, 2], 9), find([1, 2, 3], n -> n > 1))
print([1, 2, 3].at(-1), [1, 2, 3].reversed())
```

```output
3
6 [1, 2, [3]]
null 2
3 [3, 2, 1]
```

**`length` is a property and not a method**, so it is read with no brackets after it — `xs.length` is
`xs.length`, and writing to it is refused rather than resizing the array:

```slate
print([1, 2, 3].length, [].length)
print(map(["a", "bb"], _.length))
```

```output
3 0
[1, 2]
```

Where slate parts from JavaScript it is **to remove a case rather than add one**:

- **A mutator answers nothing**, so `sort` and `unshift` cannot be mistaken for the copying forms
  `sorted` and `concat`. The bare verb changes the array and the participle answers a new one.
- **Nothing answers absence.** `pop`, `shift` and `at` **fault** where there is nothing there, while
  `find` and `indexOf` answer **`null`** — a search that found nothing is an answer, and reaching past
  the end is a mistake.
- **`at` and `slice` count back from the end** where the position is negative, which is the whole reason
  JavaScript grew `at` beside `xs[i]`.
- **A comparator answers a number** whose sign orders the pair, as a class's `<=>` does.

## Objects

`keys  values  entries  has  without`

```slate
val o = { a: 1, b: 2 }

print(keys(o), values(o), has(o, "a"))
print(without(o, "a"), o)

for [k, v] in entries(o)
    print(k, v)
```

```output
["a", "b"] [1, 2] true
{b: 2} {a: 1, b: 2}
a 1
b 2
```

**`without` answers a NEW object**, which is `with`'s rule read the other way: a slate object's shape
is not a thing one name changes under another's feet. A key that is not there is not an error, so a
table forgetting something it is unsure of is one line — and a copy of a [data value](../reference/data-types.md)
is a data value, as `with`'s is.

**A `proto` a declaration wrote is not a field these report.** A class instance and a data variant
reach what they are through it, so `keys`, `values`, `entries`, `has` and `without` all pass over it —
which is what `print` has always done. A `proto` a *program* wrote on a plain object is an ordinary
field and is reported like any other.

An object answers **no** methods of its own — its names belong to the program, and a builtin `o.keys`
would give every object a field nothing put there. The [four universal methods](README.md) are the
exception, and a field the program wrote wins over those.

## JSON

| | |
|---|---|
| `parseJSON(text)` | a **result** |
| `toJSON(v)`, `toJSON(v, indent)` | a string; **faults** where the value has no JSON form |

**The two directions use the two channels**, and they genuinely differ: text from a file, a socket or a
person is a condition every caller was going to handle, and a function or a circle in a value the program
built itself is a defect in that program. `JSON.parse` and `JSON.stringify` both throw, so node treats the
two alike.

- **A value with no JSON form is named rather than dropped.** `JSON.stringify` drops a function silently
  from an object and turns it into `null` inside an array, so a request body goes out with a field missing
  and nothing says which.
- **A non-string key is refused**, rendering it as text would make `{ 1: "a" }` and `{ "1": "a" }` one
  document.
- **A class says what it encodes as with `toJSON(self)`** — see [Objects](../reference/objects.md).
- **The parse error is the whole rendering**, not one sentence. A JSON document is usually
  machine-written and long, so *"expected a string"* on its own says nothing a person can act on.

## Bytes

| | |
|---|---|
| `toBytes(s)` | an array of numbers |
| `fromBytes(bs)` | a **result** — arbitrary bytes are not text |

`toBytes(s).length` is the byte count, so there is no third name. These are the one place a slate program
sees UTF-8, and two things need them: a `Content-Length`, and a read where a character may be split across
two arrivals.

Bytes are an array of numbers, so they carry the same `length` any array does — there is no third kind
here either:

```slate
print(toBytes("héllo").length, toBytes("héllo").length)
```

```output
6 6
```

## Timers

`setTimeout(fn, ms)  setInterval(fn, ms)  clearTimeout(id)  clearInterval(id)`

The callback comes first, which is node's order. Both `ms` forms also take a
[duration](time.md). **A timer keeps the program alive.**

## Promises

`sleep  resolve  reject  pending  settle  fail`
`all  allSettled  race  any`

See [Asynchrony](../reference/asynchrony.md).

**The four that wait on many promises at once**, which `await` cannot be written to do by itself: it
starts the second one only once the first has come back.

- **`all` answers every value in the order given**, a plain value in the array being one that has
  already arrived — a cache hit sits beside a `fetch` without being dressed up as a promise. It fails
  with the first rejection in that same order, and `all([])` answers `[]`.
- **`allSettled` answers the RESULT shape slate already has** — `{ ok: true, value }` or
  `{ ok: false, error }`, the same shape `parseJSON`, every `Sync` call in `slate:fs` and `run`
  already answer — and not JavaScript's `{ status, value | reason }`.
- **`race` answers whichever one settles first**, success or failure.
- **`any` answers the first to succeed**, past any number of failures, and fails only where every one
  did — with every reason, since a slate rejection carries text and there is nothing for an
  `AggregateError` to be.
- **`race([])` and `any([])` are refused rather than answered** with a promise that never settles,
  which is what JavaScript does and is a program that hangs.

```slate
async first(ms, label)
    await sleep(ms)
    label

async main()
    print(await all([1, resolve(2), 3]))
    print(await allSettled([resolve(1), reject("bad")]))
    print(await race([first(20, "slow"), first(5, "fast")]))
    print(await any([reject("no"), resolve("yes")]))

main()
```

```output
[1, 2, 3]
[{ok: true, value: 1}, {ok: false, error: "bad"}]
fast
yes
```

## Generators

`next(g)`, which is `g.next()` — see [Asynchrony](../reference/asynchrony.md).

## `host`

```slate
print(host())
```

```output
interpreter
```

**Which of the three hosts this program is running on, constant for the life of a program.** These
pages run on the interpreter, so that is what prints above; the same call answers `"node"` under
`slate js` run with node, and `"browser"` in a browser. It takes no arguments and refuses one that
takes any.

**A shared file is the reason this exists.** A component with no control over where it runs cannot
otherwise tell a browser-only call from one that will fault everywhere else — see
[the DOM](dom.md) for the case that asked for it.

## `fetch`

```slate
val r = await fetch(url, options)
```

node's name and the browser's, and it **answers a result** rather than throwing — which is slate's rule
for anything that reaches the network, not a disagreement with either. It is native because HTTPS needs
OpenSSL; the *server* half is [`slate:http`](http.md) and is written in slate.

**It works on both back ends**, over the host's own `fetch` under `slate js` — a status, a headers
object with lower-cased names, and a body. Nothing in this file says *"not in the JavaScript back end
yet"* any more.

Two things differ there and [JavaScript](../reference/javascript.md) says why: **`trust` refuses**,
no JavaScript host letting a program add a certificate authority for one request, and **the redirect
rule is the host's** — the interpreter follows at most five and refuses one that leaves `https` for
`http`, where a browser follows them itself and gives a page no way in.

**A response header that repeats is joined with `", "`**, on both. An object has one value per name
and HTTP does not: `Link`, `Vary` and `Via` all repeat, and combining them is what RFC 9110 allows
and what a browser's `Headers` hands over already done.

**`Set-Cookie` is the exception and is a LIST**, of the lines as they arrived, absent when there were
none. The same section of RFC 9110 excludes it and the reason is arithmetic: a cookie carries commas
inside itself — `Expires=Wed, 21 Oct 2026 07:28:00 GMT` — so two cookies joined by commas cannot be
taken apart again by anything. In a browser it is absent however many arrived: `Set-Cookie` is a
forbidden response-header name, so a page never reads one. The browser still applies the cookie.

**A body that is not UTF-8 is `""`** rather than a string of replacement characters, which is the same
answer `run` gives and for the same reason: slate has no byte value for it to be.

**In a browser a relative URL is resolved against the page's own address**, so `fetch("/signup")`,
`fetch("./next")` and `fetch("../up")` all reach the origin the page was served from — the resolving is
`new URL(url, location.href)`, which is what the platform's own `fetch` does with one. **Under node and
the interpreter there is no page**, so the same call is refused and says so: *"`/signup` is not an http
or https URL, and there is no page to resolve it against"*. A URL naming a scheme slate does not speak
keeps the plain sentence, a base being no help to it.
