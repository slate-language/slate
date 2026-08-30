#!/usr/bin/env slate

// slate as a command: the shebang line above, the arguments a shell handed over, and the status this
// leaves behind. Make it executable and run it by name -- `chmod +x examples/script.sl`, then
// `./examples/script.sl a b c`.
//
// The `#!` line belongs to the kernel rather than to slate, and slate skips it. It is read at the
// very first byte of the file and nowhere else: `#` is not a comment here -- a comment is `//` -- and
// this did not make it one.

import { args, exit } from slate:process

// `args` is a VALUE, not a call, and it holds only what came after the program's own name. So
// `args[0]` is the first thing a person typed, where C, node and Python all hand a program its whole
// command line and begin by skipping past themselves.
if args.len() == 0
    print("usage: script.sl <word>...")
    print("       counts the letters in each word you give it")

    // A status a shell can act on. Everything printed above is still printed: `exit` unwinds the
    // program rather than stopping the process where it stands, so the answer arrives and then slate
    // leaves. A status outside 0 to 255 is refused rather than truncated.
    exit(0)

// An argument is an ordinary string, and `args` is an ordinary array.
var total = 0

for word in args
    print(word + ": " + string(len(word)))
    total = total + len(word)

print("total: " + string(total))

// Nothing below this line runs. Without an `exit` at all, a program that ran answers 0 anyway and one
// that faulted answers 1 -- `exit` is for the statuses a program chooses for itself.
exit(0)

print("never reached")
