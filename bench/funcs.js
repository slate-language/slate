// The JavaScript twin of funcs.sl. The answer, 8,000,010,000,000, is inside 2^53 and so is every
// running total on the way there, which is what keeps double arithmetic exact here.

function add3(a, b, c) {
    return a + b + c;
}

function run() {
    let total = 0;
    let i = 0;

    while (i < 4000000) {
        total = total + add3(i, 1, 2);
        i = i + 1;
    }

    return total;
}

console.log(run());
