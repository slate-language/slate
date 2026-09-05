# `slate:image`

Photographs and avatars — decoding what somebody uploaded, scaling it down, and writing it back out.

```slate
import { readImage, imageShape, resizeImage, encodePNG, encodeJPEG, encodeWebP } from slate:image

// An image is a record. Four pixels, three channels, rows packed and the top row first.
val square = { width: 2, height: 2, channels: 3,
    pixels: [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255] }

val png = encodePNG(square)

print(png[0], png[1], png[2], png[3])        // the PNG signature

val back = readImage(png)

print(back.ok, back.value.width, back.value.height, back.value.channels)

val bigger = resizeImage(back.value, 4, 4)

print(bigger.width, bigger.height, len(bigger.pixels))

// The shape without decoding anything, which is what to ask of an upload.
print(imageShape(png).value.width, imageShape(png).value.height)

print(readImage(toBytes("not an image")).ok)
```

```output
137 80 78 71
true 2 2 3
4 4 48
2 2
false
```

## An image is a record, not a handle

`{ width, height, channels, pixels }`, where `pixels` is a byte array of `width * height * channels`
— rows packed with no padding, the top row first, and the channels interleaved. Every name here
either answers one or takes one, so a thumbnail is one expression:

```slate
val small = encodeJPEG(resizeImage(readImage(upload).value, 200, 200), 80)
```

Nothing in the middle is a resource to give back, and the pixels are ordinary slate values: a program
can read them, store them, send them, or build an image itself and encode that — which is what the
runnable program above does.

## What it reads and what it writes

| | |
|---|---|
| **read** | PNG, JPEG, GIF (first frame), WebP, BMP, TGA, PSD, PIC, PNM, Radiance |
| **write** | PNG, JPEG, WebP |

**The format is recognised from the bytes**, so there is nothing to tell `readImage` what to expect
and a file with the wrong extension is read correctly anyway. A GIF decodes to its **first frame**;
there is no animation.

## WebP, which is what a browser writes

Everything above but WebP is Sean Barrett's `stb_image`, which has never read one — WebP is VP8 in a
RIFF container, a video codec's worth of code. WebP is libwebp, and it is here because it is what a
modern browser produces: a page that re-encodes a photograph before uploading it usually writes one,
so without it the commonest upload a form meets would be the one `readImage` refuses.

Nothing about the call changes. The header says which decoder answers, and `channels` comes back as
3 or 4 — a WebP carries RGB or RGBA and there is no greyscale form of the file, though
`readImage(bytes, 1)` converts one for you exactly as it does a PNG.

```slate
import { readImage, imageShape, encodeWebP } from slate:image

val src = { width: 2, height: 2, channels: 4,
    pixels: [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 128] }

val file = encodeWebP(src, { lossless: true })

print(file[0], file[1], file[2], file[3])       // "RIFF"
print(file[8], file[9], file[10], file[11])     // "WEBP"

val shape = imageShape(file).value

print(shape.width, shape.height, shape.channels)
print(readImage(file).value.pixels == src.pixels)

// A quality instead of a record is the lossy coder, which keeps the alpha either way.
print(len(encodeWebP(src, 40)) < len(encodeWebP(src, 100)))
```

```output
82 73 70 70
87 69 66 80
2 2 4
true
true
```

**An animated WebP is refused**, and says which library reading one would take. Its frames live in
`ANMF` chunks that only `libwebpdemux` walks, and that is a second library nothing here binds:

```slate
val anim = readImage(bytes)

if !anim.ok then print(anim.error)
// "this is an animated WebP; reading one needs libwebpdemux, which this package does not bind"
```

**A truncated WebP says it is truncated** rather than that it is damaged, which is the difference
between an upload worth asking for again and one that is not:

```slate
print(readImage(partial).error)   // "the WebP data stops before the image does"
```

## `channels`, and asking for a different number

