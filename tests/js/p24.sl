// `slate:url`'s base64url, on both back ends.
//
// **The module is slate source carried in the binary**, so both back ends read one text and the
// only thing that could make them disagree is a builtin underneath it — `toBytes`, `chars`,
// `indexOf` into a string, integer division, and indexing a string with a number. Every one of
// those has disagreed between the two at some point in this project's history, which is why an
// encoding written once still earns a differential file.
//
// **The vectors are RFC 4648's own**, so a back end that agreed with itself and with nothing else is
// caught here rather than in a round trip that could be wrong twice.

import { base64urlEncode, base64urlDecode } from slate:url

// -- the published vectors -----------------------------------------------------------------------

for s in ["", "f", "fo", "foo", "foob", "fooba", "foobar"]
    print("[" + base64urlEncode(s) + "]")

// The two characters that are the whole difference from base64: 62 is `-` and 63 is `_`.
print(base64urlEncode([251, 255]), base64urlEncode([255, 255, 255]))

// -- a string is its bytes -----------------------------------------------------------------------

print(base64urlEncode("café") == base64urlEncode(toBytes("café")))

val back = base64urlDecode(base64urlEncode("café"))

print(back.ok, fromBytes(back.value).value)

// -- every byte there is, and every tail length ---------------------------------------------------

var bs = []
var i = 0

while i < 256
    push(bs, i)
    i = i + 1

val whole = base64urlDecode(base64urlEncode(bs))

print(whole.ok, len(whole.value), toJSON(whole.value) == toJSON(bs))

val all = [1, 2, 3, 4, 5]

for n in [1, 2, 3, 4, 5]
    val piece = all[0..<n]
    val here = base64urlEncode(piece)

    print(len(here), toJSON(base64urlDecode(here).value) == toJSON(piece))

// -- what is refused, and in what words ------------------------------------------------------------

// **A result rather than a fault**, text encoded this way arriving from outside — and the sentence
// names the character, since "that was not base64url" is something a reader can do nothing with.
for s in ["ab*d", "Zm8=", "Zm9vYg==", "Zm9vA", "Zm9vZh", "Zm9vZg", ""]
    val r = base64urlDecode(s)

    print(r.ok, if r.ok then string(len(r.value)) else r.error)
