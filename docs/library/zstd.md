# `slate:zstd`

Zstandard — the encoding for a hot path, and for a protocol whose two ends are both yours.

```slate
import { zstd, unzstd } from slate:zstd

val page = toBytes(repeat("<p>hello</p>", 40))
val small = zstd(page, 3)                   // the level: 1 fast, 3 the default, 19 for storage
val back = unzstd(small, 1 << 20)           // the limit is not optional

print(len(small) < len(page))
print(back.ok, fromBytes(back.value).value == fromBytes(page).value)
print(unzstd(toBytes("not zstd"), 1 << 20).ok)
```

```output
true
true true
false
```

## Why it is here beside brotli and gzip

**It fills the gap between them.** [`slate:brotli`](brotli.md) at quality 5 is the slow end of what a
request handler can afford; `deflate` is the fast end and compresses worse than either. zstd at level 3
is several times faster than deflate and compresses better than it, and at 19 it is in brotli's range —
so it is the first encoding worth reaching for on a response being built now, and the obvious one for a
build cache, a log, or a wire format where both ends are yours.

## The names are the format's own verbs

**`zstd` and `unzstd`, not `compress` and `decompress`.** Those two are `slate:brotli`'s, and every
built-in module's names are declared into one scope — so two modules cannot own a word.
[`slate:gzip`](gzip.md) settled this first with `gzip`, `gunzip`, `deflate` and `inflate`, and these are
what the command line calls them.

## The two channels

**`zstd` faults** — it cannot fail on input the program already holds. **`unzstd` answers a result**,
because what is being decompressed came from somewhere else: a request body that is not a zstd frame is
an ordinary thing to be sent and a `400` to answer, not a defect in the program reading it.

The three failures are three sentences, since they mean three different things to whoever sent the bytes:
*expands past the N bytes it was allowed*, *ends in the middle*, *is not a zstd frame*.

## The limit is required

**A zstd frame is entitled to say nothing about how large it becomes**, and where its header does carry a
size that number is the frame's claim rather than a fact. So there is no form of `unzstd` that omits the
limit.

## The level is written at every call

There is no default, for [`slate:brotli`](brotli.md)'s reason: it is the one number a caller has to think
about, and no single value is right often enough to be the quiet one. The scale runs from libzstd's own
minimum to 22 and is **not** linear — negative levels are a regime of their own that skips most of the
match search, 1 to 3 are for anything on a hot path, 9 is a good compress-once setting, and 19 to 22 want
real memory at the writing end.

**A frame carries a checksum**, which is what tells a damaged stream from one that was never zstd.

## Both hosts have it, and a browser does not

**node has carried Zstandard in `zlib` since 22.15**, so this module is native under `slate js` as well
as here — and the compressed bytes are not compared between the two, node linking its own copy of libzstd
and the interpreter linking the machine's. Two encoders at one level may frame the same input differently
and both be right; what is checked is the round trip and what each makes of the other's frames.

**One difference is documented rather than papered over.** node's decompressor answers *nothing* about
a frame that ends in the middle — an empty buffer and no error, where libzstd's one-shot call says
`srcSize_wrong` — so the JavaScript back end reads the frame header and measures what came back against
what it claimed. A frame that declared **no** size is the one case it cannot check, and there the two
back ends read a truncation differently: this one answers what it managed and the interpreter refuses.
Every frame `zstd` writes declares its size, so this is about frames from somewhere else.

**No browser has zstd** — `CompressionStream` takes `gzip`, `deflate` and `deflate-raw`, and no engine
has proposed a fourth — so both names refuse there naming zstd, exactly as `slate:brotli` does.

[`slate:http`](http.md) writes `Content-Encoding: zstd` for a client that asks for it, in preference to
brotli, with nothing asked of the handler; that page says what the rules are.
