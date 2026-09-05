# `slate:image`

Photographs and avatars — decoding what somebody uploaded, scaling it down, and writing it back out.

```slate
import { readImage, imageShape, resizeImage, encodePNG, encodeJPEG } from slate:image

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
| **read** | PNG, JPEG, GIF (first frame), BMP, TGA, PSD, PIC, PNM, Radiance |
| **write** | PNG, JPEG |

**The format is recognised from the bytes**, so there is nothing to tell `readImage` what to expect
and a file with the wrong extension is read correctly anyway. A GIF decodes to its **first frame**;
there is no animation.

**There is no WebP.** The decoders here are Sean Barrett's `stb_image`, which has never read one —
WebP is VP8 in a RIFF container, which is a video codec's worth of code — so a `.webp` upload is
refused. That is worth knowing because it is what a modern browser writes: a page that re-encodes a
photograph before uploading it often produces WebP, and a form taking images should say which it
accepts.

```slate
val webp = readImage(bytes)

if !webp.ok then print(webp.error)   // "this image could not be read: unknown image type"
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

**`readImage` and `imageShape` answer a result; `resizeImage`, `encodePNG` and `encodeJPEG` fault.**
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

## Not in the JavaScript back end, on either host

Both names refuse under `slate js`, and the two hosts refuse for different reasons. **node has no
image support in its standard library at all** — there is no `zlib`-shaped module for pictures, and
every reader anybody uses is an npm dependency. **A browser does decode**, through
`createImageBitmap` and `OffscreenCanvas` — but the whole of that surface answers **promises**, where
these five answer on the spot, so a browser half would make the two back ends disagree about what an
image even is. That is the same rule `crypto.subtle` is held to: a host that has a thing only in a
different shape does not have it.

So this is a server's module. Resize and re-encode where the interpreter runs, and send the browser
the answer.
