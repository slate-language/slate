# The differential corpus

Each `p*.sl` here is a program whose output is **the same from the interpreter and from the
JavaScript back end**, and that is the whole of what they are for:

    slate p1.sl                  > want.txt
    slate js p1.sl -o p1.js
    qjs p1.js                    > got.txt
    diff want.txt got.txt

They are not run by `sysl test .`, because the suite has no JavaScript engine in it: running the
emitted code needs `sysl-lang/quickjs-ng` as a dependency of this repo, which moves the compiler
floor to 0.0.93 and puts `--include-path quickjs=…` on every test run. When that lands, these become
the differential suite and the diff above becomes an assertion.

Until then they are run by hand, and every one of them was: `wide.sl` is the fixture for a driver
test and the four numbered ones cover, in order, arithmetic and printing; patterns, `match`,
labelled loops, closures and `try`/`catch`; classes, generators, `with`, defaults and spread
arguments; and the `...` literals.
