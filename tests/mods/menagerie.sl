// Classes crossing a file, which is the case where a class is two things under one name: a value
// other files reach for, and a type other files test against.

// An interface: a `type` over function fields. A class promises one with `is`, and the promise is
// checked where the class is written rather than where somebody first wanted the method.
export type Speaker = { speak: function }

export class Animal is Speaker
    val legs = 4

    new(name) = { name: name }

    speak(self) = "..."

    intro(self) = s"${self.name} says ${self.speak()} on ${self.legs} legs"

export class Bird from Animal is Speaker
    val legs = 2

    new(name) = { name: name }

    speak(self) = "tweet"

// Not exported, so another file sees neither the value nor the type.
class Ghost from Animal
    speak(self) = "boo"

export haunt() = { name: "spook", proto: Ghost }

export isGhost(v) = v is Ghost
