// The JavaScript twin of nested.sl: loops.js's loop inside a function that also holds a closure over
// one of its names.

function run(pairs) {
    let total = 0;
    let turns = 0;
    const scale = 1;
    const weigh = (v) => v * scale;

    while (turns < 6000) {
        for (const [a, b] of pairs) {
            total = total + weigh(a * b);
        }

        turns = turns + 1;
    }

    return total;
}

const pairs = [];

for (let i = 0; i < 1000; i++) {
    pairs.push([i, i + 1]);
}

console.log(run(pairs));
