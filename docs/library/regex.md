---
title: "slate:regex"
weight: 80
---

# `slate:regex`

ECMAScript regular expressions — the dialect a browser reads. **One export, because a pattern is one
object and everything a program does with it is a method on that object.**

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

The flags are `i`, `m`, `s` and `u`.

## A match is an ordinary object

`text`, `start`, `end`, `groups` and `named`.

- **`groups` has the whole match at 0**, and **`null`** for a group that took no part.
- **`named` is always present and empty where the pattern names nothing.** A field that appears only
  sometimes is one a program must test for before reading.
- **Every offset is in characters**, as everywhere else in slate — the engine answers in bytes under
  the interpreter and in UTF-16 code units under `slate js`, and each is converted in one pass.

## The dialect is ECMAScript's, and it is the same one on both back ends

**The pattern you write is the pattern the engine compiles**, on either back end and with nothing in
between. Under the interpreter it goes to [QuickJS's engine](https://github.com/sysl-lang/libregexp),
carried in the binary; under `slate js` it goes to the host's own `RegExp`. So `\s`, `.`, `^` and `$`
mean what they mean in a browser, `\d` is `[0-9]`, and a program that works in one place works in the
other.

**A Perl construct that ECMAScript does not have is refused where the pattern is written**, carrying
the engine's own complaint — a possessive quantifier `a*+`, an atomic group `(?>…)`, a conditional
`(?(1)…)`, recursion `(?R)`, `\K`, `\X`, `\A`, `\z`, `\h`, `\R`, a POSIX class `[[:alpha:]]`, a
Python-style `(?P<name>…)`, a modifier that runs to the end of a pattern `(?i)`. The spellings
ECMAScript uses instead are `(?<name>…)` for a named group, `^`/`$` with or without `m` for the
anchors, and `\s`/`\S` for the spaces.

**`u` is always on, whether or not it is written.** slate counts a string in characters, and without
`u` ECMAScript matches over UTF-16 code units — `.` would take half of an emoji and `^.$` would say
one character is two. What it buys beyond that is `\p{…}`: `\p{L}`, `\p{Nd}` and `\p{Script=Greek}`
all work with no flag to remember.

## Three of JavaScript's decisions are reversed

| slate | JavaScript, and what it costs |
|---|---|
| **a pattern carries no position** | a `/g` pattern holds a mutable `lastIndex`, so `re.test(s)` twice on one string is `true` then `false` — visible only on the second call |
| **`replace` replaces every match**, `replaceFirst` stops | a bare `replace` changes the first only unless `/g` is set, which is why `replaceAll` had to be added two decades later |
| **a match that would backtrack forever is a fault** | no limit at all, so a crafted subject stops a server answering |

**There is no `g` flag and no `y` flag**, and asking for either is refused *by name*: both are about
where the next match starts, and a pattern here has no such state to hold. The third refusal is `x`,
which slate had when its patterns were Perl's — ECMAScript has no extended mode, so a space written
in a pattern is part of it.

**A match runs under a step budget**, and a pattern that would backtrack forever gives up rather than
holding the program. It is an ordinary fault, so a server matching a pattern somebody sent can catch
it and answer:

```slate
import { regex } from slate:regex

try
    regex("(a+)+$").test("a".repeat(40) + "b")
catch e
    print(e.message.contains("backtracking"))
```

```output
true
```

[The JavaScript page](../reference/javascript.md) has the one difference that is left standing: a
browser has no budget of any kind, so that fault is the interpreter's alone.

## Equality

**An identical pattern compiles once**, so `regex("a") == regex("a")` is **true** where two arrays written
the same way are equal by contents but two compiled patterns would not otherwise have been. That falls out
of interning rather than being a decision about equality.

There is no way to release a pattern, and none is needed: a slot names the same pattern for as long as the
program runs, so a loop writing `regex("\\d+")` costs one entry and not one per turn.
