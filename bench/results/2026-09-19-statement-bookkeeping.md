# Statement bookkeeping removed — shortlist item 1, `fa327b6`

Taken 2026-09-19 on this machine, best of 5, under `caffeinate`, box at 91.3% idle, `pgrep -x java`
empty. **Both columns were measured in the same session**, so they are comparable to each other and
not to the table above: the `0.0.57` column is the installed release and `item 1` is `fa327b6` on
`unread-values`. Milliseconds of process wall time.

|  | 0.0.57 | item 1 | change | lua | 0.0.57/lua | item 1/lua |
|---|---|---|---|---|---|---|
| startup | 4.7 | 4.7 | -- | 1.8 | 2.6x | 2.6x |
| arith | 1488.4 | **1245.1** | **-16.3%** | 47.6 | 31.1x | 26.1x |
| reals | 1481.6 | **1258.8** | **-15.0%** | 57.7 | 25.6x | 21.8x |
| arrays | 1446.3 | **1216.9** | **-15.9%** | 92.5 | 15.9x | 13.2x |
| loops | 1056.8 | 942.8 | -10.8% | 119.4 | 8.8x | 7.9x |
| alloc | 1497.3 | 1358.0 | -9.3% | 160.0 | 9.6x | 8.5x |
| dispatch | 2125.9 | 1929.9 | -9.2% | 88.3 | 24.7x | 21.9x |
| closures | 1209.0 | 1098.8 | -9.1% | 45.0 | 28.8x | 24.4x |
| options | 1909.1 | 1751.3 | -8.3% | 84.9 | 23.7x | 20.6x |
| funcs | 1479.2 | 1365.6 | -7.7% | 47.4 | 30.4x | 28.8x |
| globals | 2468.1 | 2280.4 | -7.6% | 98.2 | 23.8x | 23.2x |
| fields | 1345.8 | 1257.2 | -6.6% | 60.9 | 21.7x | 20.6x |
| nested | 1843.9 | 1757.6 | -4.7% | 130.0 | 14.1x | 13.5x |
| mapset | 932.0 | 894.5 | -4.0% | 17.4 | 52.8x | 51.4x |
| fib | 2783.1 | 2679.5 | -3.7% | 79.6 | 34.5x | 33.6x |
| methods | 2411.2 | 2327.8 | -3.5% | 141.6 | 16.8x | 16.4x |
| csv | 588.2 | 568.8 | -3.3% | 297.7 | 2.0x | 1.9x |
| calls | 1516.9 | 1468.8 | -3.2% | 146.6 | 9.9x | 10.0x |
| sorting | 754.1 | 750.7 | -0.5% | 560.4 | 1.3x | 1.3x |
| strindex | 2471.9 | 2485.4 | *+0.5%* | 2.3 | 1045.6x | 1062.6x |
| strings | 858.4 | 872.9 | *+1.7%* | 359.0 | 2.4x | 2.4x |
| **geomean** | | | | | **17.6x** | **16.4x** |

Against `node --jitless` the mean went **12.5x to 11.6x** and against `python3` **8.2x to 7.7x**.

**THE THREE THAT MOVED LEAST ARE THE THREE WHOSE WORK IS INSIDE A BUILTIN**, which is finding 5
read from the other end: `strings`, `strindex` and `sorting` run almost no instructions per unit of
work, so taking instructions away buys them nothing and the two small rises are noise at this
sample size. The three that moved most — `arith`, `arrays` and `reals` — are the tight loops where a
quarter of every turn was bookkeeping.

**The instruction counts are exact and are the real evidence**, a time being a measurement and a
count an increment. With a `--features profile` build:

| benchmark | 0.0.57 | item 1 | change |
|---|---|---|---|
| `arith` | 250,000,036 | 190,000,026 | **-24.0%** |
| `loops` | 112,210,055 | 80,174,041 | **-28.6%** |
| `fields` | 135,000,043 | 105,000,033 | **-22.2%** |
| `funcs` | 136,000,040 | 112,000,028 | **-17.6%** |
| all twenty | 2,425,522,165 | 1,925,846,289 | **-20.6%** |

