// The JavaScript twin of fields.sl.
//
// **This is the benchmark a V8 shape and its inline caches were built for**, so the jitless column
// is the interesting one: even without generated code, Ignition caches the lookup against the
// object's hidden class rather than hashing the name each time.

function run() {
    const o = { a: 0, b: 1, c: 2 };
    let i = 0;

    while (i < 5000000) {
        o.a = o.a + o.b + o.c;
        i = i + 1;
    }

    return o.a;
}

console.log(run());
