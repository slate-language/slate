#!/usr/bin/env slate

// slate as a scripting language, read by both back ends: the shebang line above, the arguments the
// command line carried, and the status the program leaves behind.
//
// Run it with arguments and compare the STATUS as well as the output, since the status is half of
// what this is about:
//
//     slate p9.sl one two three ; echo $?
//     slate js p9.sl -o p9.js && node p9.js one two three ; echo $?
//
// Both should print the same eight lines and both should leave with 3. Under `qjs` the arguments
// come off `scriptArgs` instead and the invocation is `qjs --std p9.js one two three`.

import { args, exit } from slate:process

print("how many: " + string(args.len()))

// The program's own name is NOT args[0], which is where this parts from C, node and Python.
print("first: " + (args[0] ?? "<none>"))
print("last: " + (args[args.len() - 1] ?? "<none>"))

// An argument is an ordinary string and goes wherever a string goes.
for a in args
    print("  " + upper(a))

// And `args` is an ordinary array: everything an array does, it does.
print("sorted: " + join(sorted(args), ","))

// Everything printed before the exit is still printed, which is the whole reason `exit` unwinds
// rather than stopping the process where it stands.
print("leaving with 3")

exit(3)

print("this line never runs")
