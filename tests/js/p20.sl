// `slate:regex`, on both back ends.
//
// **The two sides here are two ENGINES, not two implementations of one thing.** The interpreter's
// patterns go to PCRE2 through `sh.sysl.pcre2`; the emitted program's are translated into `RegExp`
// by `js_rt_regex.sysl`. So every line below is a claim that a translation is exact, and the ones
// that matter most are the constructs both engines accept while meaning different things --
// `\s`, `.`, and `^`/`$` under `m` -- because those are the only ones a program could get wrong
// without anything refusing it.
//
// **What is deliberately NOT here.** A pattern that backtracks forever gives up under PCRE2 and runs
// forever under `RegExp`, so `(a+)+$` against a subject with no `b` cannot be in a corpus that has
// to finish; `docs/reference/javascript.md` names it. Neither can `\w` under `i` against `U+017F`,
// which is the one measured difference left standing.

import { regex } from slate:regex

// -- the ordinary half, which is most of what anybody writes -------------------------------------

print(regex("\\d+").find("abc123").text)
print(regex("<(.+?)>").find("<a><b>").text)
print(regex("foo(?=bar)").test("foobar"), regex("foo(?=bar)").test("foobaz"))
print(regex("(?<=\\$)\\d+").find("costs $42").text)
print(regex("(\\w)\\1").find("hello").text)
print(regex("(?:ab)+").find("abab").text)

val m = regex("(\\d+)-(\\w+)").find("xx 42-abc")

print(m.text, m.start, m.end, len(m.groups), m.groups[1], m.groups[2])

val n = regex("(?<year>\\d{4})-(?<month>\\d{2})").find("on 2026-08")

print(n.named.year, n.named.month)

val e = regex("(a)|(b)").find("b")

print(e.groups[1], e.groups[2])
print(regex("(a*)b").find("b").groups[1] == "")
print(regex("(a)(b)").find("ab").named)

// -- the flags -------------------------------------------------------------------------------------

print(regex("hello", "i").test("Hello"))
print(regex("a.b", "s").test("a\nb"), regex("a.b").test("a\nb"))
print(regex("foo$").test("foo\n"), regex("foo$").test("foo"))
print(regex("a", "im").pattern(), regex("a", "im").flags())
print(regex("a  b  # a comment\n c", "x").test("abc"))
print(regex("a\\ b", "x").test("a b"))

// **`^` and `$` under `m` are the first place `RegExp` means something else.** PCRE2 breaks a line
// at a newline and nothing else; `RegExp` breaks it at a carriage return and at the two Unicode
// separators too, so an unmodified `m` would find a line start in three places PCRE2 does not.
print(regex("^b", "m").find("a\nb").start)
print(regex("^b", "m").test("a\rb"), regex("^b", "m").test("a\u{2028}b"))
print(regex("a$", "m").test("a\rb"), regex("a$", "m").test("a\nb"))

// **And `.` is the second.** PCRE2's excludes the newline alone.
print(regex("a.b").test("a\rb"), regex("a.b").test("a\u{2029}b"))

// -- the sets ---------------------------------------------------------------------------------------

// **`\s` IS THE DANGEROUS ONE.** PCRE2 here is not in UCP mode, so it is the six ASCII spaces;
// `RegExp` reads it as every Unicode space there is. A field split on `\s` would cut on a
// no-break space in a browser and not in the interpreter.
print(regex("\\s").test("\u{a0}"), regex("\\s").test(" "))
print(regex("\\S").test("\u{a0}"), regex("[\\S]").test("\u{a0}"))
print(len(regex("\\s+").split("a b\tc")))

// `\h`, `\v` and `\R`, which `RegExp` does not have at all.
print(regex("\\h").test("\u{a0}"), regex("\\h").test("\n"))
print(regex("\\v").test("\n"), regex("\\v").test(" "))
print(regex("\\H").test("\u{a0}"), regex("\\V").test("\n"))
print(len(regex("\\R").findAll("a\r\nb\nc")))
print(regex("[\\h\\v]").test("\t"), regex("[\\H]").test("q"))

// The POSIX classes, and the negations that are NOT ASCII.
print(regex("[[:alpha:]]").test("a"), regex("[[:alpha:]]").test("1"))
print(regex("[[:^alpha:]]").test("\u{e9}"), regex("[[:^alpha:]]").test("a"))
print(regex("[[:digit:][:punct:]]+").find("a!5b").text)
print(regex("[x[:^digit:]]").test("q"))
print(regex("[[:xdigit:]]+").find("zz1aF!").text)
print(regex("[[:cntrl:]]").test("\u{1}"), regex("[[:cntrl:]]").test("a"))

