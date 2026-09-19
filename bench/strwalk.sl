// Reading a 20,000-character string one character at a time BY INDEX, where the characters are NOT
// one byte each.
//
// **`strindex` is this benchmark over ASCII and it hides half the question.** A slate position is a
// character and the storage is UTF-8, so for text that is all one byte a position and a byte offset
// are the same number and an index is arithmetic. For text that is not -- which is most of the
// writing in the world -- something has to find where the tenth character begins, and the only way
// to do that from cold is to walk the nine before it. This is the benchmark that says what that
// costs.
//
// **The text is deliberately all in the basic plane** (three bytes each in UTF-8, one unit each in
// UTF-16), so that the JavaScript twin's index means what this one's means. An emoji would not: it
// is one character here and two units there, and the twin would be walking a different string.
//
// **The twins do NOT all do the same amount of work here, and their headers say so.** Python indexes
// code points in constant time, JavaScript indexes UTF-16 units in constant time, and Lua has no
// character indexing at all -- `utf8.offset` counts from the front, so the idiomatic Lua walk is
// quadratic in the same way slate's used to be. Lua is the yardstick everywhere else in this
// directory and it is not a yardstick here.

run(s)
    var found = 0
    var i = 0

    while i < s.length
        if s[i] == "本" then found = found + 1

        i = i + 1

    found

var text = ""
var k = 0

while k < 1000
    text = text + "日本語あいうえおかきく" + "さしすせそたちつてと"
    k = k + 1

print(run(text))
