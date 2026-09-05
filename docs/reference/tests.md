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
| `skip(reason)` | this test is not going to run here, and why |

**A failed assertion raises**, and the runner catches it exactly as a [`catch`](faults.md) would. A test
that faults without asserting anything fails the same way, and whatever it printed is shown above the
failure.

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
