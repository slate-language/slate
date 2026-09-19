// The JavaScript twin of options.sl. Destructuring with defaults in the parameter list is what slate
// writes as `val { width = 10, height, scale = 2 } = opts`, and the rule is the same one: the
// default is taken where the property is absent or `undefined`, not where it is falsy.

function sized({ width = 10, height, scale = 2 }) {
    return width * height * scale;
}

function run(given, partial) {
    let total = 0;
    let turns = 0;

    while (turns < 2000000) {
        total = total + sized(given) + sized(partial);
        turns = turns + 1;
    }

    return total;
}

console.log(run({ width: 3, height: 4, scale: 5 }, { height: 4 }));
