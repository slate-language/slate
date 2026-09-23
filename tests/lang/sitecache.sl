// What a field read and a method call are allowed to REMEMBER, asked from the language.
//
// **The interpreter caches where a name was found, one cell per place in the program that reads
// one.** Every test below runs ONE such place twice with the answer changed in between, which is the
// only shape that can catch a cache handing back what it found last time. They are ordinary
// questions about an ordinary program -- all of them were true before the cache existed -- and they
// are written down because each is a way that remembering could be wrong while a program that reads
// one object of one shape still looked perfectly right.
//
// **`slate js` has no such cache and runs these too**, which is the point of this directory: what is
// under test is the language, so the file is also the check that the two back ends still agree.

import { spawn, send, ask } from slate:actor

readA(o) = o.a ?? "none"

readGreet(o) = o.greet

writeA(o, v)
    o.a = v
    o.a

class Box
    var n

    tell(self) = "class"

    get twice(self) = self.n * 2

    set twice(self, v)
        self.n = v / 2
end Box

// Two classes whose instances lay their fields out differently, so `proto` stands at one position in
// a `Tick` and at another in a `Tock`, and `kind` at one position in each class object.
class Tick
    var a

    kind(self) = "tick"
end Tick

class Tock
    var x
    var y
    var a

    kind(self) = "tock"
end Tock

callKind(v) = v.kind()

@test
ONE_PLACE_READS_TWO_SHAPES_AND_ANSWERS_FOR_EACH()
    // The same instruction, three objects, the field at a different position in each.
    assertEq(readA({ a: 1 }), 1)
    assertEq(readA({ b: 2, c: 3, a: 4 }), 4)
    assertEq(readA({ a: 5 }), 5)

@test
A_FIELD_ADDED_AFTER_A_READ_MISSED_IS_FOUND_BY_THE_NEXT_ONE()
    val o = { b: 1 }

    assertEq(readA(o), "none")

    o.a = 7

    assertEq(readA(o), 7)

@test
A_TABLE_THAT_OUTGREW_ITS_SMALL_CASE_IS_STILL_READ_IN_THE_RIGHT_PLACE()
    val o = { a: 1 }

    assertEq(readA(o), 1)

    var i = 0

    while i < 40
        o["k" + string(i)] = i
        i = i + 1

    assertEq(readA(o), 1)

    o.a = 2

    assertEq(readA(o), 2)
    assertEq(o["k39"], 39)

@test
A_WRITE_AT_ONE_PLACE_LANDS_IN_THE_RIGHT_FIELD_OF_EITHER_SHAPE()
    val p = { a: 0 }
    val q = { z: 9, a: 0 }

    assertEq(writeA(p, 1), 1)
    assertEq(writeA(q, 2), 2)
    assertEq(p.a, 1)
    assertEq(q.a, 2)
    assertEq(q.z, 9)

@test
A_WRITE_AT_A_PLACE_THAT_HAS_UPDATED_A_FIELD_CAN_STILL_MAKE_ONE()
    val p = { a: 0 }
    val q = { z: 9 }

    assertEq(writeA(p, 1), 1)
    assertEq(writeA(q, 2), 2)
    assertEq(q.z, 9)
    assertEq(q.a, 2)

@test
A_METHOD_REPLACED_ON_THE_CLASS_IS_THE_ONE_THE_NEXT_CALL_RUNS()
    val b = Box(1)

    assertEq(b.tell(), "class")

    Box.tell = self -> "replaced"

    assertEq(b.tell(), "replaced")

    Box.tell = self -> "class"

@test
A_FIELD_WRITTEN_ON_THE_OBJECT_WINS_OVER_THE_ONE_ITS_CLASS_SHARES()
    val b = Box(1)

    assertEq(b.tell(), "class")

    // Its own, so it takes no receiver -- and the call has to find it rather than the class's, which
    // is the one thing a remembered proto hop must never be allowed to decide on its own.
    b.tell = () -> "own"

    assertEq(b.tell(), "own")

