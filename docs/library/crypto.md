# `slate:crypto`

Digests, HMAC, key derivation and randomness.

```slate
import { sha256, hmac, randomBytes, timingSafeEqual } from slate:crypto

val nonce = randomBytes(18)
val tag = hmac("SHA-256", "a key", "the message")

print(len(nonce), len(sha256("abc")), len(tag))
print(timingSafeEqual(tag, hmac("SHA-256", "a key", "the message")))
print(timingSafeEqual(tag, hmac("SHA-256", "a key", "another message")))
```

```output
18 32 32
true
false
```

| | |
|---|---|
| `md5  sha1  sha256  sha384  sha512` | text or bytes in, the digest as bytes out |
| `hmac(name, key, message)` | |
| `pbkdf2(name, password, salt, rounds, length)` | |
| `randomBytes(n)` | from the operating system |
| `timingSafeEqual(a, b)` | |

**`hmac` takes the digest by name** — `"MD5"`, `"SHA-1"`, `"SHA-256"`, `"SHA-384"`, `"SHA-512"` — because
what a program is speaking to decides it, and a default here would be a decision taken by whoever wrote the
module rather than by the protocol. **`pbkdf2` takes the same names without `"MD5"`**: every other name
here reads a protocol somebody else chose, and deriving a key is the one thing a program chooses for
itself.

## Why the module exists

**A package cannot have a native.** [`slate:jwt`](jwt.md) and [`slate:ws`](ws.md) are carried in the binary
and are compiled against the scope the natives live in; a package installed with `slate add` is not — so
one speaking a protocol with a challenge in it (SCRAM, SASL, a signed webhook, a request signed for S3) had
no digest at all and no source of unpredictability at all. **A nonce a program worked out from the clock is
not a nonce**, and that half cannot be written in slate at any price.

**What a program can write, it writes.** Hex, base64 and the message layout of whatever protocol is being
spoken are ordinary slate, so they are not here. What is here is the compression functions and the kernel.

**`pbkdf2` is here for a reason that is not tidiness**: one SCRAM handshake is 4,096 HMACs, which is some
eight thousand SHA-256 compressions — a millisecond as a native and seconds in the interpreter.

## `timingSafeEqual`

**What a program checks a tag it was sent with.** `==` on two byte arrays stops at the first byte that
differs, which tells an attacker how much of a forged tag was right, and a tag can be guessed a byte at a
time from that.

## `md5` and `sha1`

**Both are exported and neither is an endorsement.** Each is what an existing protocol asks for — a
WebSocket handshake, a Git object, an old server's SASL, PostgreSQL's `md5` login, HTTP Digest, an S3
`ETag` — and a program speaking one has no say in the matter. Nothing new should be signed with either, and
no content address may be one.

**For a password, none of these is the answer.** [`slate:password`](password.md) is Argon2id and is
deliberately slow, which is the whole difference. `hash` is deliberately not a name here: it is
`slate:password`'s, where it means the slow one, and a second `hash` meaning the fast one is exactly the
confusion a login path must not have.
