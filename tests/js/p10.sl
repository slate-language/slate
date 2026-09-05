// The builtins whose ANSWER is not the shape JavaScript's own would be.
//
// **Every program beside this one is about a language construct**, and each of them happens to reach
// a few builtins on the way. This one is about the builtins themselves, and specifically about the
// ones where JavaScript has an answer of its own and it is the wrong answer: a miss that is `-1`
// rather than `null`, a `Number()` that trims and reads `""` as zero, an `undefined` where slate has
// nothing.
//
// It exists because `indexOf` answered `-1` here for as long as this back end had one, and the
// compiler's golden tests -- which pin the emitted text -- could not have seen it. What found it was
// `slate-language/lath`, whose `isVoid(tag)` asks `[...].indexOf(tag) != null`: every tag was a void tag,
// so an element rendered as its opening tag and nothing else.

// -- a miss is `null`, because slate has no out-of-band integer -------------------------------------

print([1, 2, 3].indexOf(2), [1, 2, 3].indexOf(9))
print([1, 2, 3].lastIndexOf(2), [1, 2, 3].lastIndexOf(9))
print("héllo".indexOf("llo"), "héllo".indexOf("z"))
print("héllo".lastIndexOf("l"), "héllo".lastIndexOf("z"))
print([1, 2, 3].find(x -> x > 2), [1, 2, 3].find(x -> x > 5))
print([1, 2, 3].findIndex(x -> x > 2), [1, 2, 3].findIndex(x -> x > 5))

// This is the shape the framework depends on, written out because a test that only asks for the
// value would still pass while the comparison it exists for did not.
print(["br", "img"].indexOf("div") != null, ["br", "img"].indexOf("br") != null)

// -- and a position is read ONE way, where JavaScript reads it two ------------------------------

// `Array.prototype.indexOf` counts a negative back from the end and `String.prototype.indexOf`
// clamps it to zero. slate dispatches one builtin over both kinds, so one of those readings had to
// go and counting back is the one `slice` and `at` already use.
print("abcabc".indexOf("b", 2), "abcabc".indexOf("b", 5))
print("abcabc".lastIndexOf("b", 3), "abcabc".lastIndexOf("b", 0))
print("abcabc".indexOf("b", -3), "abcabc".lastIndexOf("b", -3))
print("abcabc".indexOf("b", -99), "abcabc".lastIndexOf("b", -99))
print("abc".indexOf("a", 99), "abc".lastIndexOf("a", 99))
print("héllé".indexOf("l", 3), "héllé".lastIndexOf("l", 2))
print([1, 2, 1, 2].indexOf(2, 2), [1, 2, 1, 2].lastIndexOf(1, 1))
print([1, 2, 1].indexOf(1, -1), [1, 2, 1].lastIndexOf(1, -99))
print([1, 2, 1].indexOf(1, 99), [1, 2, 1].lastIndexOf(1, 99))

// -- `number` reads text, and answers `null` when the text is not a number --------------------------

// **The integer path is strict and the fallback is `strtod`'s**, which is why a leading blank is
// allowed and a trailing one is not, and why the two answers have different kinds.
for s in ["12", " 12", "12 ", "", "+7", "-7", "0x10", "1e3", "inf", "nan", "1_000", ".5", "5.",
          "1.5x", "abc", "9223372036854775807", "9223372036854775808", "-9223372036854775808"]
    val v = number(s)

    print(s, "->", v, if v == null then "" elif v is integer then "integer" else "real")

// -- `integer` and `real` take a NUMBER, and say so --------------------------------------------------

print(integer(-2.7), integer(2.7), integer(7))
print(real(7), real(2.5))

try
    integer("7")
catch e
    print(e.message)

try
    real(true)
catch e
    print(e.message)

// -- and the ordinary answers, so a fix that breaks the common case is loud --------------------------

print(number(2.5), number(7))
print([1, 2, 3].indexOf(1), "abc".indexOf("a"))

// -- A COMPARATOR ANSWERS A BOOLEAN, AND THE BACK END DEMANDED A NUMBER ------------------------------
//
// slate's rule is `sorted(xs, (a, b) -> a.age < b.age)`, because zero is TRUE here and a -1/0/1
// comparator would read as "yes, yes, yes" and sort nothing. The JavaScript runtime asked for a
// number instead, so the documented idiom faulted under `slate js` and nowhere else -- and every
// golden test stayed green, the runtime being a text block no expectation quotes.

print(sorted([3, 1, 2], (a, b) -> a < b))
print(sorted([3, 1, 2], (a, b) -> a > b))

// Stability: two elements the comparator calls equal keep the order they came in.
val people = [{ n: "a", age: 2 }, { n: "b", age: 1 }, { n: "c", age: 2 }]

print(map(sorted(people, (x, y) -> x.age < y.age), p -> p.n))

try
    sorted([2, 1], (a, b) -> a - b)
catch e
    print(e.message)
