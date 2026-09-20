// The JavaScript twin of branches.sl.
//
// JavaScript has no `match`, so the twin is a `switch`, which an engine is free to compile to a jump
// table or a chain of comparisons as it sees fit -- the same freedom `dispatch.js` takes. `continue`
// and `try`/`catch` are direct: JavaScript's own words for the same thing. The `if`-as-expression
// becomes JavaScript's `?:`, which is the nearest thing it has to an `if` that answers a value.
//
// Every JavaScript number is a double, but every value here stays an ordinary integer under 2^31 and
// the one product taken (`seed * 16807`) stays under 2^53, so this is exact integer arithmetic and
// prints the same answer as the other three.

function risky(r) {
    if (r === 0) throw new Error("boom");
    return 0;
}

function run() {
    let seed = 1;
    let i = 0;
    let flagCount = 0;
    let chainTotal = 0;
    let nestedCount = 0;
    let continueCount = 0;
    let exprSum = 0;
    let matchTotal = 0;
    let faultCount = 0;

    while (i < 2000000) {
        seed = (seed * 16807) % 2147483647;

        const r = seed % 1000;

        i = i + 1;

        if (r % 7 === 0) {
            flagCount = flagCount + 1;
        }

        if (r < 100) {
            chainTotal = chainTotal + 1;

            if (r % 13 === 0) {
                nestedCount = nestedCount + 1;
            }
        } else if (r < 400) {
            chainTotal = chainTotal + 2;
        } else if (r < 700) {
            chainTotal = chainTotal + 3;
        } else {
            chainTotal = chainTotal + 4;
        }

        if (r % 97 === 0) {
            continueCount = continueCount + 1;
            continue;
        }

        const k = r % 5;

        switch (k) {
            case 0: matchTotal = matchTotal + 10; break;
            case 1: matchTotal = matchTotal + 20; break;
            case 2: matchTotal = matchTotal + 30; break;
            case 3: matchTotal = matchTotal + 40; break;
            default: matchTotal = matchTotal + 50; break;
        }

        const bonus = r % 2 === 0 ? 1 : 2;

        exprSum = exprSum + bonus;

        if (i % 1000 === 0) {
            try {
                faultCount = faultCount + risky(r);
            } catch (e) {
                faultCount = faultCount + 1;
            }
        }
    }

    return flagCount + chainTotal * 3 + nestedCount * 7 + continueCount * 11 +
        exprSum * 13 + matchTotal * 17 + faultCount * 19;
}

console.log(run());
