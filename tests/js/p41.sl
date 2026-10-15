// A local that takes the name of something outside it, read ABOVE the line that declares it.
//
// **slate binds a name where its declaration stands, so the read above it is the outer one.** Only a
// LATER definition collides, and `val g = g()` -- a generator named and then run -- is an idiom. A
// JavaScript `const` binds for its whole block instead, so every one of these used to stop node with
// `Cannot access 'made' before initialization`. `js_spell.sysl` is what gives such a local a name of
// its own in the emitted program.

made() = 1

class Made
    var n

data Shape
    Circle(r)
    Square(side)

counting()
    yield 1
    yield 2

// -- a `val` and a `var` -------------------------------------------------------------------------

shadowedByVal()
    val x = made()
    val made = x + 1
    made

shadowedByVar()
    val x = made()
    var made = x + 1
    made += 10
    made

print(shadowedByVal(), shadowedByVar())

// -- a default reading the outer name, in front of a body declaring it ---------------------------

defaulted(n = made())
    val made = n + 1
    made

print(defaulted(), defaulted(5))

// -- in a lambda's body, and in a nested block ---------------------------------------------------

val inLambda = n ->
    val x = made()
    val made = x + n
    made

nested(flag)
    if flag
        val x = made()
        val made = x + 1
        return made
    0

print([1, 2].map(inLambda), nested(true), nested(false))

// -- a class and a data variant as the outer name ------------------------------------------------

classed()
    val p = Made(3)
    val Made = p.n + 1
    Made

dataed()
    val c = Circle(2)
    val Circle = c.r * 10
    Circle

print(classed(), dataed())

// -- the generator idiom, inside a function and at the top level ---------------------------------

stepped()
    val counting = counting()
    [counting.next().value, counting.next().value]

print(stepped())

val counting = counting()

print(counting.next().value, counting.next().value)

// -- what a function written in the block reads --------------------------------------------------
//
// **A lambda runs when it is called**, so one written above the declaration reads the block's own
// binding once that exists; two local functions calling each other are the ordinary case. And every
// binder below the declaration still shadows it.

deferred()
    val later = () -> made
    val x = made()
    val made = x + 41
    later()

mutual(n)
    val isEven = k -> if k == 0 then true else isOdd(k - 1)
    val isOdd = k -> if k == 0 then false else isEven(k - 1)
    isEven(n)

shadowedAfter()
    val x = made()
    val made = x + 1
    val f = made -> made * 100
    [made, f(3), [5].map(made -> made + made)]

print(deferred(), mutual(4), mutual(3), shadowedAfter())

// -- an annotated binding ------------------------------------------------------------------------
//
// **`val x: T = e` is a binding and its check travelling together**, so the read above it is still
// the outer name's and the check below it reads the local.

annotatedVal()
    val x = made()
    val made: integer = x + 1
    made

annotatedVar()
    val x = made()
    var made: integer = x + 1
    made += 10
    made

annotatedOwnInit()
    val made: integer = made() + 5
    made

print(annotatedVal(), annotatedVar(), annotatedOwnInit())

// -- a class and a data type taking a builtin's name, below a read of the builtin ----------------
//
// **A class's shape names the class**, so its test is the local class's and not the builtin's. A
// `data` line binds its shared object and then each variant, every variant reading the object above
// it.

val sized = Set([1, 2]).size

class Set
    var n

    doubled(self) = Set(self.n * 2)

print(sized, Set(3).n, Set(4).doubled().n, Set.test(Set(5)), Set.test(7), Set.name())

val counted = Map([[1, 2], [3, 4]]).size

data Map
    Leaf(v)
    Empty

print(counted, Leaf(3) is Leaf, Map.test(Empty), Map.test(Leaf(1)), Map.test(3), Map.name())

// -- a function written in the block, CALLED before the declaration has run ----------------------
//
// **What a deferred read finds is decided when it runs**: the outer binding until the local's
// declaration has executed, the local after it. So a lambda called during the local's own
// initialiser reads the outer name, and the same lambda called later reads the local.

val tier = "outer"

initialiser()
    val down = n -> if n == 0 then made() else down(n - 1)
    val made = down(3) + 1
    made

beforeAndAfter()
    val peek = () -> tier
    val first = peek()
    val tier = "inner"
    [first, peek(), tier]

onlyMention()
    val tier = (() -> tier + "!")()
    tier

nestedFunctions()
    val outerFn = () ->
        val innerFn = () -> tier
        innerFn()
    val tier = outerFn() + "+"
    [tier, outerFn()]

hoistedDefinition()
    val got = reader()
    val tier = "local"
    reader() = tier
    [got, reader()]

print(initialiser(), beforeAndAfter(), onlyMention())
print(nestedFunctions(), hoistedDefinition())

// A class is declared at the top level, so its method's outer binding is a builtin: `abs` below is
// the builtin while the `val` taking its name is being worked out.

class Probe
    var n

    measured(self) = abs(self.n)

val abs = Probe(-3).measured() + 10

print(abs)
