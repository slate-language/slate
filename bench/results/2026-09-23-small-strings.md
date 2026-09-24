# 2026-09-23 — A STRING OF ONE ASCII CHARACTER IS MADE ONCE: `strings` 31.5 → 17.9 ms

The `string-append` write-up left `strings` at 33 ms with a third of it in `string(i % 10)` and
another third in the collector and `malloc`/`free` of the digit strings. `string(digit)`, `s[i]`, a
`for` over a string, `chars(s)` and `split(s, "")` each answered a fresh heap cell and a `malloc`ed
byte for what is one of 128 texts. Control `8bd0c9d` (dev); branch `small-strings`.

## What was built

`small_str.sysl`, one field on the `Vm` (`small_strs`, 128 entries), and one line each in
`obj.sysl`'s `reserve_spares` (a rebuilt heap empties the table) and `collector.sysl`'s `mark_spares` (every interned
cell is rooted).

- **The table is filled lazily**: the first time a character is asked for, its cell is made in the
  VM's own heap, charged like any string, and kept. Every later ask answers that cell. A full heap's
  reserve cell is never kept.
- **Only ASCII**, so the table is indexed by the byte. A byte of 0x80 or above is part of a longer
  character or an ill-formed byte counting as one on its own; both still get a cell per read.
- **Invisible to a program by construction**: a string is immutable and `==` compares text. An
  interned cell never has a room (rooms start at 64 bytes) and a one-byte string indexes without its
  cursor, so the one shared cell has no state any holder could see change.
- **The sites**: `printed_value` for an integer 0–9 (no `snprintf`, no builder), `str_char_value` for
  `s.at(i)` and a `for` over a string, `str_slice` of one character (which is `s[i]`), `chars`/
  `split("")` pieces, and `split` pieces of one byte.

### Not done here, and why

- **`string` resolved at compile time (shortlist item 8) was left to the `construction` agent**,
  briefed with the same resolution for `number`/`string` in `csv` and running at the same time.
- **`strindex`/`strwalk` (item c): the obvious thing is not in slate.** Best-of-30 on this box:
  `slate --version` takes **4.4 ms**, `/usr/bin/true` 1.4 ms, and **an empty C `main` linked against
  the same twelve Homebrew dylibs 4.2 ms**. So ~2.7 ms of every run is `dyld` mapping, fixing up
  and signature-checking libuv, OpenSSL, PCRE2, brotli, hiredis, nghttp2, zstd, LMDB, WebP and SQLite
  before `main` runs — no one of them dominant (OpenSSL 0.7, libuv 0.6, the three small ones 0.6
  together). That is 40–60% of `strindex` (6.1 ms) and `strwalk` (7.1 ms), and 2x qjs on both is
  mostly that. **The fix is linking them statically**, as the Linux tarballs already do — a sysl/
  packaging decision, not an interpreter change. What remains of `strindex` after startup is the
  walk, which now allocates nothing; `strwalk`'s characters are three-byte kanji and still get a cell
  each.

## The numbers

Alternating best-of-9 (`bench/alternate.pl 9`), control `8bd0c9d` against the branch, box 86.5%
idle at the start, a neighbour's gate running by the end (68% idle) — so everything but the string
programs is inside the noise band of ±5%.

| program | control | branch | change |
|---|---|---|---|
| **strings** | 31.46 | **17.88** | **−43.2%** |
| strindex | 6.80 | 6.13 | −9.8% |
| fields, globals, startup | | | −4.1% to −5.5% (noise: none of them makes a one-character string) |
| strwalk | 7.29 | 7.10 | −2.6% |
| loops | 141.4 | 145.7 | +3.1% (noise) |
| every other program | | | −2.6% to +1.1% |
| **geometric mean, all twenty-three** | | | **−3.88%** |

`strings` is **1.06x QuickJS** (16.8 ms), from 1.9x.

`SLATE_PROFILE`, control → branch:

| program | collections | allocator steps |
|---|---|---|
| strings | 221 → 166 | 597,306 → 447,316 |
| strindex | 16 → 8 | 41,298 → 21,317 |
| strwalk | 16 → 16 | 43,301 → 43,301 (kanji: not ASCII, unchanged as it must be) |

## Tests

- `tests_small_str.sysl` (six): asking twice for a character answers one cell, and `s[i]`, a slice,
  a `chars` piece and a `split` piece all answer that same cell; `string(7)` is the interned `"7"`
  while `string(10)` and `string(-3)` are fresh; a two-byte character, a three-byte one and a lone
  0x80 byte are NOT interned (while an ASCII character of the same string is); an interned cell held
  by nothing but the table survives two collections with its text, and a rebuilt heap empties the
  table; a program appending to an interned character, keeping it and reading back what it built
  sees exactly what it made; 10,000 one-character strings in a one-megabyte heap all read back.
- `tests_strcount.sysl`'s census names `small_str.sysl` as the third file that makes a string cell.
- `tests/lang/onechar.sl` (five), both back ends: `string()` of a digit, ten and a negative; `s[i]`,
  a slice and `at(-1)` over ASCII and non-ASCII; `chars` and `split`; a `for` over a string; an
  interned character appended to and compared.
