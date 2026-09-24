# 2026-09-24 — `%` BY A LITERAL AS A MULTIPLY BY ITS RECIPROCAL: REFUTED ON THIS MACHINE, NOT LANDED

`2026-09-24-mapset-chain.md` ended on: "`Rem` is a hardware divide by a literal; a
multiply-by-reciprocal fold is the obvious next". `mapset`'s loop is `i % 1000` four million times,
`strings` has `i % 10`, `csv` `i % 100`. The item assumed an `sdiv` costs 10–20 cycles. **On this
M-series machine it does not, and the fold loses.**

## What was built (branch `rem-literal`, pushed, not merged)

- `divisor_of(by)` in `run_arith.sysl`: libdivide's unsigned generator applied to `|by|` — a mask
  for a power of two (and for one), `q = hi(n × m) >> s` where the rounded-up multiplier is exact,
  and the 65th-bit form `((n − t) >> 1 + t) >> s` otherwise. The dividend's magnitude is divided
  and its sign put back, so `x % -1`, `MinInt % -1`, `MinInt % 1` and every negative dividend are
  what `Rem` answers with no case of their own. sysl's `u128` gives the high multiply (`umulh`); no
  sysl gap.
- `Unit.divisors`, filled by `intern_divisor` from `fuse`: `SlotIntRem(i, k)` carries the index
  instead of the literal (so a divisor wider than 32 bits folds too), and a new `IntRemBy(k)` folds
  `PushInt(v); Rem` for an expression's remainder. A zero literal is never folded; anything but a
  machine integer goes to `remainder_of` with the literal.
- Tests: an exhaustive table (`tests_rem_literal.sysl`, >250,000 pairs: every divisor ±1..±300 plus
  twenty wide ones up to ±2^63, against the edges, the divisor's neighbours and multiples, and 400
  generated dividends each) comparing against `remainder_of`; the fold shape, `% 0`'s sentence, a
  real and a big-integer dividend, a wide literal, and profile counts. `tests/lang/remlit.sl` on
  both back ends. `sysl test .` 3130/0; the `profile` and `--no-default-features` shapes were not
  run, the branch not landing.

## The measurement

**Dispatch counts do not move** (profile build, dev `bc0b522` vs branch): the three benchmarks'
remainders were already `SlotIntRem` — `mapset` 4,000,000, `strings` 150,000, `csv` 20,000 — and
still are. The change is only what happens inside the arm, so the question is `sdiv` against the
reciprocal.

**The arm compiles as intended** (disassembly of the PGO `run_frames`): `cneg; umulh; sub; add
..., lsr #1; lsr; msub; eor; sub` inline, no call and no divide — about 14 cycles of dependent
latency, against `sdiv` + `msub`.

**Native, with the interpreter out of the picture** (`sysl` probe, 200M remainders by 1000 of an
LCG stream, three rounds each, `@noinline` on both):

| | hardware `x % d` | reciprocal as landed | reciprocal, best case (one kind, shift masked) |
|---|---|---|---|
| ms | 213–221 | 262–292 | 227–232 |

The best-case reciprocal is **~6% slower** than the divide. Apple's integer divider is fast enough
that a high multiply, the 65th-bit correction and the sign handling cost more than it does.

**Alternating best-of-9, PGO against PGO** (box 48–55% idle, other agents gating — noisy): geometric
mean **+0.54%**, `mapset` +4.4%, `csv` −2.3%, `strings` −0.5%. A focused best-of-15 on the three
and a `% 1000` loop read the branch 6.5–10% slower on all four, including `csv`, whose remainders
are 0.1% of its instructions — so those rows are the box, not the change; the native figure above
is the one that decides.

## Verdict

**Do not land.** On this hardware the reciprocal cannot beat `sdiv`, even in its best form. It
would pay on a core with a slow divider (older x86, some ARM cores), which is where libdivide's
numbers come from; slate's Linux tarballs run on such cores, so the branch is left pushed for the
day a Linux profile shows `Rem`. What would move `mapset` further is not the divide: its loop is
nine dispatches a turn and the remainder is one.
