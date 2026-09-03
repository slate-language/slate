# `slate:regex`

PCRE2 patterns. **One export, because a pattern is one object and everything a program does with it is a
method on that object.**

```
import { regex } from slate:regex

val re = regex("(\\d+)-(\\d+)", "i")

print(re.test("10-20"))
print(re.find("x 10-20 y").groups)          // ["10-20", "10", "20"]
print(re.findAll(text))
print(re.replace(text, "$2-$1"))
print(re.replaceFirst(text, "x"))
print(re.split(text))
print(re.pattern(), re.flags())
```

The flags are `i`, `m`, `s` and `x`.

## A match is an ordinary object

`text`, `start`, `end`, `groups` and `named`.

- **`groups` has the whole match at 0**, and **`null`** for a group that took no part.
- **`named` is always present and empty where the pattern names nothing.** A field that appears only
  sometimes is one a program must test for before reading.
- **Every offset is in characters**, as everywhere else in slate — PCRE2 answers in bytes and the whole
  slot array is converted in one pass.

## Three of JavaScript's decisions are reversed

| slate | JavaScript, and what it costs |
|---|---|
| **a pattern carries no position** | a `/g` pattern holds a mutable `lastIndex`, so `re.test(s)` twice on one string is `true` then `false` — visible only on the second call |
| **`replace` replaces every match**, `replaceFirst` stops | a bare `replace` changes the first only unless `/g` is set, which is why `replaceAll` had to be added two decades later |
| **a match that would backtrack forever is a fault** | no limit at all, so a crafted subject stops a server answering |

**There is no `g` flag**, and asking for one is refused *by name* with the sentence saying what to do
instead — a flag silently ignored would make `replace` look like it had worked for the wrong reason.

## Two dialect points

**`$` is the very end** rather than also the position before a final newline, and **`\d` is `[0-9]`**
rather than every decimal digit in Unicode. Those are the two places PCRE2 and JavaScript disagree
silently: both compile either way and merely match something else. A program wanting Unicode digits writes
`\p{Nd}`, which works regardless.

## Equality

**An identical pattern compiles once**, so `regex("a") == regex("a")` is **true** where two arrays written
the same way are equal by contents but two compiled patterns would not otherwise have been. That falls out
of interning rather than being a decision about equality.

There is no way to release a pattern, and none is needed: a slot names the same pattern for as long as the
program runs, so a loop writing `regex("\\d+")` costs one entry and not one per turn.
