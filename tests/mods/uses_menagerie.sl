import { Animal, Bird as Tweeter, Speaker, haunt, isGhost } from "./menagerie.sl"

val b = Tweeter.new("robin")

print(b.intro())

// The alias is what the test looks up, not the name the class was declared under.
print(b is Tweeter, b is Animal)

// A class annotation takes anything made from it, which is what a chain has to mean.
name(a: Animal) = a.name

print(name(b))

// `Ghost` was not exported, so here it is an ordinary binding rather than a test -- and the file that
// declared it can still tell.
print(haunt() match
    Ghost -> "bound"
    _ -> "tested")

print(isGhost(haunt()), isGhost(b))

// The interface crosses as an ordinary `export type`, and `Bird` keeps its promise with a method
// `Animal` supplies -- one link up the chain.
print(if b is Speaker then "speaks" else "silent")

// **A DECLARATION MAY NAME AN IMPORTED TYPE**, which is what lets a package build a vocabulary on
// another module's. It could not until 2026-09-02: the shape check ran before the imported types
// were opened, so every one of them looked like a name the declaration was binding -- while `is`
// on the very same name, one line below, worked.
type Winged = Tweeter
type Perched = { on: string, who: Animal }

print(b is Winged, { on: "wire", who: b } is Perched, { on: "wire", who: 5 } is Perched)

// **An imported class is a SHAPE VALUE under its alias**, the shape having been interned where the
// class was declared -- so the name it reports is the declared one and the test still finds the
// class in the module that wrote it, not in this file.
print(Tweeter.name(), Tweeter.test(b), Tweeter.test(Animal.new("cat")))
print(Speaker.test(b), Animal.mismatch(5))
