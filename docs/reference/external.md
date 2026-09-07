---
title: External
weight: 175
---

# External

```
external localStorage
```

**`external` names a value of the JavaScript host and binds it to a slate name.** It is the door
through which a browser API or an npm package reaches a program, and it is a *language* feature
rather than a library one: what used to need a hand-written builtin in the back end is a package's own
line now. **The document is the worked example** — `slate:dom` was forty-four such builtins and is
[the `dom` package](../library/dom.md), written in slate over this declaration.

**It is the JavaScript host's alone.** Under the interpreter the declaration is accepted and every
operation that would touch the host faults, naming the command — the program is correct and the way it
was run is the mistake.

## The declaration

```slate
external localStorage
external ResizeObserver
external clipboard = "navigator.clipboard"
```

**A bare name reads that name off the global object; a `=` names a dotted path instead** and binds
the last thing on it under the slate name on the left. Nothing else is a path: there are no
arguments, no call, and no subscript in one — a path is how a global is *reached*, and everything
after that is an ordinary operation on the value.

**A declaration stands at the top level of a file and nowhere else**, which is where `import` stands
and for the same reason: it says what the file is built on. One inside a function is refused where it
is written.

```slate
main()
    external localStorage

    print(1)

main()
```

```error
top level
```

**The path is read where the declaration stands, and a path that names nothing is a fault** saying so
and quoting the path. A global that does not exist is nearly always a program in the wrong host — a
node build reaching for `document`, a page reaching for `process` — and the earliest place that can
be said is the line that asked for it.

**The name binds like a `val`.** It is immutable, it is exported and imported like any other name,
and it shadows and is shadowed by the ordinary rules. A declaration is not a type, an interface, or a
promise about what the host value can do: it says only *where it came from*.

## What an external is

**An external is one value kind and it is opaque.** It is not `any`, it is not an object, and it is
not a bag slate can look inside. What can be done with one is a closed list, and everything on that
list is an operation the *host* performs:

| | |
|---|---|
| `x.name` | read a property |
| `x.name = v` | write a property |
| `x[k]` and `x[k] = v` | the same two by computed key |
| `x.name(a, b)` | call a method, with `x` as the receiver |
| `x(a, b)` | call it, with the object its path named it from as the receiver |
| `x.new(a, b)` | construct with it — JavaScript's `new` |
| `x is external` | the type test |
| `x == y` | identity |

Everything else is refused, and the two halves of that are different in kind. **Arithmetic,
comparison, iteration and indexing-as-a-sequence have no meaning on one**, and the checker refuses
them before the program runs:

```slate
external localStorage

print(localStorage + 1)
```

```error
does not apply to external
```

**And a structural pattern simply does not match**, because nothing a pattern does may fault. An
external matches a bare name, `_`, and no other pattern:

```slate
external localStorage

print(localStorage match
    n @ number -> "a number"
    { length } -> "an object with a length"
    _ -> "only the name matched")
```

```output
only the name matched
```

**An external is a VALUE, so storing one is ordinary.** It goes in an array, in a field, in a `Map`,
through a function and back out — the restriction is on *operations*, never on travel. A handle that
could not be kept would be no use to a program that has to hold a `ResizeObserver` for as long as the
element it watches.

```slate
external localStorage

val kept = [localStorage]

print(kept.length, kept[0] == localStorage, localStorage is external)
```

```output
1 true true
```

**`==` is identity and there is no other equality**, JavaScript's own `===` for objects being exactly
that. Two declarations of one path are one host value and compare equal; nothing else does.

**`print` says `<external Name>`** where the host offers a constructor name — `<external Storage>`
for `localStorage`, `<external ResizeObserver>` for one of those — and `<external>` where it offers
none. It is a debugging sentence and not a reading: nothing about a host object can be printed, and a
program that wants a field's value asks for the field.

## What crosses the boundary

**The invariant is one sentence: no foreign object ever becomes a slate value except as an
external.** Nothing that came from the host is ever unwrapped into something slate owns, and
everything in the two tables below follows from it.

**Outward — a slate value handed to the host:**

| slate | JavaScript |
|---|---|
| `null` | `null` |
| a boolean | a boolean |
| an integer | a `number`, and one too large to be exact is a fault rather than a rounding |
| a real | a `number` |
| a string | a string |
| an array | a new JavaScript array, each element crossing by this table |
| an object | a new plain object, each value crossing by this table |
| a function | a JavaScript function |
| a promise | a JavaScript promise |
| an external | the host value itself |
| anything else | a fault naming the kind |

**An array and an object are COPIED, and that is deliberate.** slate's array is a JavaScript array on
this host and its object is a table the runtime owns, so handing either straight out would put slate's
own representation where the host can write to it — a `fields` map is not something an API can read,
and a shared array is two languages mutating one thing under two sets of rules. A copy is one pass
over what is being handed over anyway, and it keeps the boundary a boundary. **The copy is not a
snapshot the host keeps in step with**: a change on either side after the call is not seen by the
other.

**A regular expression, a socket, a set, a map, a date, a duration and a class instance do not
cross.** Each is a slate value with an implementation the host has no reading of, and a fault naming
the kind is worth more than a plausible-looking object with nothing behind it. What crosses instead
is what the program means: the pattern's text, the numbers a date holds, an array built from the set.

**Inward — a host value handed back:**

