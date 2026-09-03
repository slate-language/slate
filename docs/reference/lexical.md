# Lexical structure

What the compiler reads before it reads anything else: files, whitespace, names and literals.

## Files

A slate program is a **`.sl`** file. A file that writes [elements](elements.md) is conventionally
**`.slx`**, after `.tsx` — but the extension says nothing to the compiler, which parses both the same
way, and elements are read in every file. It is a name for a reader and an editor.

A file with a `#!` line on its first byte is a command. slate skips that line and everything after
the program's name on the command line belongs to the program:

```
#!/usr/bin/env slate

import { args, exit } from slate:process

if args.len() == 0
    print("usage: greet <name>...")
    exit(2)

for name in args
    print("Hello, " + name + "!")
```

`#!` is read at the very first byte and nowhere else. **`#` is not a comment in slate.**

## Comments

`//` to the end of the line. There is no block comment.

## Indentation is structure

slate is off-side ruled, as Python and sysl are. A block is opened by indenting under the line that
introduces it and closed by returning to the outer column.

**A newline inside brackets means nothing**, which is what lets an argument list or an array literal
be split across lines. Two tokens suspend that rule, and only where they end a line: **`->`** and
**`match`**. Either one at the end of a line opens a block even inside brackets, which is what lets a
callback with a real body be written where it is passed:

```
each([1, 2, 3], x ->
    val doubled = x * 2
    print(x, doubled))
```

An arrow written mid-line would hand the block to whatever line came next, so it does not open one.

**A block lambda has to be the last argument**, because its block runs to the end of its last line
and a `,` arriving there has nothing to mean.

**A trailing operator does not continue a line.** `a +` followed by `b` on the next line is two
statements, not a sum. Where an expression has to span lines, brackets are what say so — inside them
the off-side rule is suspended and the continuation is unambiguous:

```
val ok = (
    isShort(name) ||
    isKnown(name))
```

## `end`, and the closing words

A block that has grown long enough to want a closing marker takes one: `end if`, `end while`,
`end for`, `end loop`, `end <name>` for a definition or a class. **`end` is a soft word** — a program
may still call something `end` — and so are `class`, `data` and `type`.

## Names

An identifier is a letter or `_` followed by letters, digits and `_`. Names are case-sensitive.

**The type words are not keywords.** `null`, `boolean`, `integer`, `real`, `number`, `string`,
`array`, `object`, `function`, `date`, `time`, `zone` and the rest of the twenty-one listed in
[Patterns](patterns.md) are ordinary names in expression position — `val int = 3` and `val date = readIt()` both work — and are read as type tests only in
[pattern position](patterns.md).

**There are no abbreviations.** It is `boolean` and `function`, never `bool` and `fn`; a short form
is refused with the long one named.

## Literals

```
null            true    false
42              -7      1_000_000
0xff            0b1011  0o17
3.14            2e10    1e-3
"text"          s"interpolated ${text}"
[1, 2, 3]       [0; 5]
{ a: 1, b: 2 }  { a }
0..<n           1..10
```

An integer may be written in hexadecimal, binary or octal, and `_` may be written between digits of
any of them.

**Integers and reals are separate values**, not one numeric type. An integer is 64 bits, wraps, and
divides towards zero.

Every comma list takes a **trailing comma**: an array, an object, an argument list, a parameter list.

`[v; n]` is an array of `n` copies of `v`.

## Strings

A string literal is double-quoted with the usual escapes (`\n`, `\t`, `\\`, `\"`, `\u{...}`). There is
no single-quoted form and no character type — **a single character is a string of one**.

An **s-string** interpolates:

```
s"${w} by ${h}"
s"$w by $h"                  // the same thing
s"$point.x"                  // interpolates `point`, then `.x` is text
s"${point.x}"                // says the other thing
s"costs 5$"                  // a `$` that begins no name is just itself
s"$$"                        // a literal `$`
```

**A hole that is a single name needs no braces.** The short form is identifier-only and stops at the
end of the name, which is why `$point.x` and `${point.x}` differ.

**There is no raw string.** A backslash in a string is an escape wherever it appears, so a regular
expression written as a literal doubles its backslashes: `regex("\\d+")`.

## What a program never writes

There is no `undefined`, no `NaN` that spreads, and no `Invalid Date`. Each of those is a value that
travels through a program silently changing what everything downstream computes, and slate has none
of them: the equivalent situation is either a `null` the program can test or a fault it can catch.
