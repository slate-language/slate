---
title: Tests
weight: 150
---

# Tests

`@test` marks a function of no arguments, and `slate test` is the only thing that calls one.

```slate
val floor = 2

export clamp(x) = if x < floor then floor else x

@test
clamp_lifts_a_small_number_to_the_floor() =
    assertEq(clamp(-3), floor)

@test
async a_missing_file_answers_rather_than_raising() =
    val r = await readFile("nothing-here.txt")

    assert(!r.ok, "a file that is not there answers a result")
```

```
$ slate test .
  ok    examples/testing.sl :: clamp_lifts_a_small_number_to_the_floor   0ms
  FAIL  examples/testing.sl :: widen_clamps_every_element   0ms
        error: got [2, 5], wanted [2, 5, 2]
          --> examples/testing.sl:41:5
           |
        41 |     assertEq(widen([1, 5, -2]), [2, 5, 2])
           |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

5 passed, 1 failed
```

`slate test` takes a file or a directory, and walks a directory for every `.sl` file under it.
`slate test --js` runs the same suite [in JavaScript](javascript.md).

## The assertions

| | |
|---|---|
| `assert(condition)` | |
| `assert(condition, message)` | |
| `assertEq(got, wanted)` | renders both sides, quoting a string so `"6"` and `6` do not look alike |
| `assertFaults(fn)` | calling `fn` is supposed to raise |
| `assertFaults(fn, message)` | and the fault has to say that |
| `skip(reason)` | this test is not going to run here, and why |

**A failed assertion raises**, and the runner catches it exactly as a [`catch`](faults.md) would. A test
that faults without asserting anything fails the same way, and whatever it printed is shown above the
failure.

## A call that is supposed to fail

**`assertFaults` is the one assertion that cannot be written as a condition**, because a fault leaves
the test rather than answering false. Without it the shape is a `try` whose body ends in a complaint —
and a `try` that forgets that last line is a test which passes whatever the call does.

```slate
val pump = { handle: null }

pull(p) = if p.handle == null then throw "the pump has no handle" else "water"

@test
pulling_a_handleless_pump_says_so() =
    assertFaults(() -> pull(pump), "no handle")
```

The function takes no arguments, so what you write at the call is a lambda around the thing you expect
to go wrong. With a second argument the fault's own text has to **contain** it; with one, any fault
will do. What fails, and what it says:

- `expected a fault, got a value: 42` — the call answered instead of raising;
- `the fault said "…", wanted it to contain "…"` — it raised, about something else.

**An `async` function's fault arrives a turn later, so `assertFaults` answers a promise where it was
given one** — `await` it, and the test is `async` like any other that waits for something.

```slate
@test
async a_file_that_is_not_there_is_a_fault_in_the_strict_reader() =
    await assertFaults(readStrictly)
```

**A `skip` travels straight through it.** A skip is the test's whole verdict rather than the fault the
call was asked for, so `assertFaults` never swallows one.

## Leaving a test out

**`skip(reason)` says a test is not going to run here**, which is what a suite needs where one host has
something another has not — a socket under [`slate js`](javascript.md), a database nobody started, a
platform the code is not written for yet.

```slate
@test
a_server_answers_what_it_is_asked() =
    if !canListen() then skip("this host has no listener")

    assertEq(ask("/"), "hello")
```

```
  ok    tests/api.sl :: a_route_is_matched_before_it_is_called   0ms
  skip  tests/api.sl :: a_server_answers_what_it_is_asked   this host has no listener

7 passed, 1 skipped
```

**It raises**, so nothing after it runs — which is why there is no `return` on the line below it, and
why forgetting one cannot leave the test running on the host it was written to be left out of.

**A `catch` does not get it.** A skip is the test's whole verdict, exactly as `exit` is a script's, so
a library the test called cannot swallow it.

**A reason is required, and it is shown where the timing is on a pass.** A test left out with nothing
said is one nobody ever puts back — and a run that skipped anything says so on its last line, so a
suite that quietly stopped running half of itself cannot report a page of greens.

