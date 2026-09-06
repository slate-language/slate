---
title: "slate:crypto"
weight: 90
---

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
| `argon2(password)` | a promise of a PHC record — Argon2id, 19 MiB, two passes |
| `argon2Verify(record, attempt)` | a promise of `true` or `false` |
| `argon2NeedsRehash(record)` | `true` or `false`, at once |

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

**For a password, none of these is the answer.** `argon2` below is deliberately slow, which is the whole
difference — and it is why there is no `hash` in this module. Every name here says which algorithm it is, so
a reader checking a login path by eye can see that the slow one was used.

## `argon2` — the one hash here meant to be slow

Argon2id, in the PHC format every other Argon2 implementation reads.

```slate
import { argon2, argon2Verify, argon2NeedsRehash } from slate:crypto

async main()
    val stored = await argon2("correct horse")

    print(startsWith(stored, "$argon2id$v=19$m=19456,t=2,p=1$"))
    print(await argon2Verify(stored, "correct horse"))
    print(await argon2Verify(stored, "wrong"))
    print(argon2NeedsRehash(stored))

main()
```

```output
true
true
false
false
```

**A password is the one thing a server stores that must be expensive to check.** Everything else in this
module wants to be fast, and for a password that is the whole vulnerability: a stolen table of fast hashes
is tried at billions of guesses a second on a graphics card. Argon2 is slow *and* memory-hungry, so the
card's thousands of cores cannot each hold a copy of the working state. The memory is the lever that
matters, and it is why a default call reserves 19 MiB.

The salt is a fresh sixteen bytes from the operating system per call, so hashing one password twice gives
two different records and both verify.

### The parameters, and where the heavier profile went

`argon2` and `argon2NeedsRehash` each take an optional record of parameters:

| | | |
|---|---|---|
| `memoryCost` | 19456 | kibibyte blocks — 19 MiB |
| `timeCost` | 2 | passes over that memory |
| `parallelism` | 1 | lanes |
| `hashLength` | 32 | bytes of tag |
| `salt` | the kernel's | text or bytes, 8 to 32 of them |

The defaults are OWASP's first recommendation for a login. **64 MiB and three passes — for something
hashed rarely and worth more than a session, a key-encrypting key or a recovery code — is
`argon2(secret, { memoryCost: 65536, timeCost: 3 })`** rather than a second name: once the numbers are
parameters at all, a name for one particular pair of them is a second way to say the same thing.

**A `salt` you give is a footgun, and it is accepted anyway** because a published test vector and a record
being reproduced from another implementation both need it. A program that passes a constant has given up
the only thing a salt is for: one precomputed table would then break every account at once.

**An unknown key is refused rather than ignored.** `{ memoryCosts: 65536 }` would otherwise be a login
that was thought to have been strengthened and was not.

### The parameters travel inside the record

So raising what a program asks for invalidates nothing: existing records keep verifying, because
`argon2Verify` uses the parameters the password was hashed *with*. `argon2NeedsRehash` says which records
are below what is written today — ask it after a successful verify, while the plaintext is still in hand,
and re-hash the ones that answer `true`. That is the whole upgrade path.

Where a program hashes with something other than the defaults, tell `argon2NeedsRehash` so:
`argon2NeedsRehash(stored, { memoryCost: 65536, timeCost: 3 })`.

### The derivation runs on a thread, which is why two of these are promises

**Hashing a password is supposed to take a tenth of a second, and a loop is one thread.** Done on the loop,
that tenth of a second is a tenth of a second in which the server answers nobody — so ten simultaneous
logins were ten seconds of a dead process. `argon2` and `argon2Verify` hand the derivation to a thread pool
and answer promises; everything else the server is doing carries on while it runs.

**`argon2NeedsRehash` is not one of them**, and the difference says what the pool is for: it reads the
parameters out of the record and compares them, which is microseconds and no derivation at all.

**The pool is four threads unless `UV_THREADPOOL_SIZE` says otherwise**, and it is shared with file reads
and name resolution.

### Neither answers a result, and that is a decision

**A wrong password is `false`; a stored record that will not parse faults.** They are not the same failure —
a record that is not an Argon2 record is a defect in whatever wrote the column — and collapsing them would
make a corrupted row read as an intruder, which is the one confusion a login path must not have.

`await argon2(p)` is the record itself and `await argon2Verify(r, p)` is a boolean, not the `{ ok, value }`
a file read answers. Those carry a result because what they read came from outside the program and may not
be there; a derivation is a value the program built, and every way it can go wrong is a fault raised where
the call is written, before anything reaches a thread.

**The record comes first and the password second.** Both are text, so a swap would answer `false` forever
and never say why — a second argument that *is* a record while the first is not is caught and named.
