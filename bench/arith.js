// The JavaScript twin of arith.sl. Every JavaScript number is a double, so this is real arithmetic
// where slate's and Lua's is integer -- the answer, 99,999,980,000,000, is well inside 2^53, so it
// is exact and prints the same.

function run() {
    let total = 0;
    let i = 0;

    while (i < 10000000) {
        total = total + i * 2 - 1;
        i = i + 1;
    }

    return total;
}

console.log(run());