## Setting up, and tidying away

**Four annotations say what runs around a test**, and every one of them marks a function of no
arguments exactly as `@test` does:

| | |
|---|---|
| `@setup` | before **each** test in the file |
| `@teardown` | after **each** test, however it went |
| `@setupAll` | once, before the first test |
| `@teardownAll` | once, after the last |

**What they share, they share through the file's own `var`s**, there being nothing else to pass: a
hook takes no arguments and hands nothing back.

```slate
import { lmdbOpen, lmdbClose } from slate:lmdb

var store = null
var wrote = 0

@setupAll
open_the_store() =
    store = lmdbOpen("/tmp/counting", { mapSize: 1048576 })

@setup
start_from_nothing() =
    wrote = 0

@teardownAll
shut_the_store() =
    lmdbClose(store)

@test
a_write_is_counted() =
    wrote = wrote + 1

    assertEq(wrote, 1)
```

**One of each to a file, and a second is refused where it is written**, naming both:

```
error: a file has one `@setup` at most, and `first` is already it -- `second` would be the second
```

That is the whole of the arrangement — there is no nesting, no group, and no way for one test to opt
out of the file's setup. A test that wants something different is a test that belongs in a file of its
own, which costs nothing and reads better than a flag would.

**A hook may be `async`**, and is waited for the way an `async` test is.

### When one of them goes wrong

**A fault in `@setup` fails the test it was preparing, and the failure names the setup**:

```
  FAIL  tests/store.sl :: a_write_is_counted   0ms
        `open_the_store` failed before this test ran
        error: the store would not open
```

A fault in `@setupAll` does that to **every** test in the file, and a `skip` in either leaves the test
out with the reason given — which is how a whole file says *this host is not for me* once instead of in
every test.

**A `@teardown` runs however the test went** — passed, failed or left out — because what it gives back
is exactly what a setup that stopped halfway had already taken. **Its own fault is a failure of its
own**, counted on the last line under the teardown's name rather than folded into the test or quietly
dropped: a passing test with a broken teardown is not a passing file.

**A `@setup`, the test it prepares and its `@teardown` run on one event loop**, and each of the three
is waited for only as far as its own answer. So a socket the setup opened is still open while the test
runs, and a timer the test armed is still armed while the teardown runs — which is what makes
`clearTimeout` in a teardown mean anything. The loop is let settle **after** the teardown, and it waits
only for what the three of them left behind: whatever the file's `@setupAll` opened is the file's, and
settles after its `@teardownAll`.

## Running only some of them

**`--only <substring>` runs the tests whose name contains it**, and nothing else:

```
$ slate test tests --only clamp
  ok    examples/testing.sl :: clamp_lifts_a_small_number_to_the_floor   0ms

1 passed
```

The last line still counts what ran. **A filter that matches nothing is a failure, not an empty
success** — the usual cause is a misspelling, and a test step that is green having run nothing is the
worst outcome available to it:

```
$ slate test tests --only clmap

0 passed
slate: no test name contains "clmap"
```

**A file with nothing chosen is not prepared**: its `@setupAll` does not run, so a filter costs nothing
in a suite whose files each open a database.

## Where tests live

**Beside the code or in a file of their own**, and the difference is what they can reach. A slate module
is a *file*, so a test beside the code sees what that file kept private, and a test file that imports the
module sees exactly what a reader of it sees. Both are ordinary `@test` functions; nothing distinguishes
the two arrangements but where you put them.

**Only the file being tested contributes its tests.** A test file that imports the module it tests does
not run that module's tests a second time, so walking a directory runs each file's tests exactly once.

## Two rules worth knowing

**An `async` test is waited for.** Calling one hands back a promise that has not settled, so a runner that
read the answer straight away would call every asynchronous test a pass whatever it did.

**Running a file plainly calls none of its tests**, so `@test` costs a program that is not being tested
one closure and nothing else.
