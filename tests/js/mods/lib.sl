// A module the JavaScript back end's tests import from.
//
// Its own fixture rather than one of `tests/mods/`, because what those pin is what the machine does
// with them: a test here quotes the emitted text line for line, so an edit made for the machine's
// sake would break a test about JavaScript for no reason a reader could see.

export val greeting = "hello"

export double(x) = x * 2

export type Point = { x: number, y: number }

// No `export`, so nothing outside this file can reach it -- and the emitted module has no field for
// it either.
quiet() = "unseen"
