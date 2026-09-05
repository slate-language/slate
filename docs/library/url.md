# `slate:url`

Percent-encoding and the `name=value` grammar — the piece under everything that reads a URL.

```slate
import { percentDecode, encodeComponent, parseQuery, parsePairs } from slate:url

val q = parseQuery("name=Ada+Lovelace&year=1843&tag=caf%C3%A9")

print(q.name, q.year, q.tag)
print(encodeComponent("a b/c?d=e&f"))
print(percentDecode("caf%C3%A9", false))

val cookies = parsePairs("session=abc; theme=dark", ";", false)

print(cookies.session, cookies.theme)
```

```output
Ada Lovelace 1843 café
a%20b%2Fc%3Fd%3De%26f
café
abc dark
```

## It exists so that a page can import it

These four were `slate:http`'s, and that module exported them saying in as many words that a framework
over it needs the same decoder its router uses. That was true and it was not enough: **the JavaScript
back end emits the whole of an imported module**, so a browser page importing `slate:http` to reach two
functions grew by **239 KB** — 340,761 bytes to 579,710 — because `slate:http` is a server, an HTTP/2
speaker and a file server. A page that only wants to read its own query string was paying for all of it.

So this is the lowest module slate has after [`slate:llhttp`](llhttp.md), and it is here for that
module's reason: what a program actually wanted was underneath something much larger.

**`slate:http` still exports all four and always will.** It imports them from here and forwards them,
so nothing written against that module changed.

**It asks nothing of the host** — no socket, no clock, no document — so it works under the interpreter,
under node and in a browser with no branch anywhere.

## Decoding is over bytes, not characters

`%C3%A9` is two bytes that are one character, so a decoder working a character at a time cannot put
them back together: this one collects the bytes and decodes the lot at the end.

**It answers its input unchanged where those bytes turn out not to be text.** A URL is something
somebody else wrote, and a fault here would let any link stop a program. For the same reason, **a `%`
not followed by two hex digits is a `%`** — which is what every browser does with one.

`plusIsSpace` is the one difference between a query or a form and everything else percent-encoded. A
cookie's `+` is a `+`, and so is a path segment's.

## Encoding is the unreserved set and nothing more

`encodeComponent` leaves `A-Z`, `a-z`, `0-9`, `-`, `.`, `_` and `~` alone and encodes everything else,
which is RFC 3986's unreserved set. Encoding more than is needed is always safe and encoding less never
is, so the rule is the narrow one.

## A repeated name is the last one

```slate
import { parseQuery } from slate:url

val q = parseQuery("a=1&a=2&debug")

print(q.a)
print(has(q, "debug"), q.debug, "|")
```

```output
2
true  |
```

**That is a decision rather than an oversight.** The alternative every framework reaches for is an array
where a name repeats — which makes the *type* of `q.name` depend on what somebody put in a link, so a
program that read it as a string works until the day a name arrives twice. A value whose shape varies is
the thing this language argues against everywhere.

A program that genuinely expects a name more than once reads the raw text by hand; a server has it on
`req.search`.

**A name with no `=` is present and empty**, which is what a bare `?debug` means to everybody who writes
one.

## `parsePairs` is the grammar the three of them share

A query string, a form body and a `Cookie` header are one grammar with two knobs: the separator, and
whether `+` means a space.

```slate
import { parsePairs } from slate:url

print(parsePairs("a=1&b=two+words", "&", true).b)
print(parsePairs("a=1; b=two+words", ";", false).b)
```

```output
two words
two+words
```

It is exported because the three callers inside `slate:http` do not exhaust it: a dozen headers are
`name=value` lists, and a program reading one of them would otherwise write this again — which is the
very thing moving the module was meant to stop.

**A value wrapped in quotes is unwrapped**, a cookie's being so by the specification.

## `base64urlEncode` and `base64urlDecode`

Bytes as text that survives a URL: RFC 4648 §5's alphabet, which is base64 with `-` for `+` and `_`
for `/`, **and no padding at all**.

```slate
import { base64urlEncode, base64urlDecode } from slate:url

print(base64urlEncode("foobar"))
print(base64urlEncode([251, 255]))

val r = base64urlDecode("Zm9vYmFy")

print(r.ok, fromBytes(r.value).value)

val bad = base64urlDecode("ab*d")

print(bad.ok, bad.error)
```

```output
Zm9vYmFy
-_8
true foobar
false `*` is not a base64url character
```

**Encode takes a string or an array of bytes, and a string is its UTF-8 bytes** — the same reading
`encodeComponent` gives one, and the only reading there is: what an encoding of bytes does with text
is encode the text's bytes.

**Decode answers a result, and its value is BYTES.** Text encoded this way arrives from outside — a
cookie, a token, a signature somebody sent — so being malformed is a condition the caller was always
going to deal with rather than a fault, which is [the rule](../reference/faults.md) for anything read
from outside. And what was encoded is as likely to be a digest as a sentence, so answering text would
be guessing; `fromBytes` is the one call to text and answers a result of its own, so the two compose:

```slate
val r = base64urlDecode(piece)

if r.ok then fromBytes(r.value) else r
```

Three things are refused, each with its own sentence:

- **a character that is not in the alphabet**, `=` included — the padded spelling is base64 and this
  is not it, and accepting both would make two encodings of one value valid, which is the shape of
  hole a token format compared as text is walked through;
- **a length one past a multiple of four**, which carries no whole byte in its last character, so
  such a piece is truncated rather than merely odd;
- **bits past the last whole byte that are not zero**, or two spellings decode to the same bytes.

**`slate:jwt` is written on these**, a token being three base64url pieces; it carried a private copy
until the pair moved here, which is why they are in this module and not in that one.
