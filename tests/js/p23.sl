// What a call is refused for, on both back ends.
//
// **Arity is a thing the two back ends used to disagree about, and not in wording -- in MEANING.**
// A JavaScript function ignores an argument it was not expecting and binds `undefined` for one it
// was not given, so an emitted `f(1, 2)` for a one-parameter `f` quietly dropped the `2` and ran,
// where the interpreter faulted. A call with too few failed further in, with a sentence about
// `undefined` that named neither the function nor the count.
//
// **Every one of these goes through `anything`**, because the checker refuses most of them before a
// program runs -- which is the good case and is not what this file is about. What is pinned here is
// the MACHINE's answer, for the calls a checker cannot see: a function reached through a value.

anything(v) = v

// -- the shapes a call can be wrong ---------------------------------------------------------------

one(a) = a
two(a, b) = string(a) + "/" + string(b)
defaulted(a, b = 5) = string(a) + "+" + string(b)
gathering(a, b, ...rest) = string(a) + string(b) + toJSON(rest)

print(anything(one)() catch e -> e.message)
print(anything(one)(1, 2) catch e -> e.message)
print(anything(two)(1) catch e -> e.message)
print(anything(defaulted)(1, 2, 3) catch e -> e.message)
print(anything(gathering)(1) catch e -> e.message)

// **A function that takes NOTHING is the case the emitter used to leave unchecked**, having written
// no signature for an empty parameter list -- so this is the one that was silent rather than merely
// worded differently. It is also the commonest shape of the mistake: a framework handing props to a
// component that ignores them.
none() = "nothing wanted"

print(anything(none)({ start: 1 }) catch e -> e.message)
print(anything(none)())

// -- what is named, and what cannot be ------------------------------------------------------------

// **A lambda written at the call site keeps the old wording**, there being nothing to name and the
// caret already pointing at it.
print(anything((a) -> a)(1, 2) catch e -> e.message)

// A lambda BOUND to a name has that name, which is what a reader would look for.
val held = (a) -> a

print(anything(held)(1, 2) catch e -> e.message)

// -- a method and a maker --------------------------------------------------------------------------

class Box
    var size

    fits(self, thing) = string(self.size) + " " + string(thing)

val b = Box(2)

print(anything(b.fits)() catch e -> e.message)
print(anything(Box)(1, 2) catch e -> e.message)

// -- the two other things said about a callee ------------------------------------------------------

// **A named argument names a parameter, so the sentences about one name the FUNCTION too** -- and
// they were the same divergence: the interpreter said `` `a function` `` where the emitted program
// said `` `$t21` ``, a temporary nobody wrote.
print(gathering(1, b = 2) catch e -> e.message)
print(two(1, c = 2) catch e -> e.message)
print(anything((a) -> a)(b = 1) catch e -> e.message)

// And a named argument that is right still places itself.
print(defaulted(b = 9, a = 1))

// -- a CALLBACK is a different question from a call ------------------------------------------------

// **A native hands a callback as many arguments as the callback declares.** A call the program WROTE
// is strict, above; this is the other side of the same rule, and it is TypeScript's line in the same
// place -- a function of fewer parameters is assignable where more are supplied, and a direct call
// with the wrong count is an error.
//
// What it buys is the shape a person actually writes: a handler that does not read the event, a
// `forEach` that does not read the element, a timer that ignores everything.
print(map([1, 2, 3], () -> 9))
print(map([1, 2, 3], (v) -> v * 2))
print(filter([1, 2, 3], () -> true))
print(reduce([1, 2, 3], (a) -> a, 0))
print(reduce([1, 2, 3], (a, b) -> a + b, 0))
print(sorted([3, 1, 2], () -> true))
print(every([1, 2], () -> true), some([1, 2], () -> false))

forEach([1], () -> print("forEach ran with nothing"))

// **A callback that declares MORE than the native can supply is still a fault, and it names the
// NATIVE** -- the reader's function is not wrong, and the surface they attached it to cannot feed
// it, which is what they need to be told.
print(map([1], anything((a, b) -> a)) catch e -> e.message)
print(reduce([1], anything((a, b, c) -> a), 0) catch e -> e.message)
print(forEach([1], anything((a, b) -> a)) catch e -> e.message)

// -- and a call that is right is still right --------------------------------------------------------

print(two(1, 2), defaulted(1), gathering(1, 2, 3, 4))
