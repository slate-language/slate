// A type declared or imported under one of slate's own kind words.
//
// **A local wins**: a name in a pattern is shadowed exactly as it is everywhere else, so where this
// file has a `Set`, `is Set`, `x: Set`, a `match` arm and `Set.test` all mean the declaration. The
// parser reads a kind word before anything is in scope, so `resolve_pattern` is where the
// declaration is found -- and both back ends resolve through it.

import { Map, Ledger as array, aBuiltinSet, isTheSetKind } from "./mods/kinds.sl"

class Set
    var n

data period
    Weekly
    Monthly(day)

type integer = { count: number }

// -- `is` ----------------------------------------------------------------------------------------

print(Set(4) is Set, Map(1) is Map, array(0) is array, Weekly is period, { count: 2 } is integer)
print(aBuiltinSet() is Set, [1] is array, 3 is integer, Set(4) is Map)

// -- an annotation -------------------------------------------------------------------------------

sizeOf(m: Map) = m.size
countOf(c: integer) = c.count
dayOf(p: period) = p match
    Monthly(d) -> d
    _ -> 0

print(sizeOf(Map(7)), countOf({ count: 8 }), dayOf(Monthly(9)), dayOf(Weekly))

// -- a `match` arm -------------------------------------------------------------------------------

which(v) = v match
    Set -> "the class"
    Map -> "the import"
    array -> "the renamed import"
    period -> "the data type"
    integer -> "the alias"
    _ -> "something else"

print(which(Set(1)), which(Map(1)), which(array(1)), which(Monthly(1)), which({ count: 1 }))
print(which(aBuiltinSet()), which(5), which([5]))

// -- the type as a value -------------------------------------------------------------------------

print(Set.test(Set(1)), Set.test(aBuiltinSet()), Map.test(Map(2)), period.test(Weekly))
print(Set.mismatch(Set(1)).length, Set.mismatch(aBuiltinSet()).length > 0)

// -- a parameter of the same name shadows the class in its turn ---------------------------------

shadowedAgain(Set, v) = v is Set

print(shadowedAgain(1, Set(1)))

// -- the control: a file that declares no `Set` still means the kind -------------------------------

print(isTheSetKind(aBuiltinSet()), isTheSetKind(Set(1)))
