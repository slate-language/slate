# `slate:regex`

PCRE2 patterns. **One export, because a pattern is one object and everything a program does with it is a
method on that object.**

```slate
import { regex } from slate:regex

val re = regex("(\\d+)-(\\d+)")
val text = "a 10-20 b 30-40"

print(re.test(text))
print(re.find(text).groups)
print(re.find(text).start, re.find(text).end)
print(re.replace(text, "$2-$1"))
print(re.replaceFirst(text, "x"))
print(re.pattern())
```

```output
true
["10-20", "10", "20"]
2 7
a 20-10 b 40-30
a x b 30-40
(\d+)-(\d+)
```

Asking for a `g` flag is refused by name, since a flag silently ignored would make `replace` look like
it had worked for the wrong reason:

```slate
import { regex } from slate:regex

print(regex("a", "g"))
```

```error
g
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
rather than every decimal digit in Unicode. Both are settled here so that a pattern means one thing
wherever it runs — each is a place PCRE2 and JavaScript would otherwise disagree silently, compiling
either way and merely matching something else. A program wanting Unicode digits writes `\p{Nd}`, which
works regardless.

**Under `slate js` a pattern is translated into `RegExp`**, and the same rule decides everything there:
`\s`, `.` and `^`/`$` under `m` all mean something else to a browser and are written out so that they do
not. A handful of PCRE2 constructs a browser has nothing to mean — a possessive quantifier, an atomic
group, recursion, `\K` — are refused where the pattern is written, naming the construct.
[The JavaScript page](../reference/javascript.md) has the measurements and the three differences that
are left standing, of which the backtracking budget above is one: `RegExp` has no such limit in any
browser.

## Equality

**An identical pattern compiles once**, so `regex("a") == regex("a")` is **true** where two arrays written
the same way are equal by contents but two compiled patterns would not otherwise have been. That falls out
of interning rather than being a decision about equality.

There is no way to release a pattern, and none is needed: a slot names the same pattern for as long as the
program runs, so a loop writing `regex("\\d+")` costs one entry and not one per turn.
