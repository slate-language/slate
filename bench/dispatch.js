// The JavaScript twin of dispatch.sl, written as a `switch` -- which is what a JavaScript program
// writes where a slate program writes `match`, and which an engine is free to compile to a jump
// table or to a chain of comparisons as it sees fit.

function kind(w) {
    switch (w) {
        case "add": return 1;
        case "sub": return 2;
        case "mul": return 3;
        case "div": return 4;
        case "mod": return 5;
        default: return 0;
    }
}

function run(words) {
    let total = 0;
    let i = 0;

    while (i < 5000000) {
        total = total + kind(words[i % 6]);
        i = i + 1;
    }

    return total;
}

console.log(run(["add", "sub", "mul", "div", "mod", "nope"]));
