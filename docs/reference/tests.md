# Tests

`@test` marks a function of no arguments, and `slate test` is the only thing that calls one.

```
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

**A failed assertion raises**, and the runner catches it exactly as a [`catch`](faults.md) would. A test
that faults without asserting anything fails the same way, and whatever it printed is shown above the
failure.

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
