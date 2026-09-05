# `slate:gzip`

gzip and zlib — the compression a program has wherever slate runs, including a browser.

```slate
import { gzip, gunzip, deflate, inflate } from slate:gzip

async main()
    val page = toBytes(repeat("<p>hello</p>", 40))
    val small = await gzip(page)
    val back = await gunzip(small, 1 << 20)        // the limit is not optional

    print(len(small) < len(page))
    print(back.ok, fromBytes(back.value).value == fromBytes(page).value)

    val zipped = await deflate("the same text, wrapped as zlib instead")
    val flat = await inflate(zipped, 1 << 20)

    print(fromBytes(flat.value).value)
    print((await gunzip(toBytes("not a gzip stream"), 1 << 20)).ok)

main()
```

```output
true
true true
the same text, wrapped as zlib instead
false
```

| | |
|---|---|
| `gzip(data)` | a promise of the bytes, wrapped as a gzip member |
| `gunzip(data, limit)` | a promise of `{ ok, value }` — the bytes, or why not |
| `deflate(data)` | a promise of the bytes, wrapped as zlib |
| `inflate(data, limit)` | a promise of `{ ok, value }` |

`data` is text or bytes; text crosses as its UTF-8, which is what goes on a wire either way.

## Which of the two wrappers

**`gzip` is the file format** — the one `gzip`, `curl` and `Content-Encoding: gzip` all mean, with a
ten-byte header and a trailer carrying a length and a CRC-32.

**`deflate` is zlib** — two bytes of header and an adler-32, which is what `Content-Encoding: deflate`
means in practice and what every HTTP client expects under that name, despite what the name says.

Neither is the bare deflate stream that sits inside both. A program that needs *that* is writing a
container of its own, and has to say so byte by byte anyway.

## Every one of them answers a promise

**A browser's compression is a stream, and there is no synchronous way to ask it.** So the surface is
promise-shaped on every host rather than being synchronous in the interpreter and absent in a browser —
which is the trade this module exists to avoid making. Nothing is waiting for a network here; on the
interpreter the answer is a promise that has already been settled.

[`slate:brotli`](brotli.md) is synchronous and stays so: its signature was written before there was a
second host, and a program already holds it.

## The limit is required

**A deflate stream carries no length, and a crafted few hundred bytes expands without bound.** So the two
that read say how large an answer the caller is prepared to hold, and there is no form that omits it.

For a gzip stream the trailer states the length, so the refusal happens before a byte is allocated. For a
zlib stream there is nothing to state it, so the output is counted as it arrives.

## The two channels

**Compressing faults and decompressing answers a result**, which is the rule everywhere in slate: a value
the program built cannot fail to be compressed, and bytes that came from somewhere else can be anything.

The sentences are about the container — *this does not begin with gzip's two magic bytes*, *this expands
past the N bytes it was allowed*, *this gzip stream's checksum does not match its contents* — and slate
reads that container itself on both back ends, so they are the same words wherever the program runs.
[The JavaScript back end](../reference/javascript.md) names the one sentence that is not.

## What compresses to what is not promised

Two deflate implementations agree about the format and not about the stream. The same text packed by the
interpreter and by a browser is a different length and a different set of bytes, and both are correct —
so a program may compare what came *back*, and never the compressed bytes themselves.

[`slate:http`](http.md) compresses a response without asking the handler; that page says what the rules
are.
