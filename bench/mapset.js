// The JavaScript twin of mapset.sl, using the host's own `Map` and `Set`.
//
// **They are not the same containers slate's are and the difference is the key rule**: JavaScript
// keys on SameValueZero, so two equal arrays are two keys and a class's `==` is never asked. Here
// every key is a small integer, where the two rules agree, so the comparison is fair for this
// program and would not be for one keyed by objects.

function run() {
    const m = new Map();
    const s = new Set();
    let i = 0;

    while (i < 2000000) {
        m.set(i % 1000, i);
        s.add(i % 1000);
        i = i + 1;
    }

    let total = 0;
    let k = 0;

    while (k < 1000) {
        total = total + m.get(k);

        if (s.has(k)) {
            total = total + 1;
        }

        k = k + 1;
    }

    return total;
}

console.log(run());
