# `slate:jwt`

JSON Web Tokens, written in slate.

```slate
import { sign, verify, decode } from slate:jwt

val token = sign({ sub: "alice", exp: when + 3600 }, secret, "HS256")
val r = verify(token, secret, "HS256")
```

| | |
|---|---|
| `sign(claims, key, alg)` | |
| `verify(token, key, alg)` | a **result** |
| `decode(token)` | the claims, unverified |

## The algorithm is an argument because the `alg` header is not to be trusted

**That is the whole security of the thing.** A verifier that read the algorithm out of the token it is
checking accepts whatever an attacker wrote there — `alg: none` was accepted by most libraries for years,
and the RS256-public-key-used-as-an-HMAC-secret confusion turns a *published* key into a signing key.

**The caller says what it expects, the header is compared against it before a signature is checked at all**,
and a token that disagrees is refused there.

HS256/384/512, RS, PS and ES.

## Three arguments and no options object

All three are decisions the caller has to make, and an option is for what has a sensible answer when nobody
says. **Extra header fields — `kid`, above all — go in the claims under `header`**, and are taken *out*
rather than signed: a claim called `header` would be a surprising thing to find in a payload you signed.

## The two channels

**A malformed token, a bad signature and an expired claim are all answers**, because a program handling
requests wants to say `401` and carry on. **A key that is not a key faults**, being the program's own
mistake.

**An HMAC tag is compared in constant time**, and that is not superstition: a comparison that stops at the
first differing byte tells an attacker how much of a forged tag was right. The asymmetric algorithms need
no such care, verifying a signature not being a comparison.
