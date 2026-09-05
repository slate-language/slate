// `slate:gzip`, on both back ends.
//
// **This is the module the parity rule was written for.** A browser has `CompressionStream` and has
// no brotli at all, so gzip and zlib are the compression a slate program can count on wherever it
// runs -- and the interpreter's half is miniz while this one is the host's own streams, which is as
// far apart as two implementations of one surface get.
//
// **What is compared is what came BACK, never the compressed bytes.** Two deflate implementations
// agree about the format and not about the stream: the same text packed by miniz and by a host is a
// different length and a different set of bytes, and both are correct. So a round trip is the
// assertion, along with the parts of the container the format itself fixes.
//
// **The other half is `tests_gzip.sysl`**, which hands bytes ACROSS the two back ends -- the
// interpreter compressing what node decompresses and back again -- which is the one thing a corpus
// file cannot do, being one program run twice with nothing shared between the runs.

import { gzip, gunzip, deflate, inflate } from slate:gzip

// One byte of an array replaced, which is how a stream is damaged below.
patched(bs, at, byte) = concat(bs[0..<at], [byte], bs[(at + 1)..<len(bs)])

// -- what the format itself fixes ----------------------------------------------------------------

async main()
    val text = "the quick brown fox jumps over the lazy dog, and then the quick brown fox again"
    val packed = await gzip(text)

    // gzip's two magic bytes and its only compression method, which every writer must produce.
    print(packed[0], packed[1], packed[2])

    // **The MTIME is zero and the OS byte is 255 in the interpreter's**, so that packing the same
    // bytes twice gives the same stream -- but a host writes its own, and neither is read back. What
    // is checked instead is that the header is the fixed ten bytes: the flags say there is no name,
    // no comment and no extra field, so the body begins at ten on both.
    print(packed[3])

    // zlib's header is two bytes whose pair is a multiple of 31, and whose low nibble is the method.
    val z = await deflate(text)

    print(z[0] % 16, (z[0] * 256 + z[1]) % 31)

    // -- round trips -----------------------------------------------------------------------------

    val back = await gunzip(packed, 4096)

    print(back.ok, fromBytes(back.value).value == text)

    val flat = await inflate(z, 4096)

    print(flat.ok, fromBytes(flat.value).value == text)

    // Bytes rather than text, which is the other thing either takes.
    val bytes = [0, 1, 2, 255, 128, 0, 0, 0, 7]
    val small = await gzip(bytes)

    print(toJSON((await gunzip(small, 4096)).value))

    // Nothing at all, which is the case a stream format has to have an answer for.
    val nothing = await gunzip(await gzip(""), 16)

    print(nothing.ok, len(nothing.value))

    // Text that is not ASCII, so that the UTF-8 crossing is the same on both.
    val greek = "λ, καὶ ἡ σκοτία αὐτὸ οὐ κατέλαβεν"
    val greekBack = await gunzip(await gzip(greek), 4096)

    print(fromBytes(greekBack.value).value == greek)

    // Something long enough that the compressor has work to do and the answer arrives in pieces.
    val long = repeat("slate compresses this line over and over. ", 500)
    val longBack = await gunzip(await gzip(long), 65536)

    print(longBack.ok, len(longBack.value) == len(toBytes(long)))

    // -- a member neither compressor here writes ---------------------------------------------------

    // **The `gzip` command puts the file's NAME in the header and neither of slate's two hosts
    // does**, so a stream carrying one is only ever met coming from somewhere else -- which is
    // exactly the case a round trip cannot reach. The flag says a NUL-terminated name follows, and
    // both back ends have to walk past it to find the body.
    val named = [31,139,8,8,0,0,0,0,2,3,110,97,109,101,100,46,116,120,116,0,5,193,209,9,128,48,12,64,193,85,222,0,46,225,135,254,233,14,213,70,27,104,18,41,1,193,233,189,243,98,82,49,177,67,6,215,8,35,155,112,127,250,112,134,89,241,74,87,23,50,162,79,188,154,141,194,186,207,219,194,165,210,43,234,104,254,231,29,73,151,70,0,0,0]
    val namedBack = await gunzip(named, 4096)

    print(namedBack.ok, fromBytes(namedBack.value).value)

    // -- the limit -------------------------------------------------------------------------------

    // **Exactly the size is allowed and one less is not**, the limit being the most it may become.
    val sized = await gzip("abcdefghij")

    print((await gunzip(sized, 10)).ok)
    print((await gunzip(sized, 9)).error)
    print((await inflate(await deflate("abcdefghij"), 9)).error)

    // -- a container that is wrong -----------------------------------------------------------------

    print((await gunzip([1, 2, 3], 64)).error)
    print((await gunzip(toBytes("not a gzip stream at all"), 64)).error)
    print((await gunzip(patched(packed, 2, 9), 4096)).error)

    // A header that says a file name follows and then never ends it.
    print((await gunzip([31, 139, 8, 8, 0, 0, 0, 0, 0, 255, 110, 111, 116, 101, 115, 116, 1, 2, 3, 4], 64)).error)

    // The trailer's checksum, which is computed on both back ends rather than taken from a host.
    print((await gunzip(patched(packed, len(packed) - 8, 0), 4096)).error)

    // The trailer's length, which is what sizes the answer -- too large is refused against the limit
    // and too small is caught against what actually came out.
    print((await gunzip(patched(packed, len(packed) - 1, 255), 4096)).error)
    print((await gunzip(patched(packed, len(packed) - 4, 3), 4096)).error)

    // zlib's own header, whose four rules are read here rather than left to the host.
    print((await inflate([1, 2, 3, 4], 64)).error)
    print((await inflate([120, 32, 1, 2, 3], 64)).error)
    print((await inflate([121, 155, 1, 2, 3], 64)).error)
    print((await inflate([136, 29, 1, 2, 3], 64)).error)
    print((await inflate([120, 157, 1, 2, 3], 64)).error)
    print((await inflate([120], 64)).error)

    // -- what a call may not be --------------------------------------------------------------------

    print(gzip() catch e -> e.message)
    print(gzip("a", "b") catch e -> e.message)
    print(gzip(5) catch e -> e.message)
    print(gzip([1, 2, "x"]) catch e -> e.message)
    print(gzip([1, 2, 300]) catch e -> e.message)
    print(deflate() catch e -> e.message)
    print(gunzip(packed) catch e -> e.message)
    print(gunzip(packed, "x") catch e -> e.message)
    print(gunzip(packed, 0 - 1) catch e -> e.message)
    print(inflate(z) catch e -> e.message)
    print(inflate(z, 1.5) catch e -> e.message)

main()
