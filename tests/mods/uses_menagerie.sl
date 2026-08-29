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
