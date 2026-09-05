# `slate:brotli`

```slate
import { compress, decompress } from slate:brotli

val page = toBytes(repeat("<p>hello</p>", 40))
val small = compress(page, 5)               // quality 0-11
val back = decompress(small, 1 << 20)       // the limit is not optional

print(len(small) < len(page))
print(back.ok, fromBytes(back.value).value == fromBytes(page).value)
print(decompress(toBytes("not brotli"), 1 << 20).ok)
```

```output
true
true true
false
```

## The two channels

**`compress` faults** — it cannot fail on input the program already holds. **`decompress` answers a
result**, because what is being decompressed came from somewhere else: a request body that is not a brotli
stream is an ordinary thing to be sent and a `400` to answer, not a defect in the program reading it.

The three failures are three sentences, since they mean three different things to whoever sent the bytes:
*expands past the N bytes it was allowed*, *ends in the middle*, *is not a brotli stream*.

## The limit is required

**A brotli stream carries no length and a crafted one of a few hundred bytes expands without bound.** There
is no form of `decompress` that omits the limit.

## Not in a browser

**No JavaScript host has a brotli encoder**, so `compress` and `decompress` refuse under `slate js`,
naming brotli rather than promising a release. [`slate:gzip`](gzip.md) is the compression a browser has,
and it is promise-shaped for that reason; this module is synchronous and stays so.

[`slate:http`](http.md) compresses a response without asking the handler; that page says what the rules are.
