// Arrays, and the method syntax every builtin type answers to.
//
// A builtin method is the free function of the same name with the receiver in front, so `map(xs, f)`
// and `xs.map(f)` are the same call written two ways. There is no array prototype and nothing for a
// program to patch: what an array can do is fixed, and what a program can do to an array is write a
// function.

val scores = [88, 42, 97, 61, 75]

print("scores:", scores)
print("doubled:", scores.map(n -> n * 2))
print("passing:", scores.filter(n -> n >= 60))
print("total:", scores.sum())
print("best:", scores.reduce((a, b) -> if a > b then a else b, 0))

// The bare verb changes the array; the participle answers a new one. Nothing hands the array back
// from a change, so `sorted(scores)` and `sort(scores)` cannot be confused at the call site.
print("sorted:", scores.sorted())
print("untouched:", scores)

// Numbers order as numbers. JavaScript's default answers [10, 9] for this, having compared the text.
print("numbers order as numbers:", sorted([10, 9, 100, 1]))

// A comparator answers whether the first value comes before the second. It is a boolean and not a
// number, because zero is true in slate and a -1/0/1 comparator would read as "yes" every time.
val people = [
  { name: "Ada", born: 1815 },
  { name: "Alan", born: 1912 },
  { name: "Grace", born: 1906 }
]

print("by birth:", sorted(people, (a, b) -> a.born < b.born).map(p -> p.name))
print("by name:", sorted(people, (a, b) -> a.name < b.name).map(p -> p.name))

// The callback is handed the value and nothing else, which is what lets a one-argument builtin be
// passed straight in. JavaScript's `["1","2","3"].map(parseInt)` answers [1, NaN, NaN] because the
// index arrives as a second argument.
print("read as numbers:", ["1", "2", "3"].map(number))

// Searching answers a position or `null` -- never a sentinel to remember.
print("where 97 is:", scores.indexOf(97))
print("where 5 is:", scores.indexOf(5))
print("first over 90:", scores.find(n -> n > 90))

// Changing one in place, by name.
val queue = []

push(queue, "first")
push(queue, "second")
insert(queue, 0, "urgent")

print("queue:", queue)
print("next:", removeAt(queue, 0), "leaving", queue)

// Strings and numbers answer to the same syntax, for the same reason.
print("  hello, world  ".trim().upper().split(", "))
print((3.7).floor(), (2.1).ceil(), (16).sqrt())
