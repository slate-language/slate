---
title: "slate:fs"
weight: 20
---

# `slate:fs`

Ten operations, each in a promise-shaped and a blocking form.

```slate
import { readFile, writeFile, mkdir, readDir, rename, remove, rmdir } from slate:fs

async main()
    await mkdir("scratch")
    await writeFile("scratch/notes.txt", "one line")

    val notes = await readFile("scratch/notes.txt")

    if notes.ok
        print(notes.value)
    else
        print("could not read it:", notes.error)

    await readDir("scratch") match
        { ok: true, value: names } -> print(names)
        { error: e } -> print(e)

    await rename("scratch/notes.txt", "scratch/kept.txt")
    await remove("scratch/kept.txt")
    await rmdir("scratch")

main()
```

| | |
|---|---|
| `readFile(path)` | text |
| `readBytes(path)` | [`bytes`](bytes.md) |
| `writeFile(path, v)` | replaces whatever was there |
| `appendFile(path, v)` | adds to it, and makes the file where there is none |
| `writeBytes(path, bs)` | the same, given the bytes themselves |
| `appendBytes(path, bs)` | |
| `readDir(path)` | the names in it |
| `stat(path)` | size, kind, and `mtime` as an [instant](time.md) |
| `exists(path)` | a plain `true` or `false` — the one call with no failure case |
| `remove(path)` | |
| `mkdir(path)` | |
| `rmdir(path)` | |
| `rename(from, to)` | |

**Every one has a blocking twin under a `Sync` suffix** — `readFileSync`, `writeFileSync`,
`appendFileSync`, `statSync` and the rest — which is node's arrangement and node's spelling:

```slate
mkdirSync("scratch")
writeFileSync("scratch/notes.txt", "one line")

print(readFileSync("scratch/notes.txt").value)
```

## Results, not rejections

**A call that can fail answers a result — `{ ok: true, value: v }` or `{ ok: false, error: text }` — and
the promise never rejects.** A file that is not there is not a defect in the program asking for it, so the
caller is handed something it has to look at rather than an unwind it has to be ready for.

**Giving a builtin the wrong kind of argument still raises**: `readFile(42)` faults, `readFile("/gone")`
answers.

Every error carries libuv's own sentence — `cannot read x: ENOENT: no such file or directory`.

A file that is not valid UTF-8 has no slate string to become, so `readFile` answers an error **naming
`readBytes`**. `writeFile` renders anything that is not a string the way `print` would.

**`writeBytes` and `appendBytes` are the writing side of `readBytes`**, and they are what a program
holding bytes wants: `writeFile` would render a buffer as the text `<bytes 8192: 89 50 ...>`, which
is a picture of a PNG rather than one. Each takes a [buffer](bytes.md) or an array of numbers from 0
to 255; anything else is a fault naming `writeFile` as the call that renders things.

## Why the plain names are the asynchronous ones

A language whose entire event story is one loop has a lot to lose from a call that stops it: a server that
blocks on a read stops answering everybody. The `Sync` forms are there because a great many programs are
not servers — a script that reads a configuration file before it does anything gains nothing from a promise
and pays for it in an `async` function that exists only to hold an `await`.

**The naming is what keeps that from being a trap.** The blocking call is the one with the longer name and
the suffix, so reaching for it is a decision rather than an accident. The two halves agree on everything
but the waiting: a `Sync` call answers the same result its promise would have settled to, error and all.

## `watch`

**`watch(dir, fn)` calls `fn` every time something under `dir` changes, and `unwatch(id)` stops it.** The
operating system says what changed — nothing is polled — and the whole tree is watched, including
directories made after the watch began.

```slate
import { watch, unwatch, mkdirSync, writeFileSync, removeSync, rmdirSync } from slate:fs

mkdirSync("watched-tree")

var w = null
var edits = 0

// Keep saving until the watcher hears: its stream takes a moment to start.
save()
    edits = edits + 1
    writeFileSync("watched-tree/notes.txt", "draft " + string(edits))

val saving = setInterval(save, 20)

changed(e)
    if e.path != "notes.txt" then return

    print(e.path)
    unwatch(w)
    clearInterval(saving)
    removeSync("watched-tree/notes.txt")
    rmdirSync("watched-tree")

w = watch("watched-tree", changed).value
```

```output
notes.txt
```

| | |
|---|---|
| `watch(dir, fn)` | `{ ok: true, value: id }`, or `{ ok: false, error }` for a directory that is not there or is not a directory |
| `unwatch(id)` | stops that watcher; an id that names nothing is not an error |
| the event | `{ path, kind }` — the path relative to `dir`, and `"rename"` or `"change"` |

**The answer is a result, as everywhere in `slate:fs`**, and the id is `setTimeout`'s and `onSignal`'s
convention: `unwatch` takes it, nothing else reads it, and one that has been stopped names nothing. A
wrong argument — `watch(42, fn)`, a handler that is not a function — still faults.

**`path` is `null` where the platform did not say which entry it was, and a change to the watched
directory ITSELF is named by the directory's own last component** — the example above, which made
`watched-tree` a moment before watching it, may be told `watched-tree` first, which is why it waits for
the name it wants. `kind` is `"rename"` for a name
appearing or going (a new file, a removed one, both ends of a rename) and `"change"` for new contents,
which are node's two words and libuv's.

### One save is several events

**Nothing inside `watch` merges them, because only the caller knows how long a burst lasts.** An editor
writes a temporary file and renames it over the old one, a formatter rewrites three files, and macOS
carries a file's recent history in the flags of a later event — so a file made a moment ago is still
reported as a `"rename"` when it is written to. Treat an event as *look again*, not as a description of
what is on the disk, and settle a burst before acting on it:

```slate
var settling = null

rebuild() = print("rebuilding")

watch("src", e ->
    if settling != null then clearTimeout(settling)
    settling = setTimeout(rebuild, 100))
```

### A watcher keeps the program running

**Unlike a signal handler, which does not.** `onSignal` arms something that may happen while a program
does whatever it is for; a file watcher is usually what the program is *for* — a development server, a
rebuild loop — and one that watched a directory and then ended at once would have done nothing. That is
node's rule too: `fs.watch` is `persistent` unless asked otherwise. So a program with a watcher in it
runs until it calls `unwatch`, and a test that watches must unwatch: one that forgets is failed with
`left 1 handle open: a file watcher on …`.

### macOS only, for now

**The tree is watched with FSEvents, which is recursive.** On Linux, inotify watches one directory at
a time and libuv does not walk the tree, so a recursive watch would silently miss every edit below the
top level. `watch` answers an error there instead — `cannot watch src: watching a directory tree needs
macOS's FSEvents, and inotify on this platform watches one directory at a time` — and so does the
JavaScript back end, even though node can walk the tree itself, so that one program behaves one way on
either host.
