# Library

What a program has without writing it.

- **[Globals](globals.md)** — the names in scope with no import: printing, text, numbers, arrays,
  objects, JSON, bytes, timers, promises and `fetch`.
- **The `slate:` modules** — everything else, reached by `import { … } from slate:name`.

| module | |
|---|---|
| [`slate:fs`](fs.md) | the file system, in a promise-shaped and a blocking form |
| [`slate:net`](net.md) | TCP, and TLS at both ends |
| [`slate:http`](http.md) | an HTTP server, a router, and static files |
| [`slate:url`](url.md) | percent-encoding, base64url, and the `name=value` grammar |
| [`slate:time`](time.md) | eight temporal types, and the arithmetic over them |
| [`slate:process`](process.md) | another program, this program's environment, signals |
| [`slate:regex`](regex.md) | PCRE2 patterns |
| [`slate:crypto`](crypto.md) | digests, HMAC, key derivation, randomness |
| [`slate:password`](password.md) | Argon2id |
| [`slate:jwt`](jwt.md) | JSON Web Tokens |
| [`slate:ws`](ws.md) | WebSockets |
| [`slate:redis`](redis.md) | a Redis client |
| [`slate:sqlite`](sqlite.md) | SQLite — the database that needs no server |
| [`slate:gzip`](gzip.md) | gzip and zlib — the compression every host has |
| [`slate:brotli`](brotli.md) | brotli — smaller, and not in a browser |
| [`slate:zstd`](zstd.md) | Zstandard — faster than both, and not in a browser |
| [`slate:llhttp`](llhttp.md) | the HTTP parser itself |
| [`slate:nghttp2`](nghttp2.md) | HTTP/2 framing, and HPACK |
| [`slate:dom`](dom.md) | the document — in a browser only |

## Why so many of these are modules rather than globals

**Because the words are ones a program wants for its own.** `stat`, `send`, `close`, `connect`, `run`,
`hash`, `check`, `query`, `on`, `setText` and `time` are all things an ordinary program declares. While
they were global, writing `val stat = …` shadowed a builtin without meaning to.

What is left global is roughly node's own list — `print`, `len`, the conversions, the array and string
operations, JSON, the timers, the promise words, `next` and `fetch`.

## A method is the free function with the receiver in front

`xs.map(f)` **is** `map(xs, f)` — one implementation and one set of checks, reachable two ways. So there
is no array prototype and a program cannot add to one: the table is in the interpreter.

**Dispatch is on the receiver's kind**, so `xs.upper()` says *"`upper` is not something an array can
do"* rather than reaching `upper` and complaining about its argument.

**Four methods every value answers**, whatever its kind: `toString`, `eq`, `ne`, `equals`. They are asked
last, so a kind's own answer always wins, and a field the program put there — own or through a proto —
wins over both.

## Two channels, everywhere

A condition the caller was always going to deal with is a **result**: `{ ok: true, value: v }` or
`{ ok: false, error: text }`. A defect in the program is a **fault**. See [Faults](../reference/faults.md).

`readFile("/gone")` answers; `readFile(42)` faults. `parseJSON` answers; `toJSON` faults. `decompress`
answers; `compress` faults. The rule is the same every time: **text or bytes from outside the program is
an answer, and a value the program built itself is a fault.**
