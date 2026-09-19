// The JavaScript twin of reals.sl. This is the one benchmark where JavaScript's single number type
// costs it nothing: every value here was going to be a double anyway, so unlike arith.js there is no
// promotion and no integer type being given up.

function run() {
    let total = 0;
    let i = 0;

    while (i < 10000000) {
        total = total + i * 1.5 - 0.5;
        i = i + 1;
    }

    return total;
}

console.log(run().toFixed(1));
