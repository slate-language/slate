// The JavaScript twin of loops.sl. `for (const [a, b] of pairs)` is array destructuring in the loop
// head, which is what slate's `for [a, b] in pairs` is -- the one twin here that spells it the same
// way.

function run(pairs) {
    let total = 0;
    let turns = 0;

    while (turns < 8000) {
        for (const [a, b] of pairs) {
            total = total + a * b;
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
