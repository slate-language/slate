// The JavaScript twin of strings.sl.
//
// **AN ENGINE MAY MAKE THIS LINEAR AND slate's IS QUADRATIC, WHICH IS THE POINT OF THE FILE.** V8
// represents the result of a concatenation as a rope -- two pointers rather than a copy -- and
// flattens it only when somebody reads the characters. So the same source text is O(n) here and
// O(n squared) in slate and in Lua, and the ratio this benchmark reports is a comparison of
// STRATEGIES rather than of speed at one operation.
//
// `.length` is UTF-16 code units and slate's is characters; the text is ASCII, so they agree.

function run() {
    let out = "";
    let i = 0;

    while (i < 150000) {
        out = out + "x" + String(i % 10);
        i = i + 1;
    }

    return out.length;
}

console.log(run());
