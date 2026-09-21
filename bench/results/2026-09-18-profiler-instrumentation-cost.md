# The profiler

**`SLATE_PROFILE=1 slate program.sl` writes a report to stderr**, leaving stdout exactly as it was,
so a profiled run can still be diffed against its expected output.

**An environment variable and not a flag, and that is forced by a decision already made**: everything
after a program's name on the command line belongs to the program (`main.sysl` says so), so slate has
no flag it could add without taking one a script had already claimed.

What it reports:

- **wall time**, by the same monotonic clock everything else here uses;
- **collections run, microseconds inside the collector, allocator steps and heap in use**;
- **calls and microseconds per BUILTIN**, heaviest first;
- **executions per instruction kind**, in a build that has them (below).

```
slate profile
  wall             1172731 us
  instructions     not counted in this build
  collections      1
  collector        26 us
  allocator steps  1
  heap in use      312840 bytes
  ...
  builtins, by time (7 of them)
    Map.set 2000000 calls 231745 us
```

### Instruction counts are behind `--features profile`, and the reason is a measurement

**Counting instructions needs a branch inside the instruction loop, and that branch is not free.**
Measured by alternating two binaries over this whole set, best of 5, twice:

| build | geomean against `dev` | worst benchmark |
|---|---|---|
| the branch live in the loop | **1.024x** | `arith` 1.081x |
| the same tree with the branch folded away | **0.999x** | -- |
| the shipped build, `profile` feature off | **1.001x** | `strindex` 1.014x |

The middle row is the control and it is what makes the first row a finding rather than build noise:
a tree carrying *every* other change -- the builtin timing hook, the collector hook, the whole
`profile.sysl` module, and whatever the code layout did -- measured 0.999, so the 2.4% is the one
line and nothing else.

So `CountingInstructions` is a build-time constant that `--features profile` sets, the optimiser
deletes the branch where it is false, and:

```
sysl build .                      # the shipped build: builtins, collector, allocator, heap
sysl build . --features profile   # all of that plus executions per instruction kind
```

**Everything else the instrument does is in every build**, because it costs 0.1% and a person
profiling their own installed slate should get it. Only the per-instruction count needs the rebuild,
and the report says so in words rather than printing a zero.

**The suite has a third shape because of this.** `sysl test . --features profile` runs the two tests
that assert the instruction counts are exact, beside the existing `sysl test .` and
`sysl test . --no-default-features`.

### What the counts are worth

- **A count is exact and a time is not.** Counting is an increment; timing is two readings of a
  microsecond clock, so a builtin taking a tenth of a microsecond measures as nought or one and only
  the total over many calls means anything.
- **A profiled run is a slower run** -- roughly 2x with instruction counting on, since every
  instruction hashes a name into a table. A builtin's microseconds are comparable to another
  builtin's; they are **not** a share of the unprofiled wall time in the table above. Read shares
  against `run.sh`'s numbers, which is what is done below.
- **A builtin that runs a slate callback is timed inclusively.** `map`, `filter`, `sort` and the rest
  run slate code inside the window being measured.

