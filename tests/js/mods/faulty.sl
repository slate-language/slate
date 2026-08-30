// A fault raised in one file and caught in another.
//
// **What it pins is that the fault names THIS file**, which is the whole reason a marker in a program
// of several files carries the file as well as the line: the function runs under a caller written
// somewhere else, and a `catch` reading the caller's file would be reading a file the fault has
// nothing to do with.

export boom(x) = x / 0
