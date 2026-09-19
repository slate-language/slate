// The JavaScript twin of arrays.sl. `for…of` is the walk, which is what slate's `for v in xs` is.

function build(n) {
    const xs = [];
    let i = 0;

    while (i < n) {
        xs.push(i * 2);
        i = i + 1;
    }

    return xs;
}

function byIndex(xs) {
    let total = 0;
    let i = 0;

    while (i < xs.length) {
        total = total + xs[i];
        i = i + 1;
    }

    return total;
}

function byWalk(xs) {
    let total = 0;

    for (const v of xs) {
        total = total + v;
    }

    return total;
}

function run() {
    const xs = build(500000);
    let total = 0;
    let turns = 0;

    while (turns < 10) {
        total = total + byIndex(xs) + byWalk(xs);
        turns = turns + 1;
    }

    return total;
}

console.log(run());
