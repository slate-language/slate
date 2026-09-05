// `slate:crypto`, on both back ends.
//
// **This corpus is worth more than most, because the two sides come from genuinely different
// places**: the interpreter's digests are OpenSSL's and `sysl.crypto`'s, and the emitted program's
// are written out in JavaScript in `js_rt_hash.sysl`. So a line that agrees here is a line checked
// against somebody else's implementation rather than against a second copy of itself. Every vector
// below is a published one -- FIPS 180-4, RFC 1321, RFC 2202, RFC 6070 -- so a run that agreed with
// itself and with nothing else would still be caught.
//
// **WebCrypto is not involved at all**, and that is the decision the whole runtime side is shaped by:
// `crypto.subtle` is Promise-only in every browser, so a digest built on it would answer a promise
// here and a byte array there. `randomBytes` is the one name reaching for the host, over
// `crypto.getRandomValues`, which IS synchronous everywhere.

import { md5, sha1, sha256, sha384, sha512, hmac, pbkdf2, randomBytes, timingSafeEqual } from slate:crypto
import { sign, verify } from slate:jwt

val Digits = "0123456789abcdef"

hex(bs) = join(map(bs, b -> Digits[b / 16] + Digits[b % 16]), "")

// The empty message, which is where a padding mistake shows first.
print(hex(md5("")), hex(sha1("")))
print(hex(sha256("")))
print(hex(sha384("")))
print(hex(sha512("")))

// `abc`, which is every one of the five specifications' first vector.
print(hex(md5("abc")), hex(sha1("abc")))
print(hex(sha256("abc")))
print(hex(sha384("abc")))
print(hex(sha512("abc")))

// **THE BLOCK BOUNDARY IS WHERE A DIGEST WRITTEN TWICE IS WRITTEN DIFFERENTLY.** A message one byte
// short of needing a second block, one byte over, and exactly on it: the length field has to be in
// the block after the one the data filled, and every reimplementation gets this wrong once. SHA-512
// blocks at 128 and reserves 16 bytes for its length where the others block at 64 and reserve 8.
print(hex(sha256(repeat("a", 55))), hex(sha256(repeat("a", 56))))
print(hex(sha256(repeat("a", 63))), hex(sha256(repeat("a", 64))), hex(sha256(repeat("a", 65))))
print(hex(md5(repeat("a", 55))), hex(md5(repeat("a", 56))))
print(hex(sha1(repeat("a", 63))), hex(sha1(repeat("a", 64))))
print(hex(sha512(repeat("a", 111))), hex(sha512(repeat("a", 112))))
print(hex(sha512(repeat("a", 127))), hex(sha512(repeat("a", 128))))
print(hex(sha384(repeat("a", 111))), hex(sha384(repeat("a", 112))))

// A message long enough to need many blocks.
val long = repeat("abcdefghij", 200)

print(hex(sha1(long)), hex(sha256(long)))
print(hex(sha512(long)))

// **Bytes rather than text**, which is the other way a program hands a message over -- and the byte
// 0 and the byte 255 are the two a conversion through a string would lose.
print(hex(sha256([0, 1, 2, 253, 254, 255])), hex(md5([])))
print(hex(sha256(toBytes("héllo"))), hex(sha256("héllo")))

// HMAC. **A key LONGER than the block is hashed first and a shorter one is padded with zeros**, and
// those are the two halves of RFC 2104 that a reimplementation skips.
print(hex(hmac("MD5", "key", "The quick brown fox jumps over the lazy dog")))
print(hex(hmac("SHA-1", "key", "The quick brown fox jumps over the lazy dog")))
print(hex(hmac("SHA-256", "key", "The quick brown fox jumps over the lazy dog")))
print(hex(hmac("SHA-384", "key", "The quick brown fox jumps over the lazy dog")))
print(hex(hmac("SHA-512", "key", "The quick brown fox jumps over the lazy dog")))
print(hex(hmac("SHA-256", "", "")))
print(hex(hmac("SHA-256", repeat("k", 200), "message")))
print(hex(hmac("SHA-512", repeat("k", 200), "message")))
print(hex(hmac("SHA-256", repeat("k", 64), "message")), hex(hmac("SHA-256", repeat("k", 65), "message")))

