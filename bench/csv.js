// The JavaScript twin of csv.sl.
//
// `Number(s)` rather than `parseInt` -- slate's `number` reads the whole string or faults, which is
// `Number`'s rule and not `parseInt`'s.
//
// The totals here stay inside 2^53.

function build(rows) {
    const lines = [];

    for (let i = 0; i < rows; i++) {
        lines.push(String(i) + "," + String(i * 2) + ",name" + String(i % 100));
    }

    return lines.join("\n");
}

function parse(text) {
    let total = 0;

    for (const line of text.split("\n")) {
        const parts = line.split(",");

        total = total + Number(parts[0]) + Number(parts[1]) + parts[2].length;
    }

    return total;
}

function run() {
    const text = build(20000);
    let total = 0;
    let turns = 0;

    while (turns < 30) {
        total = total + parse(text);
        turns = turns + 1;
    }

    return total;
}

console.log(run());
