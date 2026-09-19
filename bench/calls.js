// The JavaScript twin of calls.sl: a method call that allocates, once per iteration, with a real
// `class`.

class Counter {
    constructor(n) {
        this.n = n;
    }

    bump(by) {
        return new Counter(this.n + by);
    }
}

function run() {
    let c = new Counter(0);
    let i = 0;

    while (i < 2000000) {
        c = c.bump(1);
        i = i + 1;
    }

    return c.n;
}

console.log(run());
