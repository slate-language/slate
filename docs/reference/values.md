---
title: Values
weight: 20
---

# Values

slate is dynamically typed. Every value is one of a fixed set of kinds, and a program can ask which.

## The kinds

| kind | written | notes |
|---|---|---|
| `null` | `null` | the only absence there is |
| `boolean` | `true`, `false` | |
| `integer` | `42`, `0xff` | signed, no width — it grows rather than wrapping |
| `real` | `3.14`, `2e10` | a double |
| `string` | `"text"` | a sequence of **characters**, never of bytes |
| `array` | `[1, 2]` | reference type, compares by contents |
| `bytes` | `bytes([1, 2])`, `toBytes(s)` | reference type, compares by contents — [Bytes](../library/bytes.md) |
| `object` | `{ a: 1 }` | reference type, compares by contents |
| `function` | `x -> x`, a definition | |
| promise | answered by an `async` call | see [Asynchrony](asynchrony.md) |
| `set` | `Set([1, 2])` | reference type, holds each value once — [Collections](collections.md) |
| `map` | `Map([["a", 1]])` | reference type, any value as a key — [Collections](collections.md) |

A set and a map compare by **identity** rather than by contents, as a promise and a function do:
what is in either can change, so an answer read off the contents would stop being true without
either value being touched by the code that asked.

Eight more scalar kinds come with [`slate:time`](../library/time.md) — `instant`, `duration`, `date`,
`time`, `dateTime`, `zone`, `zoned`, `period` — and a compiled pattern comes with
[`slate:regex`](../library/regex.md). Each has a type word that tests for it in
[pattern position](patterns.md).

**`number` is not a kind.** It is the union of `integer` and `real`, and exists because the two are
separate values: a guard about arithmetic would otherwise have to be written twice.

## Truth

**slate follows JavaScript's rule.** `false`, `null`, an absent value, `0` (and `-0`), `NaN` and `""`
are false; everything else is true — including `[]`, `{}`, `"0"` and an empty `bytes` buffer, which
is an object in JS terms and stays true however long it is.

```slate
print(if 0 then "true" else "false")
print(if "" then "true" else "false")
print(if [] then "true" else "false")
```

```output
false
false
true
```

