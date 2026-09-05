# Values

slate is dynamically typed. Every value is one of a fixed set of kinds, and a program can ask which.

## The kinds

| kind | written | notes |
|---|---|---|
| `null` | `null` | the only absence there is |
| `boolean` | `true`, `false` | |
| `integer` | `42`, `0xff` | 64 bits, signed, wraps |
| `real` | `3.14`, `2e10` | a double |
| `string` | `"text"` | a sequence of **characters**, never of bytes |
| `array` | `[1, 2]` | reference type, compares by contents |
| `object` | `{ a: 1 }` | reference type, compares by contents |
| `function` | `x -> x`, a definition | |
| promise | answered by an `async` call | see [Asynchrony](asynchrony.md) |

Eight more scalar kinds come with [`slate:time`](../library/time.md) — `instant`, `duration`, `date`,
`time`, `dateTime`, `zone`, `zoned`, `period` — and a compiled pattern comes with
[`slate:regex`](../library/regex.md). Each has a type word that tests for it in
[pattern position](patterns.md).

**`number` is not a kind.** It is the union of `integer` and `real`, and exists because the two are
separate values: a guard about arithmetic would otherwise have to be written twice.

## Truth

**Only `false` and `null` are false.** Zero, the empty string and the empty array are all true.

```slate
print(if 0 then "true" else "false")
print(if "" then "true" else "false")
print(if [] then "true" else "false")
```

```output
true
true
true
```

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

A [class](classes.md) may take `==` over for its own instances by writing `equals`, and must write
`hash` beside it if those instances are to be used as table keys. `<`, `<=`, `>` and `>=` are one hook,
`compare` — see [Objects](objects.md).

## Numbers

**An integer is 64 bits and wraps**; it does not promote to a real and does not become a big integer.

```slate
print(9223372036854775807 + 1)
print(1 << 40)
```

```output
-9223372036854775808
1099511627776
```

**`/` between two integers divides towards zero** and answers an integer; `%` takes the sign of the
left operand. Where either operand is a real the answer is a real.

```slate
print(7 / 2, 7.0 / 2, -7 / 2)
```

```output
3 3.5 -3
```

**A real that is whole prints as an integer does.** `string(1.0)` is `"1"`. Only `%`, indexing, or a
kind test can tell the two apart, so a function that must answer an integer is worth annotating.

## Strings

**A slate string is a sequence of characters**, so every position, length and slice is counted the way
a person counts:

```slate
print(len("日本語"))
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

`toBytes(s)` answers an array of numbers and `fromBytes(bs)` answers a [result](faults.md); those two
are the only place a slate program sees UTF-8, and `len(toBytes(s))` is the byte count.

**Case and whitespace are the whole database and not the ASCII range.** `upper` and `lower` answer
what any other language with a case table answers, which is not always one character out for one
character in, and `trim` takes off Unicode's `White_Space` — so a no-break space pasted out of a form
comes off and a zero-width no-break space, which is not a space at all, stays.

```slate
print(upper("Straße"), len(lower("İ")))
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

## Reference and copy

Arrays and objects are reference types: two names may hold the same array, and a write through one is
visible through the other. Everything else is a scalar.

`a with { f: v }` answers a **copy** of `a` with `f` changed, which is how a record is updated without
mutating it. `concat(xs, ys)` is the array counterpart.

## Absence

**There is no `undefined`.** `null` is the only absence, it is an ordinary value, and slate refuses to
store anything else in its place. That single rule explains a run of behaviour that otherwise looks
unrelated:

- `pop`, `shift` and `at` **fault** where there is nothing there, rather than answering nothing.
- `find` and `indexOf` answer **`null`** — a search that found nothing is an answer, where reaching
  past the end is a mistake.
- A parameter nobody gave is **not bound at all**, so there is no sentinel to test for and
  `f(1, null)` is not the same as `f(1)`.
- An object field a value need not have is a question about its [shape](types.md) (`pinned?`), not a
  value that might be absent.
