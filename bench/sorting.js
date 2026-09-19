// The JavaScript twin of sorting.sl.
//
// **`sort` with no comparator sorts by STRING**, which is JavaScript's own trap and would not be the
// same work at all, so `(a, b) => a - b` is written out. That means every comparison here calls back
// into the program where slate's and Lua's compare numbers inside the builtin -- a real difference,
// and the honest one: it is what a JavaScript program has to write to sort numbers.
//
// `slice()` is the copy, `sort` being in place.

function build(n) {
    const xs = [];
    let seed = 1;

    for (let i = 0; i < n; i++) {
        seed = (seed * 16807) % 2147483647;
        xs.push(seed);
    }

    return xs;
}

function run() {
    const xs = build(20000);
    let total = 0;
    let turns = 0;

    while (turns < 200) {
        const ys = xs.slice().sort((a, b) => a - b);

        total = total + ys[0] + ys[19999];
        turns = turns + 1;
    }

    return total;
}

console.log(run());
