// The JavaScript twin of globals.sl: arith.sl's loop with every name at module top level.
//
// `var` at the top of a script makes a property of the global object, which is the closest thing
// JavaScript has to slate's module-level binding -- a named lookup rather than a slot.

var total = 0;
var i = 0;

while (i < 6000000) {
    total = total + i * 2 - 1;
    i = i + 1;
}

console.log(total);
