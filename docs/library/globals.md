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

`string  number  integer  real  boolean  len`

**The type words are the conversions**, and the same word [tests in a pattern](../reference/patterns.md).

```slate
print(string(123) + "!")
print(number("42"), number("nonsense"))
print(integer(2.9))
print(boolean(0))           // only false and null are false
print(len("日本語"))        // in characters
```

```output
123!
42 null
2
true
3
```

## Text

`chars  split  join  contains  indexOf  lastIndexOf  startsWith  endsWith`
`trim  trimStart  trimEnd  upper  lower  normalize  casefold  replace  repeat`

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

```slate
print(upper("Straße"), lower("ΟΔΟΣ"))
print(casefold("STRASSE") == casefold("Straße"), lower("STRASSE") == lower("Straße"))
print(normalize("e\u{301}", "NFC") == "é")
```

```output
STRASSE οδος
true false
true
```

As methods, a string answers: `len chars split contains indexOf lastIndexOf startsWith endsWith trim
trimStart trimEnd upper lower normalize casefold replace repeat number integer real boolean string`.

## Numbers

`abs  floor  ceil  round  trunc  sqrt  pow  min  max`

- **The four roundings leave an integer alone**, an integer already being whole.
- **`min` and `max` take as many arguments as they are given** and answer an integer when every one of
  them was — a `min` that answered a real for two integers would make every use of it in an index a
  conversion.
- `pow` of two integers with a non-negative exponent answers an **integer**.

As methods, a number answers: `abs floor ceil round trunc sqrt integer real boolean string`.

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

Where slate parts from JavaScript it is **to remove a case rather than add one**:

- **A mutator answers nothing**, so `sort` and `unshift` cannot be mistaken for the copying forms
  `sorted` and `concat`. The bare verb changes the array and the participle answers a new one.
- **Nothing answers absence.** `pop`, `shift` and `at` **fault** where there is nothing there, while
  `find` and `indexOf` answer **`null`** — a search that found nothing is an answer, and reaching past
  the end is a mistake.
- **`at` and `slice` count back from the end** where the position is negative, which is the whole reason
  JavaScript grew `at` beside `xs[i]`.
- **A comparator answers a number** whose sign orders the pair, as `compare` does.

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
reach what they are through it, so `keys`, `values`, `entries`, `has`, `len` and `without` all pass
over it — which is what `print` has always done. A `proto` a *program* wrote on a plain object is an
ordinary field and is reported like any other.

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

`len(toBytes(s))` is the byte count, so there is no third name. These are the one place a slate program
sees UTF-8, and two things need them: a `Content-Length`, and a read where a character may be split across
two arrivals.

## Timers

`setTimeout(fn, ms)  setInterval(fn, ms)  clearTimeout(id)  clearInterval(id)`

The callback comes first, which is node's order. Both `ms` forms also take a
[duration](time.md). **A timer keeps the program alive.**

## Promises

`sleep  resolve  reject  pending  settle  fail`

See [Asynchrony](../reference/asynchrony.md).

## Generators

`next(g)`, which is `g.next()` — see [Asynchrony](../reference/asynchrony.md).

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