@test
ONE_PLACE_CALLS_A_METHOD_ON_TWO_CLASSES_WHOSE_TABLES_DISAGREE()
    // A delegated call remembers TWO positions -- where `proto` sat on the receiver and where the
    // name sat on the class it reached -- and neither is right for the other class. One place
    // alternating between them is the only shape that says both are checked rather than believed.
    val a = Tick(1)
    val b = Tock(2, 3, 4)

    assertEq(callKind(a), "tick")
    assertEq(callKind(b), "tock")
    assertEq(callKind(a), "tick")
    assertEq(callKind(b), "tock")

@test
ONE_PLACE_READS_A_FIELD_THE_OBJECT_HAS_AND_THEN_ONE_IT_INHERITS()
    // A field the object holds itself is answered from the receiver's own table and a name it
    // inherits is answered by the walk, so these are two different paths through one place in the
    // program. Alternating is what says the first can never answer for the second.
    val own = { a: "own" }
    val inherited = { proto: { a: "shared" } }

    assertEq(readA(own), "own")
    assertEq(readA(inherited), "shared")
    assertEq(readA(own), "own")
    assertEq(readA(inherited), "shared")

@test
A_PROTO_CHANGED_UNDER_A_PLACE_IS_THE_ONE_THE_NEXT_READ_WALKS()
    val one = { greet: "one" }
    val two = { greet: "two" }
    val o = { proto: one }

    assertEq(readGreet(o), "one")

    o.proto = two

    assertEq(readGreet(o), "two")

    // And a field of its own still wins over both.
    o.greet = "mine"

    assertEq(readGreet(o), "mine")

@test
A_PROPERTY_IS_STILL_REACHED_AT_A_PLACE_THAT_HAS_READ_A_PLAIN_FIELD()
    val plain = { twice: 100 }
    val b = Box(4)

    assertEq(readTwice(plain), 100)
    assertEq(readTwice(b), 8)
    assertEq(readTwice(plain), 100)

@test
A_SETTER_IS_STILL_REACHED_AT_A_PLACE_THAT_HAS_WRITTEN_A_PLAIN_FIELD()
    val plain = { twice: 0 }
    val b = Box(0)

    writeTwice(plain, 50)
    writeTwice(b, 50)

    assertEq(plain.twice, 50)
    assertEq(b.n, 25)

readTwice(o) = o.twice

writeTwice(o, v)
    o.twice = v

data Coin
    Penny(worth)
    Nickel(worth)
end Coin

@test
A_DATA_VALUE_STILL_REFUSES_A_WRITE_AT_A_PLACE_THAT_HAS_WRITTEN_A_PLAIN_ONE()
    val plain = { worth: 1 }

    writeWorth(plain, 2)

    assertEq(plain.worth, 2)
    assertFaults(() -> writeWorth(Penny(1), 5), "a data value does not change")

writeWorth(o, v)
    o.worth = v

actor Tally
    var n = 0

    on bump(self, by)
        val b = Box(by)

        self.n = self.n + b.twice

    on sum(self) = self.n

@test
async AN_ACTOR_READS_ITS_OWN_FIELDS_AND_ITS_OWN_CLASSES() =
    // **A second line of execution has a runtime of its own**, so whatever a field read remembers is
    // that runtime's and not this one's. An actor that reads a field, a property and a class of its
    // own is the shape that would go wrong if the two ever shared one.
    val t = spawn(Tally)

    send(t.bump, 3)
    send(t.bump, 4)

    assertEq(await ask(t.sum), 14)

// **A method call on a builtin kind remembers the builtin it found, keyed on the KIND**, so one place
// in the program that meets a string and then an array has to answer each with its own.
firstOf(x) = x.at(0)

@test
A_METHOD_CALL_PLACE_THAT_MEETS_TWO_KINDS_ANSWERS_EACH_WITH_ITS_OWN() =
    assertEq([firstOf("abc"), firstOf([7, 8]), firstOf("xyz"), firstOf([1])], ["a", 7, "x", 1])

