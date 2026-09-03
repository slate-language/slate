# Objects

An object is a collection of fields.

```
{ name: "ada", born: 1815 }
{ name }                        // shorthand for `{ name: name }`
{ "two words": 1 }
```

**A key in a literal is a name or a string**, and nothing else — a number there is a parse error. A key
written through an index may be **any value**, and stays that value:

```
var q = {}
q[42] = "answer"
print(q)                        // {42: "answer"}
```

That is why [`toJSON`](../library/globals.md) refuses a non-string key rather than rendering it: `{ 1: "a" }`
and `{ "1": "a" }` are two objects and would be one document.

Objects are reference types and [compare by their contents](values.md).

`keys(o)`, `values(o)`, `entries(o)` and `has(o, k)` are how a program walks one; `entries` is what
makes a destructuring `for` head worth having:

```
for [k, v] in entries(o)
    print(k, v)
```

`o with { f: v }` answers a **copy** with `f` changed. There is no spread in a literal — `with` is it.

## `proto`

**`proto` is an ordinary field, and a lookup that misses carries on into it:**

```
val Shape = {
    describe: self -> s"${self.kind} with area ${self.area()}",
    kind: "shape"
}

val Square = { proto: Shape, kind: "square", area: self -> self.side * self.side }

square(side) = { side: side, proto: Square }

print(square(4).describe())     // square with area 16
```

**No syntax and no new kind of value.** A proto may have a proto, so chains and overriding come free;
`describe` lives on `Shape` and calls `area`, which only the concrete shapes have, so the call goes back
down to whichever object it started from. That is dispatch, and it needed no keyword.

**It is also what makes objects affordable.** Three methods written as captured closures cost three
closures *per instance*; on a proto they cost three once.

An [object pattern](patterns.md) counts a field a proto supplies, a pattern asking whether the value
*has* the field — which is the question `.` answers. (JavaScript splits the same seam and puts `in` on
this side of it.)

## The receiver rule

**A method reached through a proto is handed the object it was found on.** One `describe` serves every
shape, so it cannot have captured a particular one — it has to be told, and `self` is an ordinary first
parameter.

**A method stored on the object itself has already captured what it needs and is given nothing extra:**

```
counter() =
    var n = 0
    var c = {}

    c.bump = () ->
        n += 1
        n

    c
```

That is not two rules but one: **captured methods take no receiver, shared ones must.**

**Only `o.m(...)` passes a receiver.** `o.m` on its own hands back the bare function, so taking a method
off an object and calling it later is allowed and gives you what you took.

## Operator hooks

An object may answer for an operator. The word is the method's name, and a [class](classes.md) body
writes one with the definition syntax it already has:

```
class Money
    var cents

    plus(self, o)    = Money(self.cents + o.cents)
    times(self, n)   = Money(self.cents * n)
    negated(self)    = Money(-self.cents)
    compare(self, o) = self.cents - o.cents      // `<`, `<=`, `>` and `>=` read its sign
```

| hook | operator |
|---|---|
| `plus` | `+` |
| `minus` | `-` |
| `times` | `*` |
| `dividedBy` | `/` |
| `remainder` | `%` |
| `negated` | prefix `-` |
| `compare` | `<`, `<=`, `>`, `>=` |
| `equals` | `==`, `!=` |
| `hash` | a table key |

**Ordering is one hook and not four**, so a type cannot order inconsistently with itself. `==` keeps
`equals`, because a type whose ordering is coarser than its equality is an ordinary thing to want.

**The left operand decides and the right is never asked** — `equals`'s rule already — so there is no
reflected form and `2 * money` is a fault.

**A hook is the last thing tried**, so none can shadow what an operator means.

A type that writes `equals` should write `hash` beside it, or two equal values will not find each other
in a table.

## `toString` and `toJSON`

A class may say how it **prints** and how it **encodes**, which is what a value object needs to stop
leaking the fields it is made of:

```
class Money
    var cents

    toString(self) = "$" + string(self.cents / 100)
    toJSON(self)   = string(self.cents / 100)

print(Money(150))                       // $1
print(toJSON({ paid: Money(150) }))     // {"paid":"1"}
```

**Both replace everything below them at every depth**, so a value inside an array or a response body
renders the way its class says rather than only when printed on its own.

Without `toJSON`, a class instance and a [data variant](data-types.md) encode as their own fields —
`Circle(3)` is `{"r":3}` — and never as the chain they hang from.

## Identity

**The proto is the identity**, and [`class`](classes.md) is what lets `is` ask about it. Written by
hand, `p.proto == Point` is the closest an object literal gets — and it is not quite `instanceof`: `==`
on objects is deep, so it answers true for anything holding the same fields, and it looks exactly one
link up the chain.
