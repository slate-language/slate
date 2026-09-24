// What a call does with the arguments it was given, on both back ends.
//
// **The call rule is JavaScript's at run time and the two back ends have to agree about it exactly.**
// A surplus argument is dropped and a parameter the call left out reads as the absence a missing
// field reads as -- neither machine refuses a count any more, so what is pinned here is what each
// call ANSWERS rather than what it refuses.
//
// **Every call with a wrong count goes through `anything`**, because the checker refuses most of
// them where they are written -- which is the good case, is TypeScript's half of the rule, and is
// pinned in the compiler's own suite. What is pinned here is the MACHINE's answer, for the calls a
// checker cannot see: a function reached through a value.

anything(v) = v

// -- the shapes a call can be wrong ---------------------------------------------------------------

one(a) = a
second(a, b) = b
two(a, b) = string(a) + "/" + string(b)
defaulted(a, b = 5) = string(a) + "+" + string(b)
gathering(a, b, ...rest) = string(a) + string(b) + toJSON(rest)
boxed(x) = [x]

// **A surplus is dropped**, whatever the callee is.
print(anything(one)(1, 2))
print(anything(defaulted)(1, 2, 3))
print(anything(gathering)(1, 2, 3, 4))

// **A function that takes NOTHING is the case the emitter used to leave unchecked**, having written
// no signature for an empty parameter list. It is also the commonest shape of the mistake: a
// framework handing props to a component that ignores them.
none() = "nothing wanted"

print(anything(none)({ start: 1 }))
print(anything(none)())

// A lambda written at the call site, and one bound to a name, read the same way.
print(anything((a) -> a)(1, 2))

val held = (a) -> a

print(anything(held)(1, 2))

// -- a parameter nobody gave reads as an absence ---------------------------------------------------

print(anything((a, b) -> b == null)(1))
print(anything((a, b) -> b ?? "absent")(1))
print(anything((a, b) -> if b then "yes" else "no")(1))

// Handing one back is refused at the `return`, in the same words on both.
print(anything(second)(1) catch e -> e.message)

// **And it goes no further than the read**, which is slate's own rule and is untouched: passing one
// on or putting one in a container is refused where it is attempted.
print(anything(two)(1) catch e -> e.message)
print(anything(boxed)() catch e -> e.message)

// -- a method and a maker --------------------------------------------------------------------------

class Box
    var size

    fits(self, thing) = string(self.size) + " " + string(thing)

val b = Box(2)

print(anything(b).fits("x", "spare"))
print(anything(Box)(1, 2).size)

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
// is counted by the checker; this is the other side of the same rule, and it is TypeScript's line in
// the same place -- a function of fewer parameters is assignable where more are supplied.
//
// What it buys is the shape a person actually writes: a handler that does not read the event, a
// `forEach` that does not read the element, a timer that ignores everything.
print(map([1, 2, 3], () -> 9))
print(map([1, 2, 3], (v) -> v * 2))
print(map([1, 2, 3], (v, i) -> v + i))
print(map([1, 2, 3], (v, i, all) -> v + all.length))
print(filter([1, 2, 3], () -> true))
print(reduce([1, 2, 3], (a) -> a, 0))
print(reduce([1, 2, 3], (a, b) -> a + b, 0))
print(sorted([3, 1, 2], () -> true))
print(every([1, 2], () -> true), some([1, 2], () -> false))

forEach([1], () -> print("forEach ran with nothing"))

// **A callback that declares MORE than the native can supply is no longer refused either** -- the
// parameter the native did not feed is simply absent, exactly as it is at an ordinary call. Neither
// of these reads the parameter it was not given.
print(map([1], anything((a, b) -> a)))
print(reduce([1], anything((a, b, c) -> a), 0))

// -- and a call that is right is still right --------------------------------------------------------

print(two(1, 2), defaulted(1), gathering(1, 2, 3, 4))
