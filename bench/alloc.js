// The JavaScript twin of alloc.sl.
//
// **This is the benchmark a generational collector was built for**, so it is the one where V8's
// scavenger has the clearest advantage over a mark-sweep: nothing here survives its own iteration,
// and a copying young generation pays for the survivors rather than for the garbage.
//
// The answer, 9,000,000,000,000, is inside 2^53.

function run() {
    let total = 0;
    let i = 0;

    while (i < 3000000) {
        const p = { x: i, y: i + 1 };

        total = total + p.x + p.y;
        i = i + 1;
    }

    return total;
}

console.log(run());
