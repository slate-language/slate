// Reading a string one character at a time BY INDEX, over a string of 16,000 characters.
//
// **This benchmark exists because slate's `s[i]` walks the string from the start.** A slate string
// is UTF-8 and a position is in CHARACTERS, so the tenth character is found by decoding the nine
// before it -- which makes an ordinary left-to-right walk quadratic in the length of the string.
// Everything the other three languages do here is a constant-time read into a byte array.
//
// **It is deliberately outside the size band the other benchmarks are written to.** Sized so that
// Lua takes a fifth of a second, this file would run for hours under slate; sized so that slate
// takes a couple of seconds, the other three finish before their own start-up is over. That gap is
// the measurement, so the file is sized for slate and the reader is told which number is which.

run(s)
    var found = 0
    var i = 0

    while i < s.length
        if s[i] == "x" then found = found + 1

        i = i + 1

    found

var text = ""
var k = 0

while k < 1000
    text = text + "abcdexfghi" + "jklmnxopqr"
    k = k + 1

print(run(text))
