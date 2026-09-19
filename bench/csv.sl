// The realistic mix: generate a comma-separated text, then split it, convert its numbers and add
// them up -- which is most of what a program that reads a file actually does.
//
// **It is the only benchmark here that is more than one thing at once, and that is the point.** Two
// thirds of the others isolate a single operation so that a profile can attribute a cost; this one
// says whether the isolated costs add up to what ordinary code feels like. Splitting, converting and
// concatenating are all builtins, so a machine whose instruction loop is slow and whose builtins are
// compiled should do better here than anywhere else.

build(rows)
    var lines = []
    var i = 0

    while i < rows
        push(lines, string(i) + "," + string(i * 2) + ",name" + string(i % 100))
        i = i + 1

    lines.join("\n")

parse(text)
    var total = 0

    for line in text.split("\n")
        val parts = line.split(",")

        total = total + number(parts[0]) + number(parts[1]) + parts[2].length

    total

run()
    val text = build(20000)
    var total = 0
    var turns = 0

    while turns < 30
        total = total + parse(text)
        turns = turns + 1

    total

print(run())
