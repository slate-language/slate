---
title: Bytes
weight: 35
---

# Bytes

A **buffer of raw bytes** — what a socket delivers, what a file holds, and what a string is in an
encoding. One byte per byte, grown and cut by memory operations rather than by a loop.

```slate
val greeting = toBytes("héllo")

print(greeting.length, greeting)
print(greeting[0], greeting[1..<3])
print(fromBytes(greeting).value)
```

```output
6 <bytes 6: 68 c3 a9 6c 6c 6f>
104 <bytes 2: c3 a9>
héllo
```

**A buffer is a reference, as an array is**: two names for one buffer see each other's writes, and
`push` grows the buffer both of them hold.

## Why it is a kind of its own

Until this existed, bytes in slate were an array of numbers. That costs a whole value per byte — about
sixteen times the data in storage — and every read of one goes through a tagged union. There was also
no way at all to say *the bytes of this string, in this encoding*, or to append one run of bytes to
another; both had to be written out as loops in the program.

So an encoder in slate cost more than the socket it was writing to. Here `concat`, `push` and `slice`
are copies of a run of memory, `length` is a field, and neither loops.

**Everything that took an array of numbers still takes one.** `send`, `writeBytes`, `fromBytes`,
`sha256`, `gzip`, a SQLite parameter — each takes a buffer *or* the array, so nothing written against
the old shape stops working.

## Making one

| | |
|---|---|
| `bytes(n)` | `n` zero bytes |
| `bytes([1, 2, 255])` | those bytes; anything outside `0..255` faults |
| `bytes(b)` | a copy of another buffer |
| `toBytes(s)` | the UTF-8 bytes of a string |
| `toBytes(s, "latin1")` | one byte per character, each below 256 |

```slate
print(bytes(4))
print(bytes([72, 105]))
print(toBytes("hi") == bytes([104, 105]))
```

```output
<bytes 4: 00 00 00 00>
<bytes 2: 48 69>
true
```

**`bytes(n)` is a COUNT and `bytes([n])` is a list**, told apart by the kind of the argument rather
than by a flag — which is what `Buffer.alloc(n)` and Python's `bytes(n)` both mean by it.

**There is no literal.** A buffer is written as one of these calls, and `bytes([…])` is the short form
for a handful of known bytes.

## What a buffer can do

| | |
|---|---|
| `b.length` | how many bytes |
| `b[i]` | the byte at `i`, as an integer |
| `b[i] = v` | write a byte where one already is |
| `b[a..<z]` `slice(b, a, z)` | a new buffer of that part |
| `concat(a, b, …)` | one new buffer of all of them |
| `push(b, v)` | one byte on the end |
| `push(b, other)` | a whole buffer on the end |
| `indexOf(b, what)` | where a byte or a run of bytes first is, or `null` |
| `contains(b, what)` | whether `indexOf` would find it |
| `at(b, i)` | one byte, counting a negative position back from the end |
| `clear(b)` | empty it |
| `b.toArray()` | the bytes as an array of numbers |

```slate
val head = toBytes("GET / HTTP/1.1\r\n\r\n")

print(indexOf(head, toBytes("\r\n\r\n")))
print(contains(head, 47), indexOf(head, 255))
print(concat(toBytes("a"), toBytes("bc")).toArray())
```

```output
14
true null
[97, 98, 99]
```

**`push` takes a byte or a whole buffer, and that second form is the reason this kind exists.** It is
one copy of a run of memory with room taken in doubling steps, where the array shape made a program
write a loop.

```slate
var out = bytes(0)

push(out, toBytes("Content-Length: "))
push(out, toBytes(string(42)))
push(out, 13)
push(out, 10)
print(out.length, fromBytes(out).value == "Content-Length: 42\r\n")
```

```output
20 true
```

**A miss answers `null` and never `-1`**, which is what `indexOf` answers on an array and on a string:
slate has no out-of-band integer, so the absence of a position is the absence value.

**`b.toArray()` is the door back to the forty names an array has.** `map`, `sort` and `groupBy` are
about values, and a buffer holds bytes — so they are not here, and `toArray` is the one call that says
*I want the array's cost*.

## A `for` walks its bytes

```slate
var total = 0

for b in toBytes("abc")
    total = total + b

print(total)
```

```output
294
```

## Equality, printing and JSON

**`==` compares CONTENTS**, as it does for an array:

```slate
print(toBytes("abc") == toBytes("abc"))
print(toBytes("abc") == [97, 98, 99])
print(toBytes("abc").eq(toBytes("abc")))
```

```output
true
false
false
```

A buffer does **not** equal the array of the same numbers, for the reason a string does not equal the
array of its characters: they are different kinds, and `==` is strict across kinds. `eq` asks whether
two names hold the same buffer, which is the question `push` makes worth asking.

