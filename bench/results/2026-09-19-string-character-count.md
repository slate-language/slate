# A string carries its own character count — shortlist item 4, `7478d4b`

Taken 2026-09-19 on this machine, best of 5, under `caffeinate`, box at 95.8% idle, `pgrep -x java`
empty, both locks held. **Both columns are binaries I built and kept**, and each is named: `0.0.57`
is `dev` at `e3ed5ff`, which is this branch's own starting point, and `item 4` is that same commit
with this change and nothing else on it. Measuring the two ends of one commit is what keeps the
figure this item's rather than the week's.

|  | 0.0.57 | item 4 | change | 0.0.57/lua | item 4/lua |
|---|---|---|---|---|---|
| `strindex` | 2506.1 | **13.2** | **190x faster** | 980.1x | **5.5x** |
| `strwalk` | 4830.8 | **15.0** | **322x faster** | 30.3x | **0.1x** |
| `strings` | 883.1 | 939.8 | — | 2.4x | 2.4x |

**`strings` did not move and the two figures either side of it say why.** Lua read 365.5 and 386.8 on
the same two runs, `node --jitless` 24.9 and 26.8, `python3` 625.6 and 646.8 — the whole second
column is about 5% up, which is the machine and not the build. The RATIO is 2.4x in both, and a
ratio is what this table is for: `strings` concatenates and never asks a position, so nothing here
reaches it.

**`strwalk` IS NEW AND IT IS THE HALF `strindex` COULD NOT SEE.** `strindex` walks ASCII, where a
character is one byte and a position can be arithmetic; `strwalk` walks 20,000 characters of
Japanese, where it cannot. **Lua is NOT the yardstick on that one** — it has no character indexing at
all, and the idiomatic `utf8.offset` counts from the front, so Lua's own walk is quadratic exactly as
slate's was. That is why the ratio reads 0.1x, and the twin's header says so.

**The whole set, with the merged build** (`dev` `a42c2f1` plus this item, so items 1 and 4 together):

| | against lua | against node --jitless | against python3 |
|---|---|---|---|
| the original twenty, 2026-09-18 | 17.4x | 12.4x | 8.3x |
| the original twenty, now | **12.4x** | **8.9x** | **5.9x** |
| all twenty-one, with `strwalk` | 9.9x | 7.9x | 5.4x |

**Of that 17.4 → 12.4, this item is 17.4 → 13.4** — substituting `strindex`'s new ratio into the
September 18 row and changing nothing else — and item 1 and run-to-run drift are the rest. The
twenty-one row is what `bench/run.sh` prints with no names given; the twenty is the comparable one,
and both are here so neither reading has to be worked out from the other.

**WHAT THE COUNT COSTS IS THREE WORDS PER STRING CELL AND NOTHING ELSE.** `StrObj` carries the
character count, the last position it was asked about and that position's byte offset. The count is
written when the cell is made and a string is immutable, so it can never go stale —
`new_str_counted(s, chars)` is the only constructor and takes the number as a parameter, which is
what stops a site forgetting it. Nearly every string is derived from one already counted (a join adds
two counts, a slice subtracts two positions, `repeat` multiplies, a literal is counted when it is
interned), so the one place a walk is owed is text arriving from outside the machine.

**`chars == bytes.len` IS THE TEST FOR "EVERY CHARACTER IS ONE BYTE"** and it falls out of keeping the
count rather than costing a flag. For such a string a position IS a byte offset. For one that is not,
the cursor makes a left-to-right walk cost one step per character instead of one walk per character —
**forward only, because the decoder counts a run of ill-formed bytes as one character and that rule
has no reverse**; a position behind the cursor is walked from the front with the same iterator that
did the counting, so the two can never disagree about where a character begins.

**The evidence that is not a clock is `Vm.chars_scanned`**, every byte the character-position
routines walk over, asserted in `tests_strcount.sysl`. Walking 20,000 one-byte characters by index
now reads **fewer bytes than the string is long**; the same walk over 20,000 three-byte characters
reads the string about once. Before this it was some 200,000,000 bytes for the first.

| kind, over all twenty | 0.0.57 | item 1 |
|---|---|---|
| `PushNull` | 249,873,014 | **35,076** |
| `Discard` | 173,086,794 | **4,577,096** |
| `Pop` | 90,356,320 | **9,028,080** |

**NO OTHER KIND MOVED BY A SINGLE EXECUTION, and that is checkable rather than asserted**: the fall
in those three sums to 499,675,876, which is exactly the fall in the total. `Tick` is unchanged at
every benchmark — it is still emitted once per statement, in the same place, and making it cheaper
is item 3.

**`arith`'s loop is 19 instructions a turn where it was 25.** What went is three `PushNull`, two
`Discard` and one `Pop`; what is left computes.

**An `if`, a `match` and a `try` written as statements are DELIBERATELY UNTOUCHED.** Each is
compiled as the expression it is wherever it stands, so both arms still leave a value and the
statement still drops one — three instructions per execution, paid once per `if` rather than once
per turn of anything. Teaching the arms to leave nothing needs its own argument about the two stack
depths meeting at the jump they share, and the benchmarks here do not ask for it: `dispatch`'s
`match` is a function's answer and is read. A **loop** written as a statement is untouched for the
same reason plus one more: `break` gives a loop a value, so the value is genuinely produced and the
one instruction that drops it is paid once per loop, not per turn.

