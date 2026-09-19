// Recursion, which is the call benchmark that cannot be turned into a loop by anybody's compiler.
//
// **What it measures that `funcs.sl` does not is DEPTH.** Every call here pushes a frame that is
// still standing when the next one is made, so a machine paying anything per frame beyond the
// arguments -- a scope object, a handler record, a bounds check that grows -- pays it thirty-four
// deep rather than one deep. `fib(33)` makes 11,405,773 calls.

fib(n) = if n < 2 then n else fib(n - 1) + fib(n - 2)

print(fib(33))
