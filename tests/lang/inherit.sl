// A subclass is built through its base, which is JavaScript's rule: one with no `new` of its own runs
// the base's `new` with the same arguments, the subclass's instance as `self`, then puts its own
// initialised fields on and the subclass as the proto. One that writes its own `new` starts from what
// every base's initialisers make. Both hold for a base in this file, across a file, reached through a
// module object, or chosen while the program runs.

import { Notes, Keeper } from "./lib/notes.sl"
import * as notes from "./lib/notes.sl"

class Ledger
    var served = 0

    show(self, req) = 2

    bump(self)
        self.served += 1

class Archive from Ledger
    show(self, req) = 4

class Vault from Archive
    var sealed = true

class Shelf from Notes
    show(self, req) = 4

class Stack from Shelf
    var depth = 3

class Base
    var log = []

    new(var n)
        self.log.push(s"base ${n} ${self is Top}")

    describe(self) = s"${self.n} ${self.log}"

class Mid from Base
    var extra = 7

    mid(self) = self.extra

class Top from Mid
    top(self) = "top"

class Plain
    new(v) = { v: v }

    get(self) = self.v

class Wrapped from Plain
    twice(self) = self.v * 2

class Point
    var x
    var y

    sum(self) = self.x + self.y

class Named from Point
    var label = "p"

    tag(self) = s"${self.label}${self.sum()}"

class Own from Ledger
    var mine = 1

    new(var k)
        self.served += 100

    show(self, req) = self.served + self.k + self.mine

class Holder
    var a
    var b = 5

class HeldOwn from Holder
    new(var z)
        self.seen = self.b

class Via from notes.Keeper
    tally(self) = self.log.length

pick(flag) = if flag then Notes else Keeper

class Chosen from pick(false)
    var x = 1

class Shape
    describe(self) = "a shape"

class Hollow from Shape

@test
A_SUBCLASS_WITH_NO_new_IS_AN_INSTANCE_OF_ITSELF() =
    assertEq([Archive().show(0), Archive() is Archive], [4, true])

@test
IS_ANSWERS_AT_EVERY_LEVEL_OF_A_SAME_FILE_CHAIN() =
    val v = Vault()

    assertEq([v is Vault, v is Archive, v is Ledger, v.show(0), v.sealed], [true, true, true, 4, true])
    assertEq([Archive() is Vault, Ledger() is Archive], [false, false])

@test
IS_ANSWERS_AT_EVERY_LEVEL_OF_AN_IMPORTED_CHAIN() =
    val s = Stack()

    assertEq([s is Stack, s is Shelf, s is Notes, s.show(0), s.depth, s.served], [true, true, true, 4, 3, 0])
    assertEq([Shelf() is Stack, Notes() is Shelf], [false, false])

@test
AN_INHERITED_METHOD_MUTATES_A_BASE_VAR_ON_THE_SUBCLASS_INSTANCE() =
    val a = Vault()
    val s = Stack()

    a.bump()
    a.bump()
    s.bump()
    assertEq([a.served, s.served, Ledger().served, Notes().served], [2, 1, 0, 0])

@test
EACH_INSTANCE_GETS_ITS_OWN_BASE_VAR() =
    val one = Top(1)
    val two = Top(2)

    assertEq([one.describe(), two.describe()], ["1 [\"base 1 true\"]", "2 [\"base 2 true\"]"])

@test
A_HAND_WRITTEN_BASE_new_RUNS_ITS_BODY_WITH_THE_SUBCLASS_INSTANCE_AS_self() =
    val t = Top(3)

    assertEq([t.describe(), t.mid(), t.top()], ["3 [\"base 3 true\"]", 7, "top"])
    assertEq([t is Top, t is Mid, t is Base], [true, true, true])
    assertEq([Base(9) is Top, Base(9).describe()], [false, "9 [\"base 9 false\"]"])

@test
A_PLAIN_FORM_BASE_new_INHERITED_MAKES_A_SUBCLASS_INSTANCE() =
    val w = Wrapped(5)

    assertEq([w.get(), w.twice(), w is Wrapped, w is Plain, Plain(1) is Wrapped], [5, 10, true, true, false])

@test
IN_FINDS_AN_ADDED_METHOD_ON_THE_SUBCLASS_ONLY() =
    assertEq(["tag" in Named(1, 2), "sum" in Named(1, 2), "tag" in Point(1, 2)], [true, true, false])

@test
A_SUBCLASS_VAR_WITH_AN_INITIALISER_IS_NOT_A_PARAMETER() =
    assertEq([Named(1, 2).tag(), Named(1, 2, "q").tag()], ["p3", "p3"])

@test
A_POSITIONAL_PATTERN_SEES_THE_SUBCLASS_S_OWN_FIELDS_ONLY() =
    val told = Named(1, 2) match
        Named(l) -> l
        _ -> "no"

    assertEq(told, "p")

@test
A_SUBCLASS_WITH_ITS_OWN_new_STARTS_FROM_THE_BASE_INITIALISERS() =
    val o = Own(10)

    assertEq([o.show(0), o is Own, o is Ledger], [111, true, true])

@test
A_BASE_VAR_WITH_NO_INITIALISER_STAYS_ABSENT_UNDER_A_SUBCLASS_new() =
    val h = HeldOwn(1)

    assertEq([h.b, h.z, h.seen, has(h, "a"), h is HeldOwn, h is Holder], [5, 1, 5, false, true, true])

@test
A_BASE_REACHED_THROUGH_A_MODULE_OBJECT_IS_BUILT_THROUGH() =
    val v = Via(8)

    assertEq([v.tally(), v.n, v is Via, v is Keeper], [1, 8, true, true])

@test
A_COMPUTED_BASE_IS_BUILT_THROUGH() =
    val c = Chosen(4)

    assertEq([c.n, c.x, c.log, c is Chosen, c is Keeper], [4, 1, ["kept 4"], true, true])

@test
A_SUBCLASS_WITH_NOTHING_TO_MAKE_OVER_A_BASE_WITH_NO_new_SAYS_SO() =
    assertEq(Hollow() catch e -> e.message, "class `Hollow` has nothing to make -- it declares no fields and writes no `new`, and what it comes from has no `new` either. Give it a field with `var`, write a `new`, or make one with `{ proto: Hollow }`")