**`print` writes the count and then the bytes in hex**, at most sixteen of them:

```slate
print(bytes(0))
print(bytes(20))
```

```output
<bytes 0>
<bytes 20: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ...>
```

The count comes first because it is what a program printing a buffer almost always wanted to know,
and sixteen is a line of a hex dump.

**JSON encodes a buffer as the array of its numbers**, which is what it encoded as before it was a
kind — so a document written today reads the same as one written before, and a reader of one is
unchanged. There is nothing else to encode it as: JSON has no bytes, and base64 would be a convention
this could not read back without being told which it was.

```slate
print(toJSON(bytes([1, 2, 255])))
```

```output
[1,2,255]
```

## The two encodings

| | |
|---|---|
| `"utf8"` | what a slate string is; the default |
| `"latin1"` | one character per byte, by code |

**Two and not a table of thirty.** UTF-8 is what slate's strings are, and latin1 is the one other
encoding a byte-oriented protocol needs: it carries every byte value through a string unharmed, which
is what a Redis reply, an HTTP body read as text and node's own `'binary'` all mean by it. Anything
else is a conversion table, and that belongs in a package.

```slate
val raw = toBytes("Ā", "utf8")
val flat = toBytes("ÿ", "latin1")

print(raw.length, flat.length, flat[0])
print(fromBytes(flat, "latin1").value == "ÿ")
print(fromBytes(bytes([0xff]), "latin1").ok, fromBytes(bytes([0xff])).ok)
```

```output
2 1 255
true
true false
```

**latin1 never fails going back**, every one of the 256 byte values naming a character there —
where UTF-8 may refuse, and has to. Going out, a character at or above 256 **faults and the sentence
names it**: a `?` would silently corrupt the data the program was carrying, and a truncation to the
low eight bits would corrupt it while looking like it worked.

```slate
print(toBytes("Ā", "latin1"))
```

```error
which is character 256 and has no byte
```

## Where a buffer arrives without being asked for

| | |
|---|---|
| `onBytes(sock, fn)` | each chunk, as a buffer |
| `readBytes(path)` `readBytesSync(path)` | the whole file, as a buffer |
| `sha256(x)` and every digest, `hmac`, `pbkdf2`, `randomBytes`, `jwsSign` | [`slate:crypto`](crypto.md) |
| `gzip` `gunzip` `deflate` `inflate`, `zstd` `unzstd`, `compress` `decompress` | [gzip](gzip.md), [zstd](zstd.md), [brotli](brotli.md) |
| `encodePNG` `encodeJPEG` `encodeWebP`, and a decoded image's `pixels` | [`slate:image`](image.md) |
| a `BLOB` column, an LMDB value and key | [sqlite](sqlite.md), [lmdb](lmdb.md) |
| `h2Send`, a DATA frame's body, `hpackDeflate` | [`slate:nghttp2`](nghttp2.md) |
| a binary WebSocket message, `framed` and `maskedFrame` | [`slate:ws`](ws.md) |

Both answered an array of numbers before. A 64 KiB read built 65,536 values and a megabyte of heap to
hand back 64 KiB of data; everything a program did with that array it does with the buffer — `for`,
`[i]`, `.length`, `fromBytes`, `send` — and `chunk.toArray()` is the array where it wanted one.

`send(sock, …)` and `writeBytes(path, …)` take a buffer, an array of numbers, or (for `send`) a
string. `slate:process` is unchanged: a child's output has always arrived as text.

## What changed

**`toBytes(s)` answers a buffer where it answered an array of numbers.** That is the one thing a
program can see:

- `toBytes(s).length` is the same number it was;
- `toBytes(s)[0]`, a `for` over it, `==` against another `toBytes`, `send`, `writeBytes`, `fromBytes`,
  `sha256`, `gzip` and `toJSON` all read the same as they did;
- `toBytes(s).map(…)`, `.sort()` and the rest of the array's own names are `toBytes(s).toArray().map(…)`;
- `toBytes(s) == [104, 105]` is now false — it is a buffer against an array, two kinds.

**And every library that answered an array of bytes answers a buffer**, which the table above lists:
a digest, a compressed body, an encoded image or its pixels, a BLOB, an LMDB value, an HTTP/2 frame
and a binary WebSocket message. The same three lines apply to each — `.length`, `[i]` and a `for`
read as they did, `.map` and the rest are behind `.toArray()`, and `==` against an array literal is
now false. **Nothing changed about what they TAKE**: every one of them still reads an array of
numbers wherever it reads bytes.

## `bytes` is a type word

It tests like every other kind, and annotates like one:

```slate
count(b: bytes) = b.length

print(toBytes("hi") is bytes, count(toBytes("hi")))
```

```output
true 2
```
