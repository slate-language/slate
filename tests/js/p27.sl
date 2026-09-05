// `slate:zstd`, on both back ends.
//
// **This module has no shared implementation at all**, which is what makes a differential file worth
// more here than almost anywhere else: the interpreter links the machine's libzstd through
// `sh.sysl.zstd`, and a JavaScript host uses node's `zlib`, which carries its own copy. Two
// libraries, one format.
//
// **The compressed BYTES are never compared and cannot be.** Two encoders at one level may frame the
// same input differently and both be right — that is what a compression level is. What is compared
// is the round trip, the sizes' ordering, and every sentence each back end says about a frame it
// will not read.

import { zstd, unzstd } from slate:zstd

val page = repeat("the quick brown fox jumps over the lazy dog, ", 40)

// -- the round trip ---------------------------------------------------------------------------------

val small = zstd(page, 3)

print("round trip", fromBytes(unzstd(small, 65536).value).value == page)
print("worth doing", len(small) < len(toBytes(page)) / 10)

// **Text crosses as its UTF-8**, so a program holding a string need not convert it first.
print("text is its bytes", zstd("a page of text", 3) == zstd(toBytes("a page of text"), 3))

// An empty input is a frame like any other, and it reads back empty.
print("nothing", toJSON(unzstd(zstd("", 3), 16).value))

// -- the level is a dial and not a format --------------------------------------------------------------

print("harder is smaller", len(zstd(page, 19)) <= len(zstd(page, 1)))
print("and reads back the same", fromBytes(unzstd(zstd(page, 19), 65536).value).value == page)
print("and so does the fast end", fromBytes(unzstd(zstd(page, 1), 65536).value).value == page)

// **A negative level is a regime of its own** and still a zstd frame, which is the thing worth
// pinning: the decoder does not need to be told.
print("negative levels", fromBytes(unzstd(zstd(page, 0 - 5), 65536).value).value == page)

// -- what it refuses ------------------------------------------------------------------------------------

print("not zstd", unzstd(toBytes("not zstd at all"), 1024).error)
print("cut short", unzstd(small[0..<(len(small) / 2)], 65536).error)
print("too large", unzstd(small, 100).error)

// **`unzstd` answers a result and `zstd` faults**, which is `parseJSON` against `toJSON` and for the
// same reason: what is being decompressed came from somewhere else.
print("ok on the good one", unzstd(small, 65536).ok)

print(zstd("x") catch e -> e.message)
print(unzstd("x") catch e -> e.message)
print(zstd(42, 3) catch e -> e.message)
print(zstd("x", "hard") catch e -> e.message)
print(unzstd("x", 0 - 1) catch e -> e.message)

// The range is libzstd's own and both hosts read it off the library rather than writing a number.
print("a level nothing accepts", contains(zstd("x", 23) catch e -> e.message, "and this is 23"))
