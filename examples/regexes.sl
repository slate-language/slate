// Regular expressions: Perl's dialect, on PCRE2, with three of JavaScript's decisions reversed.
//
// The pattern you would write anywhere else is the pattern that works here -- `\d`, `\w`, lazy
// quantifiers, lookaround, backreferences and named groups all mean what they mean in Perl, Python,
// Ruby and a browser.

import { regex } from slate:regex

val words = regex("\\w+")

print(words.findAll("one two three").map((m) -> m.text).join(", "))

// A match says where it landed, in CHARACTERS. The engine counts bytes and slate counts characters,
// so every offset is converted on the way out -- which matters the moment a subject is not ASCII.
val m = regex("cd").find("éxcd")

print("found at", m.start, "to", m.end)

// Groups come back by number, and by name where the pattern gave them one.
val stamp = regex("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})")
val d = stamp.find("filed on 2026-08-28, closed later")

print(d.named.year, "/", d.named.month, "/", d.named.day)
print("the whole match:", d.groups[0])

// A group that took no part in the match is null -- which is a different thing from a group that
// matched the empty string, and the two are worth telling apart.
val either = regex("(a)|(b)").find("b")

print(either.groups[1], either.groups[2])
print(regex("(a*)b").find("b").groups[1] == "")

// -- three places this is not JavaScript ----------------------------------------------------------

// ONE. `replace` replaces every match. In JavaScript a bare `replace` changes the first occurrence
// only, unless the pattern carries `/g` -- which is why `replaceAll` had to be added to the language
// two decades after the fact. Here the bare verb does the whole job, and `replaceFirst` is the one
// that stops early.
val pair = regex("(\\w+)@(\\w+)")

print(pair.replace("a@b and c@d", "$2 at $1"))
print(pair.replaceFirst("a@b and c@d", "$2 at $1"))

// TWO. A pattern carries no position. A JavaScript `/g` pattern holds a mutable `lastIndex`, so
// `re.test(s)` answers true, then false, then true for the same string -- a bug that only appears on
// the second call. There is no state here to have it in.
val a = regex("a")

print(a.test("banana"), a.test("banana"), a.test("banana"))

// THREE. A pattern that would backtrack forever gives up instead. `(a+)+$` against a subject with no
// `b` is the standard demonstration, and node has no limit at all -- a server there stops answering.
val bomb = regex("(a+)+$")
val long = "a".repeat(40) + "b"

// Every match runs under a budget, and running out is a fault a program can catch.
try
    bomb.test(long)
    print("this line is not reached")
catch e
    print("gave up, as it should:", e.message.contains("backtracking"))

// A pattern that will not compile is refused where it is written, naming where the engine stopped.
try
    regex("a(b")
catch e
    print(e.message.contains("not a regular expression"))

// The flags are `i`, `m`, `s` and `x`. There is no `g`, and asking for one says so.
print(regex("hello", "i").test("Hello World"))
print(regex("^\\w+", "m").findAll("one\ntwo").map((x) -> x.text).join(","))

// Splitting on a pattern rather than on literal text.
print(regex("\\s*,\\s*").split("a, b ,c   ,d").join("|"))
