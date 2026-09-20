// `slate:regex`, on both back ends.
//
// **The two sides here are two ENGINES reading one dialect.** The interpreter's patterns go to
// QuickJS's engine through `sh.sysl.libregexp`; the emitted program's go to the host's `RegExp`.
// Neither side translates anything — that is what changed when slate's patterns stopped being
// Perl's — so every line below is a claim that two implementations of ECMAScript agree, which
// is a far narrower claim than the translator's and covers far more of the language.
//
// **`u` is set on both sides whether or not the program wrote it**, since slate indexes a string by
// character; without it ECMAScript matches over UTF-16 code units and the two would not even agree
// about how long a subject is.
//
// **What is deliberately NOT here.** A pattern that backtracks forever gives up under the
// interpreter's step budget and runs forever under `RegExp`, so `(a+)+$` against a subject with no
// `b` cannot be in a corpus that has to finish; `docs/reference/javascript.md` names it, and
// `tests_regex.sysl` is where it is pinned.

import { regex } from slate:regex

// -- the ordinary half, which is most of what anybody writes -------------------------------------

print(regex("\\d+").find("abc123").text)
print(regex("<(.+?)>").find("<a><b>").text)
print(regex("foo(?=bar)").test("foobar"), regex("foo(?=bar)").test("foobaz"))
print(regex("(?<=\\$)\\d+").find("costs $42").text)
print(regex("(\\w)\\1").find("hello").text)
print(regex("(?:ab)+").find("abab").text)
print(regex("a{2,3}").find("aaaa").text, regex("a+?").find("aaa").text)

// **A lookbehind of any length, and a scoped modifier.** PCRE2 refused an unbounded lookbehind and
// had no `(?i:…)` at all, so both of these were refused by one back end or the other.
print(regex("(?<=ab*)c").test("abbc"), regex("(?<=ab?)c").test("abc"))
print(regex("(?i:a)b").test("Ab"), regex("(?i:a)b").test("aB"))

val m = regex("(\\d+)-(\\w+)").find("xx 42-abc")

print(m.text, m.start, m.end, m.groups.length, m.groups[1], m.groups[2])

val n = regex("(?<year>\\d{4})-(?<month>\\d{2})").find("on 2026-08")

print(n.named.year, n.named.month)

val e = regex("(a)|(b)").find("b")

print(e.groups[1], e.groups[2])
print(regex("(a*)b").find("b").groups[1] == "")
print(regex("(a)(b)").find("ab").named)
print(regex("(?:(?<n>a)|b)\\k<n>").test("aa"), regex("x").test("y"))

// -- the flags -------------------------------------------------------------------------------------

print(regex("hello", "i").test("Hello"))
print(regex("a.b", "s").test("a\nb"), regex("a.b").test("a\nb"))
print(regex("foo$").test("foo\n"), regex("foo$").test("foo"))
print(regex("a", "im").pattern(), regex("a", "im").flags())
print(regex("a", "u").test("a"), regex("a", "u").flags())

// **`^` and `$` under `m` break a line at every ECMAScript line terminator**, which is four
// characters and not one: the newline, the carriage return and the two Unicode separators.
print(regex("^b", "m").find("a\nb").start)
print(regex("^b", "m").test("a\rb"), regex("^b", "m").test("a\u{2028}b"))
print(regex("a$", "m").test("a\rb"), regex("a$", "m").test("a\nb"))

// **And `.` excludes all four.**
print(regex("a.b").test("a\rb"), regex("a.b").test("a\u{2029}b"))

// -- the sets ---------------------------------------------------------------------------------------

// **`\s` is every Unicode space**, which is ECMAScript's rule and was `RegExp`'s all along; under
// PCRE2 it was the six ASCII ones, so a field split on `\s` cut on a no-break space in a browser
// and not in the interpreter. That difference is what moving the dialect closed.
print(regex("\\s").test("\u{a0}"), regex("\\s").test(" "))
print(regex("\\S").test("\u{a0}"), regex("[\\S]").test("\u{a0}"))
print(regex("\\s+").split("a b\tc").length)
print(regex("\\d").test("5"), regex("\\d").test("\u{0661}"))
print(regex("[a-c]+").find("xabcy").text, regex("[^a-c]+").find("abcxy").text)
print(regex("[\\w.-]+").find("a.b-c!").text)

// `\p{...}`, which is a property escape because `u` is always set.
print(regex("\\p{L}+").find("42abc!").text)
print(regex("\\P{Nd}").test("5"), regex("\\P{Nd}").test("x"))
print(regex("[\\p{Lu}]+").find("abCDe").text)
print(regex("\\p{Script=Greek}+").find("ab\u{3b1}\u{3b2}!").text)

// -- the walk ---------------------------------------------------------------------------------------

// **`findAll`'s count must equal the number of substitutions `replace` makes**, and the two walks
// are independent on each back end: `find_all`'s loop against `replace_all`'s in the interpreter,
// this runtime's loop against the host's `String.prototype.replace` under `slate js`. A zero-width
// pattern is where such a pair comes apart.
zero(pat, subject)
    val re = regex(pat)
    var subs = 0

    for c in re.replace(subject, "#").chars()
        if c == "#" then subs += 1

    print(pat, re.findAll(subject).length, subs)

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
print(regex("x").findAll("abc").length)

// -- replacing, whose syntax is ECMAScript's ------------------------------------------------------

val at = regex("(\\w+)@(\\w+)")

print(at.replace("a@b and c@d", "$2 at $1"))
print(at.replaceFirst("a@b and c@d", "$2 at $1"))
print(regex("(a)|(b)").replace("b", "[$1$2]"))
print(regex("b").replace("abc", "[$&|$`|$']"))
print(regex("a").replace("a", "$$"))
print(regex("(?<x>a)").replace("a", "[$<x>]"))
print(regex("(a)").replace("a", "[$9][$0]"))
print(regex("(?<x>a)").replace("a", "[$<nope>]"))
print(regex("(a)").replace("a", "[$<nope>]"))
print(regex("a*").replace("bb", "#"))

// -- a pattern carries no position, and an identical one is one pattern ---------------------------

val re = regex("a")

print(re.test("banana"), re.test("banana"), re.test("banana"))
print(re.findAll("banana").length, re.findAll("banana").length)
print(regex("a") == regex("a"), regex("a") == regex("b"), regex("a") == regex("a", "i"))
print(regex("a+", "i"))
print(regex("a") is regex, "a" is regex, string(regex("a", "i")))

val t = {}

t[regex("a")] = 1
t[regex("a", "i")] = 2
print(t[regex("a")], t[regex("a", "i")])

// -- characters, not code units -------------------------------------------------------------------

// **The interpreter counts a subject in bytes and a JavaScript host counts one in UTF-16 code
// units**, and slate counts characters — so each back end converts, by a different walk, and this
// is where the two conversions are asserted to agree.
val astral = regex("cd").find("\u{1f600}xcd")

print(astral.start, astral.end, "\u{1f600}xcd".length)
print(regex(".").findAll("\u{1f600}x").length)
print(regex("^.$").test("\u{1f600}"))
print(regex("\\w").find("\u{1f600}ab").start)
print(regex("[\u{1f600}]").test("\u{1f600}"), regex("\u{1f600}").find("a\u{1f600}b").start)

val bmp = regex("cd").find("\u{e9}xcd")

print(bmp.start, bmp.end)
