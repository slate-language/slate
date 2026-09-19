// The JavaScript twin of strindex.sl.
//
// **`s[i]` is a constant-time read of a UTF-16 code unit**, so this walk is linear where slate's is
// quadratic. It is also the twin whose units differ: JavaScript counts code units and slate counts
// characters, which agree only because this text is ASCII.

function run(s) {
    let found = 0;
    let i = 0;

    while (i < s.length) {
        if (s[i] === "x") {
            found = found + 1;
        }

        i = i + 1;
    }

    return found;
}

const parts = [];

for (let k = 0; k < 1000; k++) {
    parts.push("abcdexfghi" + "jklmnxopqr");
}

console.log(run(parts.join("")));
