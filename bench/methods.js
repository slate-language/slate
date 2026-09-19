// The JavaScript twin of methods.sl, written with a real `class` -- which is a prototype chain
// underneath, the same one indirection slate's proto is.

class Vec {
    constructor(x, y) {
        this.x = x;
        this.y = y;
    }

    dot(o) {
        return this.x * o.x + this.y * o.y;
    }

    scaled(k) {
        return this.x * k + this.y * k;
    }
}

function run() {
    const a = new Vec(2, 3);
    const b = new Vec(5, 7);
    let total = 0;
    let i = 0;

    while (i < 3000000) {
        total = total + a.dot(b) + b.scaled(1);
        i = i + 1;
    }

    return total;
}

console.log(run());