cutAt(x) = x.split(",")

@test
A_PLACE_THAT_FOUND_A_METHOD_ON_ONE_KIND_STILL_REFUSES_IT_ON_ANOTHER() =
    // The string's `split` is remembered first, so what is under test is that an array arriving at
    // the same place is asked the tables again rather than handed the string's answer.
    assertEq(cutAt("a,b"), ["a", "b"])
    assertFaults(() -> cutAt([1, 2]), "`split` is not something an array can do")
    assertEq(cutAt("c"), ["c"])

@test
A_NUMBER_OF_EITHER_KIND_TAKES_THE_SAME_REMEMBERED_METHOD() =
    // An integer and a real are one kind to the method tables, so one remembered answer serves both.
    val shown = [1, 2.5, 3].map((n) -> n.toString())

    assertEq(shown, ["1", "2.5", "3"])

// **A method found through a proto is answered from where the call found it last time, with nothing
// asked of the receiver's own table but whether it could hold the name at all.** Each test below
// changes what that answer should be between two calls at one place: the receiver gains the name,
// loses it again in a copy, is handed another proto, or is one of two instances only one of which
// holds the name itself.
callTell(b) = b.tell()

@test
A_METHOD_CALL_PLACE_THAT_HIT_THE_CLASS_FINDS_A_FIELD_THE_INSTANCE_GAINS_SINCE()
    val b = Box(1)

    assertEq(callTell(b), "class")
    assertEq(callTell(b), "class")

    b.tell = () -> "own"

    assertEq(callTell(b), "own")

@test
ONE_METHOD_CALL_PLACE_ALTERNATES_BETWEEN_AN_INSTANCE_THAT_SHADOWS_AND_ONE_THAT_DOES_NOT()
    val plain = Box(1)
    val shadowed = Box(2)

    shadowed.tell = () -> "own"

    assertEq([callTell(plain), callTell(shadowed), callTell(plain), callTell(shadowed)], ["class", "own", "class", "own"])

@test
A_COPY_WITHOUT_THE_SHADOWING_FIELD_REACHES_THE_PROTO_AGAIN()
    val shared = { tell: self -> "shared" }
    val o = { proto: shared, tell: () -> "own" }

    assertEq(callTell(o), "own")

    val bare = without(o, "tell")

    assertEq(callTell(bare), "shared")
    assertEq(callTell(bare), "shared")
    assertEq(callTell(o), "own")

greetOf(o) = o.greet()

@test
A_PROTO_REPLACED_UNDER_A_METHOD_CALL_PLACE_IS_THE_ONE_THE_NEXT_CALL_REACHES()
    val one = { greet: self -> "one" }
    val two = { greet: self -> "two" }
    val o = { proto: one }

    assertEq(greetOf(o), "one")
    assertEq(greetOf(o), "one")

    o.proto = two

    assertEq(greetOf(o), "two")

    // A method replaced on the proto it already reaches is the next one run as well.
    two.greet = self -> "two again"

    assertEq(greetOf(o), "two again")

@test
A_NEARER_PROTO_THAT_GAINS_THE_NAME_WINS_OVER_THE_ONE_A_PLACE_REACHED_BEFORE()
    val far = { greet: self -> "far" }
    val near = { proto: far }
    val o = { proto: near }

    assertEq(greetOf(o), "far")

    near.greet = self -> "near"

    assertEq(greetOf(o), "near")

    o.greet = () -> "own"

    assertEq(greetOf(o), "own")

remade(b, n) = b.new(n)

@test
A_CONSTRUCTOR_REACHED_THROUGH_AN_INSTANCE_IS_HANDED_NO_RECEIVER_AT_A_REMEMBERED_PLACE()
    // `new` is the one name the receiver rule does not reach -- a constructor runs before there is an
    // object to hand it -- so a place that has found it through a proto must not start handing one.
    val b = Box(1)

    assertEq(remade(b, 4).n, 4)
    assertEq(remade(b, 6).n, 6)