`readImage(bytes)` converts nothing: `channels` comes back as 1, 2, 3 or 4 depending on what the file
held. `readImage(bytes, 4)` converts on the way out, which is the call an avatar pipeline makes —
uploads arrive greyscale, RGB and RGBA in whatever mixture the people using a site happened to have,
and code that composites or scales them wants one shape.

```slate
val avatar = readImage(upload, 4).value    // always RGBA, whatever arrived
```

## The two channels

**`readImage` and `imageShape` answer a result; `resizeImage` and the three encoders fault.**
That is the rule the whole library follows: bytes from somewhere else are an answer the caller has to
look at — a corrupt JPEG is a `400` to send, not a defect in the program reading it — and a value the
program built itself is a fault. So a mismatched `pixels`, a width of zero, or a quality of 200 stops
the program where it is written.

## `imageShape` is the size guard, and that is why it exists

A decoded image is `width * height * channels` bytes **however small the file was**. A PNG of four
kilobytes can say it is 20,000 by 20,000, which is 1.2 GB the moment anything decodes it — the same
shape of attack a compression bomb is, wearing a picture's clothes. `imageShape` reads the width,
height and channel count out of the header without decoding anything, so a handler can answer `413`
instead:

```slate
val shape = imageShape(body)

if !shape.ok then return { status: 400, text: shape.error }
if shape.value.width * shape.value.height > 40_000_000 then return { status: 413 }

val img = readImage(body).value
```

## Scaling

`resizeImage(image, width, height)` answers the same image at another size, eight bits a channel, and
keeps the channel count it was given. **The filtering happens in sRGB space**, which is the right
answer for every 8-bit image a page holds: averaging two sRGB bytes as though they were quantities of
light is what makes a naively downscaled photograph come out too dark.

Nothing here preserves the aspect ratio for you — the two numbers are what the answer will be — so
work them out from the shape you read:

```slate
val wide = 200 / max(img.width, img.height)
val thumb = resizeImage(img, integer(img.width * wide), integer(img.height * wide))
```

## The quality is written at every call

`encodeJPEG(image, quality)` takes a number from 1 to 100 and there is no default, for
[`slate:zstd`](zstd.md)'s reason and [`slate:brotli`](brotli.md)'s: it is the one number a caller has
to think about, and no single value is right often enough to be the quiet one. 80 is a photograph on
a page, 60 a thumbnail, 95 something that will be edited again.

`encodePNG` takes no such number — PNG is lossless, and it is what to reach for unless the image
really is a photograph. The encoder is stb's baseline JPEG writer: no progressive mode and no
subsampling control, which is small, fast, and read by everything.

`encodeWebP` takes **either**, and that is the one signature here with two forms:

| | |
|---|---|
| `encodeWebP(image, quality)` | lossy, 1 to 100, roughly a quarter smaller than a JPEG at the same quality — **and it keeps an alpha channel**, which JPEG cannot |
| `encodeWebP(image, { lossless: true })` | nothing thrown away, and about a fifth smaller than the PNG of the same image |

Two forms rather than two names, because the second argument is what a caller has to think about
either way and lossless is a value it can take. `{ lossless: false }` is refused rather than read as
"lossy", since a lossy encode needs a number nobody wrote.

A one- or two-channel image is widened to RGB or RGBA on the way out — there is no greyscale WebP —
which is what a browser decoding the file would have shown anyway.

## Not in the JavaScript back end, on either host

All six names refuse under `slate js`, and the two hosts refuse for different reasons. **node has no
image support in its standard library at all** — there is no `zlib`-shaped module for pictures, and
every reader anybody uses is an npm dependency. **A browser does decode**, through
`createImageBitmap` and `OffscreenCanvas` — WebP as readily as PNG — but the whole of that surface
answers **promises**, where these six answer on the spot, so a browser half would make the two back
ends disagree about what an image even is. That is the same rule `crypto.subtle` is held to: a host
that has a thing only in a different shape does not have it.

So this is a server's module. Resize and re-encode where the interpreter runs, and send the browser
the answer.