**`??` is unchanged and asks a different question.** It tests whether a value is *absent*, not
whether it is true — zero and the empty string are values, not absences, so `0 ?? 5` is still `0`
and `"" ?? "d"` is still `""`. See [Logic](expressions.md#logic).

## Equality

`==` compares **by value, all the way down**. Two arrays holding the same elements are equal; two
objects holding the same fields are equal.

```slate
print([1, 2] == [1, 2], { a: 1 } == { a: 1 })
```

```output
true true
```

**An integer and a real compare across the kinds**, so `1 == 1.0` is true — but `1 is integer` and
`1.0 is integer` still differ, the two being distinct values that happen to compare equal.

**A function is equal to itself.** `f == f` is true, and two separately written lambdas with the same
body are not equal.

**There is one special case, and it is the two absences: `null == undefined` is true.** So `x == null`
and `x == undefined` are the same question — *is this absent, either way* — and `!=` is its negation.
A field holding `null` and a field that is not there are still two different things, and
[`has`](objects.md) is what asks which one you have.

```slate
val o = { a: 1, b: null }

print(o.b == null, o.nope == null, o.b == undefined)
print(null == 0, null == false, undefined == "")
print(has(o, "b"), has(o, "nope"))
```

```output
true true true
false false false
true false
```

**Nothing else of JavaScript's loose equality comes with it**, which is why there is no `===` to
escape back to. `null == 0`, `null == false` and `undefined == ""` are all false, and `==` is strict
about every other pair of kinds. The `== null` idiom is taken deliberately because a read that found
nothing is almost always to be handled the same way whichever kind of nothing it was; where it is
not, `has` draws the line.

A [class](classes.md) may take `==` over for its own instances by writing a method called `==`, and
must write `hash` beside it if those instances are to be used as table keys. `!=` is always the
opposite of `==` and may not be written. `<`, `<=`, `>` and `>=` are each a method of their own, or
all four at once as `<=>` — see [Objects](objects.md).

## Numbers

**An integer never wraps: it grows.** There is no largest integer and no smallest one, and no
arithmetic on two integers ever answers a number other than the one it means. Python's rule, and the
64-bit machine word is a fast path with nothing about it a program can see.

```slate
print(9223372036854775807 + 1)
print(1 << 100)
print(pow(2, 100))
```

```output
9223372036854775808
1267650600228229401496703205376
1267650600228229401496703205376
```

A factorial is the number rather than a remainder of it:

```slate
factorial(n)
    var f = 1

    for i in 1..n
        f = f * i

    f

print(factorial(30))
```

```output
265252859812191058636308480000000
```

**A wide integer is an integer and nothing else.** `is integer` is true of one, `==` compares the
numbers, `string` gives the digits and a literal is read at whatever width it was written at — in
any base, with separators if you like.

```slate
print(123456789012345678901234567890 is integer)
print(0xffffffffffffffffffff)
print(1_000_000_000_000_000_000_000_000)
print((1 << 100) - (1 << 100) + 5)
```

```output
true
1208925819614629174706175
1000000000000000000000000
5
```

That last line is worth reading twice: a number that grew and came back is **the same value** as one
that never left, so it compares equal to `5`, hashes as `5` does, and finds an entry a table holds
under `5`. Nothing in the language distinguishes the two.

**The bit operations read a value as an endless run of bits** — a non-negative number padded upward
with zeros and a negative one with ones — which is the only reading that needs no width to
complement within. So `~x` is `-x - 1`, `<<` grows rather than discarding, and `>>` floors toward
negative infinity: past the top of a number it answers `-1` for a negative and `0` for anything
else.

```slate
print(~5, -6 & 3, -6 | 3, -6 ^ 3)
print(1 << 100 >> 99, -1 >> 200, 7 >> 200)
```

```output
-6 2 -5 -7
2 -1 0
```

**A shift is bounded at 16,777,216 places and `pow` at an answer of that many bits.** Neither is a
width; they are the point at which slate says so rather than letting the allocator give up.

**Where a call genuinely needs a machine integer — an array index, a `repeat` count, a byte — a
number too wide for one is refused, and the refusal says so.**

```slate
print([1, 2, 3][pow(10, 30)])
```

```error
an array is indexed by an integer, and this is an integer too large to fit 64 bits
```

**An integer and a real are compared exactly and their arithmetic promotes**, which is Python's rule
and is two answers to two different questions. `big + 0.5` has no answer in the integers, so it is a
real; `big < 0.5` has an exact answer always, and rounding the integer to a double first would make
numbers a million apart compare equal. `1e30` is not the number `10 ^ 30` — it is the nearest double
to it — and this says so:

```slate
print(pow(10, 30) == 1e30)
print(pow(10, 30) < 1e30)
print(integer(1e30))
print(pow(10, 30) + 0.5 is real)
```

```output
false
true
1000000000000000019884624838656
true
```

**A wide integer goes through JSON as its digits**, JSON's own grammar bounding a number at nothing.
Reading them back grows the number again rather than rounding it to the nearest double, so a
document carries what it was given; and an exponent is still a real however large it is, which is
what keeps the two kinds apart across a round trip.

```slate
val doc = { n: pow(10, 30), scale: 1e30 }
val back = parseJSON(toJSON(doc)).value

print(toJSON(doc))
print(back.n == pow(10, 30))
print(back.scale is real)
```

```output
{"n":1000000000000000000000000000000,"scale":1e+30}
true
true
```

**`/` ANSWERS A REAL, ALWAYS — even between two integers, and even where the division comes out
exact.** `7 / 2` is three and a half, and `4 / 2` is a whole *real* rather than the integer 2. The
kind of the answer does not depend on the kinds of the operands, which is the whole of the rule:
nothing has to work out whether a division came out evenly before it knows what it is holding. It is
Python 3's rule and JavaScript's, and a wide integer reaches it the same way, through `toReal` —
which may be an infinity for a number past what a double can name.

**`\` IS THE WHOLE-NUMBER DIVISION**, and it takes two integers and answers an integer. It is
spelled with a backslash because `//` already opens a comment in slate; the spelling is Visual
Basic's. Inside a string literal a backslash is still the escape it always was, the lexer reading a
string on its own.

**`\` truncates toward zero and `%` takes the sign of the left operand**, and those two facts are one
fact: `a == (a \ b) * b + a % b` holds for every pair, and it holds *only* for the truncating
division. A flooring `\` would need a flooring `%` beside it, which is Python's pairing and not
slate's.

```slate
print(7 / 2, 7 \ 2, -7 \ 2, -7 % 2)
print(4 / 2, 4 / 2 is integer)
print(-7 == (-7 \ 2) * 2 + (-7 % 2))
```

```output
3.5 3 -3 -1
2 false
true
```

**By zero the two behave differently, and that follows from the first rule rather than being an
exception to it.** `/` is a real division wherever it appears, so `1 / 0` is the infinity `1.0 / 0.0`
has always been; `\` and `%` are whole-number operators and fault, on both back ends.

```slate
print(1 / 0, -1 / 0, 0 / 0)
print(1 \ 0 catch e -> e.message)
```

```output
Infinity -Infinity NaN
this divides by zero
```

**`\` is of integers and refuses a real**, where `/` takes anything numeric. `\=` is its compound
form, beside `/=`, and it binds at the `*` `/` `%` power.

**A real that is whole prints as an integer does.** `string(1.0)` is `"1"`. Only `%`, indexing, or a
kind test can tell the two apart, so a function that must answer an integer is worth annotating.

**Otherwise a real prints the shortest text that reads back as the same double**, exactly as
JavaScript's own `String` does — so `0.1 + 0.2` prints `0.30000000000000004` rather than rounding to
a tidy `0.3` a program is not actually holding, and `number(string(x))` is always `x` again.

## Strings

**A slate string is a sequence of characters**, so every position, length and slice is counted the way
a person counts:

```slate
print("日本語".length)
print("日本語"[0..<1])
print("héllo"[1])
print(indexOf("héllo", "llo"))      // by character; it is 3 by byte
```

```output
3
日
é
2
```

There is no character type: a single character is a string of one. That is what lets indexing, `chars`
and `split` all hand back the same kind of thing.

**`s.at(i)` reads one character and counts back from the end where the position is negative**, which
is what `xs.at(-1)` is for an array and is the whole reason JavaScript grew `at` beside `s[i]`. It
counts characters like everything else here, and a position past either end is a **fault** rather
than an absence, slate storing no `undefined` for such a read to hand back.

**A `for` walks a string's characters**, which is `chars(s)` without the array in the middle:

```slate
print("a👋b".at(-1), "a👋b".at(1))

for c in "a👋"
    print(c)
```

```output
b 👋
a
👋
```

**`.length` is that count read as a property** — a name a `.` answers with a value and no brackets
after it, exactly as a class's `get` is read. `s.length` counts characters and not UTF-16 units, so
a string of one emoji is 1 here where JavaScript says 2. An array carries one too, and so does a
[buffer](../library/bytes.md), which is the shape the bytes under a string come back in.

```slate
print("日本語".length, "a👋".length)
print([1, 2, 3].length, toBytes("héllo").length)
```

```output
3 2
3 6
```

**It is read-only.** A length is what a value already is rather than a field it holds, so writing to one
is refused instead of resizing anything:

```slate
var s = "abc"

s.length = 5
```

```error
`length` is a read-only property of a string
```

`toBytes(s)` answers a [buffer](../library/bytes.md) and `fromBytes(bs)` answers a [result](faults.md); those two
are the only place a slate program sees UTF-8, and `toBytes(s).length` is the byte count.

**Case and whitespace are the whole database and not the ASCII range.** `upper` and `lower` answer
what any other language with a case table answers, which is not always one character out for one
character in, and `trim` takes off Unicode's `White_Space` — so a no-break space pasted out of a form
comes off and a zero-width no-break space, which is not a space at all, stays.

```slate
print(upper("Straße"), lower("İ").length)
print(lower("ΟΔΟΣ"), lower("ΟΔΟΣΑ"))
print("[" + trim(" \u{a0}x\u{a0} ") + "]")
```

```output
STRASSE 2
οδος οδοσα
[x]
```

The second line is Unicode's own rule that a sigma ending a word is written `ς`, which is context
rather than a table; the first is `ß` uppercasing to two letters and `İ` lowercasing to two.

`normalize(s, form)` puts text into one of `"NFC"`, `"NFD"`, `"NFKC"` and `"NFKD"`, which is what two
strings have to go through before `==` between them means what a reader thinks it means — the same
word typed on two machines is routinely two different sequences of characters. `casefold(s)` is what
two strings differing only in case both come to, and is **not** `lower`: `ß` folds to `ss`, so
`casefold("STRASSE") == casefold("Straße")` where lowering leaves them different.

## Conversion

**The type words are the conversions.** `string`, `number`, `integer`, `real` and `boolean` each test
in pattern position and convert in expression position; the two never overlap.

```slate
print(string(123) + "!")
print(number("42"), number("nonsense"))
print(integer(2.9), real(3), real(3) is real)
```

```output
123!
42 null
2 3 true
```

`number` answers `null` where the text is not a number, which is how a program checks input without
raising. `integer` and `real` move between the two numeric kinds; the four roundings — `floor`,
`ceil`, `round`, `trunc` — leave an integer alone.

`min` and `max` take as many arguments as they are given and answer an **integer when every one of
them was**.

**`bytes` is the one word that is a kind and a constructor without being a conversion of a value.**
`bytes(n)` makes a buffer of `n` zero bytes rather than reading `n` as one; the conversions between
text and bytes are `toBytes` and `fromBytes`, since each needs an encoding named or defaulted. See
[Bytes](../library/bytes.md).

## Reference and copy

Arrays, buffers of bytes and objects are reference types: two names may hold the same one, and a write
through one is visible through the other. Everything else is a scalar.

`a with { f: v }` answers a **copy** of `a` with `f` changed, which is how a record is updated without
mutating it. `concat(xs, ys)` is the array counterpart.

## Absence

**`null` is the only absence a program can keep**, it is an ordinary value, and slate refuses to store
anything else in its place — `undefined` exists only as the immediate answer to a read that found
nothing, or to a `yield` a bare [`next()`](asynchrony.md#generators) resumed, and [compares equal to `null`](#equality). That single rule explains a run of behaviour that
otherwise looks unrelated:

- `pop`, `shift` and `at` **fault** where there is nothing there, rather than answering nothing.
- `find` and `indexOf` answer **`null`** — a search that found nothing is an answer, where reaching
  past the end is a mistake.
- A parameter nobody gave reads as the absence a missing field does, so `f(1, null)` is not the same
  as `f(1)` — and like a missing field it can be read but not kept.
- An object field a value need not have is a question about its [shape](types.md) (`pinned?`), not a
  value that might be absent.

Keeping one is refused where it is attempted — binding it to a `val`, a `var` or a `for` head,
writing it over a local, storing it in a field, an array or an object, or passing it to a function —
and in the same words under `slate js`:

```slate
val settings = { port: 8080 }
val host = settings.host

print(host)
```

```error
this field is not there, and `undefined` cannot be bound to `host` -- give it a value with `??`, or ask `has` first
```

`settings.host ?? "localhost"` is the program that runs.
