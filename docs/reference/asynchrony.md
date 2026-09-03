# Asynchrony

## `async` and `await`

An `async` function answers a promise rather than a value, and `await` waits for one:

```slate
async work(name, ms, turns)
    var i = 0

    while i < turns
        await sleep(ms)
        i = i + 1

    name + " finished"

async main()
    val a = work("a", 8, 3)
    val b = work("b", 20, 2)

    print("started both")
    print(await a)
    print(await b)

main()
```

```output
started both
a finished
b finished
```

**Everything above a function's first `await` runs before its caller sees the promise, and everything
below it runs after the caller has moved on** — which is node's rule, and why `started both` prints
before either worker's first step. The two workers then interleave by their own clocks: with those
numbers `a` takes its first two steps, `b` takes one, `a` finishes, and `b` finishes last.

**Top-level `await` is refused**, so a program that wants to wait writes an `async main` and calls it:

```slate
val x = await sleep(1)
```

```error
`await` belongs in an `async` function
```

`async` goes in front of a definition, a lambda, or a method. Making the whole program a coroutine is a
real design and one to make on purpose.

## The order things run in

**A settled promise still resumes through the queue rather than continuing in place**, so what was
scheduled first runs first; `await` of a plain value answers it and still yields, so a program cannot
tell which of the two it was handed by watching what runs next.

There are two queues and the order between them is fixed. One answers *something happened outside the
program* — a timer, a socket, a file. A second, drained to empty between every turn of the first, answers
*a value a suspended call is owed is now known*. That is JavaScript's microtask/macrotask split, and it
is not a refinement: a program that resolved a promise from a timer callback and then ran the next timer
before the awaiting function had moved would interleave in an order nothing could predict.

## Failure

**A failed promise raises where it was awaited.** A promise fails when the `async` function running it
faults; awaiting that promise raises the same fault in the awaiting function, so a chain of `await`s
carries a fault to whoever is waiting at the end of it — and a [`catch`](faults.md) anywhere along that
chain stops it.

**`catch` works across an `await`.** A coroutine carries its handlers with it when it is set aside, so a
promise that fails minutes later still raises inside the `try` that was written around the `await`
rather than escaping to the scheduler.

**A failure nothing was waiting for is the program's failure**, reported against the line that raised it.
That is the one thing node gets wrong by default and warns about instead.

**A call whose promise was thrown away fails at once; everything else is asked at the end.** The question
"was this handled?" usually cannot be answered when a promise fails — `val p = risky()` and `await p`
three lines later is ordinary — so it is asked once, after everything has settled. But a call written on
a line of its own, `main()`, was never given to anybody: there is no name for it and no line that could
ever await it, so its failure is final where it happens. That distinction is what makes the report reach
a **server**, which never settles and would otherwise hold the diagnostic for as long as the process
lived — a fault in a coroutine that looks, from outside, exactly like a hang.

## Making a promise

| | |
|---|---|
| `sleep(ms)` | a promise for later; takes a [duration](../library/time.md) too |
| `resolve(v)` | one that has already settled with a value |
| `reject(message)` | one that has already failed |
| `pending()` | one nobody has answered yet |
| `settle(p, v)` | answer a pending one |
| `fail(p, message)` | fail a pending one |

`resolve` and `reject` adapt something that has already happened; `pending`/`settle`/`fail` adapt
something that has not. Without them a program could only await what slate itself started, and anything
with a callback of its own would be stuck in callbacks. They are JavaScript's `Promise.withResolvers()`
under slate's own names.

## Timers

`setTimeout(fn, ms)` and `setInterval(fn, ms)` answer an id; `clearTimeout(id)` and `clearInterval(id)`
stop one. **A timer keeps the program alive**, so an interval nothing clears is a program that never
exits.

The callback comes first, which is node's order — and a callback in that position cannot be a
[block lambda](functions.md), those having to be last.

**A fault in a callback is not caught by the call that scheduled it.** `try setTimeout(...)` guards the
scheduling and nothing else, because the callback runs from the loop long afterwards. That is inherent
rather than a gap: there is no statement of the program's left to attach it to.

## Generators

**A function is a generator because it holds a `yield`** — Python's rule, with no word on the definition.

```slate
counter(from)
    var n = from

    loop
        yield n
        n = n + 1

val g = counter(1)

print(next(g))
print(g.next())

for x in counter(1)
    print(x)

    if x == 3 then break
```

```output
{value: 1, done: false}
{value: 2, done: false}
1
2
3
```

- **Calling one runs nothing.** The body starts on the first `next`.
- **`next(g)` and `g.next()` are the one call**, `next` being a free function like every other method.
- **`next` answers `{ value, done }`**, and a generator whose body has finished answers
  `{ value: null, done: true }` from then on.
- `for x in g` is an ordinary loop over one, and stops when the generator does.
- **A generator does not touch the event loop**, so generators work in a program with no loop running.
- **`val got = yield x`** is how a value is sent in: the driver's value is written over the slot the
  yielded one left.

```slate
echoer()
    val got = yield 1

    yield got * 10

val e = echoer()

print(next(e))
print(e.next(5))
```

```output
{value: 1, done: false}
{value: 50, done: false}
```

**`yield` takes the whole expression where `await` takes one operand.** `await f() + 1` waits for the
call and adds to the answer; `yield x * x` yields the product. A yield used inside a larger expression is
bracketed. JavaScript and Python both put `yield` at the bottom of the ladder.

**An `async` function may not `yield`.** Two things would be entitled to put one machine back and there
is no rule for which, so calling one fails its promise with *"an `async` function may not `yield` -- an
async generator is not slate"*. It is refused at the call rather than at the compile.

An abandoned generator's state is held for the life of the program — there is no finalizer, so a
generator never run to the end keeps what it was holding.
