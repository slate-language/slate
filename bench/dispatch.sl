// Branching on a string, which in slate is a `match` and in the other three is a chain of
// comparisons or a table lookup.
//
// **The words are cycled rather than repeated**, so no branch predictor learns the answer: an
// interpreter that compares strings pays the comparison every time, and one that could hash the
// subject once would show it here.

kind(w) = w match
    "add" -> 1
    "sub" -> 2
    "mul" -> 3
    "div" -> 4
    "mod" -> 5
    _ -> 0

run(words)
    var total = 0
    var i = 0

    while i < 5000000
        total = total + kind(words[i % 6])
        i = i + 1

    total

print(run(["add", "sub", "mul", "div", "mod", "nope"]))
