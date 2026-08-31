// Text and numbers.
//
// **A slate string is a sequence of characters, never of bytes.** Everything below counts and cuts
// by character, so a program that has never thought about UTF-8 cannot get it wrong -- `len` of
// three Japanese characters is three, and slicing one out gives you the character rather than a
// third of it.
//
// There is still no character type, so a single character is a string of one. That is Python's
// answer, and it is what lets indexing, `chars` and `split` all hand back the same kind of thing.

val greeting = "héllo, 世界"

print(len(greeting))
print(greeting[0], greeting[1], greeting[7])
print(greeting[0..<5])
print(chars("añb"))

// -- writing values into a string --------------------------------------------------------------

// `s"..."` renders what stands in its holes, and a hole that is a single name needs no braces --
// which is Scala's short form and covers most of them.
val w = 3
val h = 4

print(s"$w by $h")
print(s"$w by $h" == s"${w} by ${h}")

// **The short form is identifier-only and stops at the end of the name**, so anything with a dot, a
// call or an operator in it wants the braces. That keeps where a hole ends a question with one
// answer.
val box = { w: 2, h: 5 }

print(s"$box.w")
print(s"${box.w} by ${box.h}, area ${box.w * box.h}")

// `$$` is a literal `$`, and a `$` that begins no name is simply itself -- so a price needs nothing
// doing to it.
print(s"$$w is the text, $w is the value")
print(s"costs 5$")

// A hole renders as `print` would, so a container shows its contents rather than its address.
print(s"${[1, 2]} and ${ { a: 1 } }")

// Taking text apart and putting it back together.
val row = "  name , age,  city  "
val fields = split(row, ",")

print(fields)

var cleaned = []

for f in fields
    push(cleaned, trim(f))

print(join(cleaned, "|"))

// Searching answers a position a person would count -- and `null` rather than a sentinel, because
// slate has a null and the operators that go with it.
print(indexOf("héllo", "llo"), indexOf("héllo", "z"))
print(indexOf("héllo", "z") ?? 0)
print(contains(row, "age"), startsWith(row, "  "), endsWith(trim(row), "city"))

print(replace("a-b-c", "-", " to "))
print(repeat("-", 20))

// `upper` and `lower` are ASCII, which sysl's own case conversion says of itself: a Unicode case
// table is above that layer, so `é` comes back as it went in.
print(upper("hello"), upper("héllo"))

// -- numbers ------------------------------------------------------------------------------------

// `num` reads one out of a string and answers null where there is not one, which is how a program
// checks input without a fault.
val ages = ["34", "7", "not a number", "1.5"]

for a in ages
    val n = number(a)

    print(if n == null then s"${a}: not a number" else s"${a}: ${n}")

// `int` and `real` move between the two kinds slate keeps apart; the four roundings leave an integer
// alone, an integer already being whole.
print(integer(3.7), integer(-3.7), real(3))
print(floor(3.7), ceil(3.2), round(3.5), trunc(-3.7))
print(abs(-4), sqrt(16), pow(2, 10))
print(min(3, 1, 2), max(3, 1, 2))

// A small thing the pieces add up to: an average, read from text.
average(rows) =
    var total = 0.0
    var seen = 0

    for r in rows
        val n = number(trim(r))

        if n != null
            total = total + real(n)
            seen += 1

    if seen == 0 then null else total / real(seen)

print(average([" 10 ", "20", "oops", "30 "]))
