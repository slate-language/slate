// The JavaScript twin of closures.sl. The answer, 23,999,994,000,000, is inside 2^53.

function run() {
    let total = 0;
    let turns = 0;
    const scale = 3;
    const weigh = (v) => v * scale;

    while (turns < 4000000) {
        total = total + weigh(turns);
        turns = turns + 1;
    }

    return total;
}

console.log(run());