// `\p{...}`, which PCRE2 writes with a bare script name and `RegExp` does not.
print(regex("\\p{L}+").find("42abc!").text)
print(regex("\\p{Greek}+").find("ab\u{3b1}\u{3b2}!").text)
print(regex("\\P{Nd}").test("5"), regex("\\P{Nd}").test("x"))

// -- the anchors and the escapes PCRE2 spells differently ----------------------------------------

print(regex("a\\z").test("a"), regex("a\\z", "m").test("a\nb"))
print(regex("\\Aa").test("ab"), regex("\\Aa", "m").test("b\na"))
print(regex("a\\Z").test("a\n"), regex("a\\Z").test("ab"))
print(regex("\\Qa.b\\E").test("a.b"), regex("\\Qa.b\\E").test("axb"))
print(regex("\\a").test("\u{7}"), regex("\\e").test("\u{1b}"))
print(regex("a\\Nb").test("axb"), regex("a\\Nb").test("a\nb"))
print(regex("\\x{263A}").test("\u{263a}"), regex("\\o{101}").test("A"))
print(regex("(?P<x>a)(?P=x)").test("aa"))
print(regex("a(?#a comment)b").test("ab"))
print(regex("(?'y'a)\\k{y}").test("aa"))
print(regex("a\\%b").test("a%b"), regex("a{b").test("a{b"), regex("a]b").test("a]b"))
print(regex("[]a]").test("]"), regex("[a\\-z]").test("-"))

// -- the walk, which is where 0.1.1 and 0.1.2 differ ----------------------------------------------

// **`findAll`'s count must equal the number of substitutions `replace` makes**, and the two walks
// are independent: one is this back end's own loop and the other is PCRE2's `SUBSTITUTE_GLOBAL`.
// A zero-width pattern is where they came apart -- `find_at` searched unanchored and the loop
// compared the match's end against where the SEARCH began, so an empty match found ahead of the
// cursor was pushed twice.
zero(pat, subject)
    val re = regex(pat)
    var subs = 0

    for c in re.replace(subject, "#").chars()
        if c == "#" then subs += 1

    print(pat, len(re.findAll(subject)), subs)

zero("$", "abc")
zero("^", "abc")
zero("\\b", "ab cd")
zero("\\B", "ab")
zero("a*", "bb")
zero("x?", "ab")
zero("", "abc")
zero("(?=b)", "abcb")

print(regex("\\w+").findAll("one two three").map((x) -> x.text).join(","))
print(regex("\\s*,\\s*").split("a, b ,c").join("|"))
print(regex("a*").split("bb").join("|"))
print(regex(",").split(",a,").join("|"))
print(regex("z").split("abc").join("|"))
print(regex("(,)").split("a,b").join("|"))
print(regex("abc").split("abc").join("|"))
print(len(regex("x").findAll("abc")))

// -- replacing, whose syntax is PCRE2's and not JavaScript's --------------------------------------

val at = regex("(\\w+)@(\\w+)")

print(at.replace("a@b and c@d", "$2 at $1"))
print(at.replaceFirst("a@b and c@d", "$2 at $1"))
print(regex("(a)|(b)").replace("b", "[$1$2]"))
print(regex("ab").replace("ab", "[$0][$&]"))
print(regex("a").replace("a", "$$"))
print(regex("(?<x>a)").replace("a", "[$x][${x}]"))
print(regex("(a)").replace("a", "[\\1]"))

// -- a pattern carries no position, and an identical one is one pattern ---------------------------

val re = regex("a")

print(re.test("banana"), re.test("banana"), re.test("banana"))
print(len(re.findAll("banana")), len(re.findAll("banana")))
print(regex("a") == regex("a"), regex("a") == regex("b"), regex("a") == regex("a", "i"))
print(regex("a+", "i"))
print(regex("a") is regex, "a" is regex, string(regex("a", "i")))

val t = {}

t[regex("a")] = 1
t[regex("a", "i")] = 2
print(t[regex("a")], t[regex("a", "i")])

// -- characters, not code units -------------------------------------------------------------------

// **PCRE2 counts a subject in characters and `RegExp` counts one in UTF-16 code units**, so an
// astral character before a match makes every offset after it one too many unless it is converted.
val astral = regex("cd").find("\u{1f600}xcd")

print(astral.start, astral.end, len("\u{1f600}xcd"))
print(len(regex(".").findAll("\u{1f600}x")))
print(regex("^.$").test("\u{1f600}"))
print(regex("\\w").find("\u{1f600}ab").start)

val bmp = regex("cd").find("\u{e9}xcd")

print(bmp.start, bmp.end)