// PBKDF2, RFC 6070's vectors and the same shape over the other digests. **A length that is not a
// whole number of digests is where the block counter is exercised**, so 20 bytes of SHA-1 is one
// block and 40 is two.
print(hex(pbkdf2("SHA-1", "password", "salt", 1, 20)))
print(hex(pbkdf2("SHA-1", "password", "salt", 2, 20)))
print(hex(pbkdf2("SHA-1", "password", "salt", 4096, 20)))
print(hex(pbkdf2("SHA-1", "password", "salt", 4096, 40)))
print(hex(pbkdf2("SHA-1", "passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 25)))
print(hex(pbkdf2("SHA-256", "password", "salt", 4096, 32)))
print(hex(pbkdf2("SHA-256", "password", "salt", 4096, 33)))
print(hex(pbkdf2("SHA-384", "password", "salt", 1000, 48)))
print(hex(pbkdf2("SHA-512", "password", "salt", 1000, 64)))
print(hex(pbkdf2("SHA-512", "password", "salt", 1000, 100)))

// **`slate:jwt` IS WHAT `jwsSign` AND `jwsVerify` ARE FOR, and it is how they are reached at all**:
// the two are declared into the scope a built-in module's source is compiled in rather than exported
// by `slate:crypto`, so a program cannot call either directly. The `HS` algorithms are HMAC under a
// JOSE name and work on both back ends; `RS`, `PS` and `ES` are RSA and ECDSA, whose only JavaScript
// implementation is `crypto.subtle`'s and answers a promise, so those refuse there and are not here.
val signed = sign({ sub: "u1", n: 7 }, "secret", "HS256")

print(signed)
print(verify(signed, "secret", "HS256"))
print(verify(signed, "wrong", "HS256").ok)
print(verify(sign({ sub: "u1" }, "secret", "HS384"), "secret", "HS384").ok)
print(verify(sign({ sub: "u1" }, "secret", "HS512"), "secret", "HS512").ok)

// **Randomness is checked for its SHAPE and never for its value**, there being nothing two runs
// agree about. What a program can rely on is the count and that two draws differ.
print(len(randomBytes(1)), len(randomBytes(32)), len(randomBytes(1000)))
print(randomBytes(32) != randomBytes(32))

allBytes(bs) = len(filter(bs, b -> b >= 0 && b <= 255)) == len(bs)

print(allBytes(randomBytes(64)))

// A comparison that says nothing about how much of one side was right.
print(timingSafeEqual("abc", "abc"), timingSafeEqual("abc", "abd"))
print(timingSafeEqual("abc", "abcd"), timingSafeEqual("", ""))
print(timingSafeEqual([1, 2, 3], [1, 2, 3]), timingSafeEqual([1, 2, 3], [1, 2, 4]))

anything(v) = v

// The error paths, which are half of what a differential corpus is for.
say(f)
    try
        f()
    catch e
        print(e.message)

say(() -> anything(sha256)())
say(() -> sha256("a", "b"))
say(() -> sha256(anything(3)))
say(() -> sha256([1, 2, 300]))
say(() -> sha256([1, 2, -1]))
say(() -> sha256([1, "x"]))
say(() -> hmac("SHA-256", "k"))
say(() -> hmac("MD4", "k", "m"))
say(() -> hmac(anything(3), "k", "m"))
say(() -> pbkdf2("SHA-256", "p", "s", 1))
say(() -> pbkdf2("MD5", "p", "s", 1, 16))
say(() -> pbkdf2("MD4", "p", "s", 1, 16))
say(() -> pbkdf2("SHA-256", "p", "s", 0, 16))
say(() -> pbkdf2("SHA-256", "p", "s", 1, 0))
say(() -> pbkdf2("SHA-256", "p", "s", 4294967296, 16))
say(() -> pbkdf2("SHA-256", "p", "s", anything("x"), 16))
say(() -> pbkdf2("SHA-256", "p", "s", 1, -1))
say(() -> randomBytes())
say(() -> randomBytes(0))
say(() -> randomBytes(anything("x")))
say(() -> timingSafeEqual("a"))
say(() -> timingSafeEqual("a", anything(3)))
say(() -> sign({ sub: "u1" }, "secret", "HS999"))
say(() -> verify("not.a.token", "secret", "HS256"))
