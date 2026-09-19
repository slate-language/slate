// The JavaScript twin of strwalk.sl.
//
// **A JavaScript string is UTF-16 and `s[i]` reads one CODE UNIT in constant time.** Every character
// in this text is in the basic plane, so one unit is one character and the walk below counts exactly
// what the slate program counts -- which is why the text was chosen that way. An emoji would break
// the correspondence: it is one character in slate and two units here, and `s.length` would be a
// different number.
//
// **So this twin does less work than the slate program by construction**, storing two bytes per
// character rather than a variable one to four, and `s.length` is a field rather than anything that
// has to be counted.

function run(s) {
    let found = 0;
    let i = 0;

    while (i < s.length) {
        if (s[i] === "本") {
            found = found + 1;
        }

        i = i + 1;
    }

    return found;
}

const parts = [];

for (let k = 0; k < 1000; k++) {
    parts.push("日本語あいうえおかきく" + "さしすせそたちつてと");
}

console.log(run(parts.join("")));