| JavaScript | slate |
|---|---|
| `undefined` | `null` |
| `null` | `null` |
| a boolean | a boolean |
| a `number` | an integer where it is whole, a real otherwise |
| a `bigint` | an integer |
| a string | a string |
| a thenable | a promise, whose value crosses by this table |
| anything else | an external |

**Everything that is not a primitive stays external, and that is the invariant read backwards.** An
array comes back external, an object comes back external, a function comes back external — read
through the same property and call operations as anything else. There is no unwrapping and no
conversion at the door, so nothing the host owns can be mistaken for something slate owns.

**A whole `number` is an integer and a fractional one is a real.** JavaScript has one number and
slate has two, so
something has to decide, and the value is the only evidence there is — a length, a child count, a
`clientWidth` are what a program reads off a host most often, and every one of them is a count a
loop is about to be written over. A real there would make `0..<n` a fault in the ordinary case.

**`undefined` becomes `null`, and that is slate's rule rather than a convenience.** slate's own
`undefined` exists only as the immediate answer to a read that found nothing and may not be stored
anywhere; a host property that is absent and one that holds `undefined` are the same read in
JavaScript, so slate cannot honestly say which happened. `null` is a value a program can keep, and
`x.foo == null` is the question to ask.

**A thenable becomes a promise so that `await` works on it**, which is the shape rule `slate:gzip`
and `fetch` already follow — a surface that is asynchronous on one host is asynchronous everywhere,
and a program written against it reads the same in both.

## Handing a function out

**A slate closure crosses as a JavaScript function, and its arguments cross INWARD by the table
above.** So a callback is handed exactly what the language guarantees: primitives as themselves, and
everything else as an external it can read properties off. Its answer crosses outward.

**It is given as many arguments as it declares and no more**, which is
[the rule every slate call follows](functions.md#a-function-takes-as-many-arguments-as-it-declares-and-the-rest-are-dropped)
— JavaScript passes extra arguments everywhere, its own `map` calling back with three, and a
one-parameter lambda takes the first and drops the rest. A callback declaring more than the host
supplies is a fault, the function being right and what it was attached to being unable to feed it.

**A method call keeps its receiver and a bare call keeps the one its path gave it.** `x.foo(a)` calls
`foo` with `x` as `this`; `fetch(url)` on an `external fetch` is called on the global object, because
that is where the path found it. This is not a nicety — a browser's `fetch` called on anything else
throws `Illegal invocation`, and every method of a host object taken off it and called later has the
same fault waiting in it. **A function read out of an external as a property has no receiver**: read
it to hand it on, call it as a method to call it.

## Under the interpreter

**The declaration is accepted and every operation that would touch the host faults**, naming the
command:

```slate
external localStorage

print(localStorage.getItem("theme"))
```

```error
no JavaScript host
```

**`==`, `is external`, storing one and matching a name are not host operations and all work**, which
is what makes the two blocks above this section run at all. The line is exactly whether the host has
to be asked: identity, travel and the type test are the language's, and a property, a call and a
construction are the host's.

**The module still exists and the import still succeeds**, for the same reason: a refusal at the
import is a complaint about the module and sends a reader looking for a spelling mistake in a line
that is right. The mistake is the command, so the command is what the sentence names.

## Reading and writing `localStorage`

**Two properties and a method, and nothing else is needed.** These blocks are for a page and are
quoted rather than run:

```slate
external localStorage

remember(key, value) = localStorage.setItem(key, value)

recall(key) = localStorage.getItem(key) ?? ""

theme() =
    val held = localStorage.getItem("theme")

    if held == null then "light" else held
```

`getItem` answers `null` for a key that is not there — the host's own `null`, crossing as itself —
and `setItem` takes two strings. An integer handed to it crosses as a `number` and JavaScript
stringifies it, which is the host's rule and not slate's; a program that means a string writes one.

## Watching an element with a `ResizeObserver`

**The callback receives an external and reads a property off it**, which is the shape nearly every
observer API has:

```slate
import { byId } from dom

external ResizeObserver

watch(id, onWidth)
    val seen = (entries, observer) ->
        val first = entries[0]
        val box = first.contentRect

        onWidth(box.width)

    val observer = ResizeObserver.new(seen)

    observer.observe(byId(id))

    observer
```

**Four things in that function are the whole feature.** `ResizeObserver.new(seen)` is JavaScript's
`new` with a slate closure as its argument; `entries` arrives as an external because a JavaScript
array is not a slate array; `entries[0]` and `first.contentRect` are property reads answering further
externals; and `box.width` is a `number`, so what reaches `onWidth` is an ordinary slate number that
can be compared, stored and printed — an integer where the box is a whole number of pixels wide and a
real where it is not, which is the rule for every number the host hands back.

**`observer` is an external the caller keeps**, and `observer.disconnect()` later is the same method
call as any other. Nothing about the value is different for having been constructed here rather than
read off a global.

## What this is deliberately not

**There is no type system for JavaScript here, and there is not going to be one.** Kotlin/JS and
Scala.js both let a program *declare* the shape of a foreign object, and both then have to keep two
descriptions of one API in step by hand, with a compile that believes the declaration over the world.
slate's answer is that the host's values are the host's: the checker knows an external's *kind* and
nothing whatever about its members, so `x.anything` is never refused and never promised.

**`x.new(...)` is the one name an external cannot reach as a method**, `new` being how construction is
spelled. It is the same word slate uses for its own classes, which is what makes it worth the cost.

**`external` does not import anything.** A path names something the host has already loaded — a page's
globals, a module the program was bundled with — and how a name comes to be on the global object is
the host's business, not slate's.
