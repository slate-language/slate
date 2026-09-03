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
| `readBytes(path)` | an array of numbers |
| `writeFile(path, v)` | replaces whatever was there |
| `appendFile(path, v)` | adds to it, and makes the file where there is none |
| `readDir(path)` | the names in it |
| `stat(path)` | size, kind, and `mtime` as an [instant](time.md) |
| `exists(path)` | a plain `true` or `false` — the one call with no failure case |
| `remove(path)` | |
| `mkdir(path)` | |
| `rmdir(path)` | |
| `rename(from, to)` | |

**Every one has a blocking twin under a `Sync` suffix** — `readFileSync`, `writeFileSync`, `statSync` and
the rest — which is node's arrangement and node's spelling:

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

## Why the plain names are the asynchronous ones

A language whose entire event story is one loop has a lot to lose from a call that stops it: a server that
blocks on a read stops answering everybody. The `Sync` forms are there because a great many programs are
not servers — a script that reads a configuration file before it does anything gains nothing from a promise
and pays for it in an `async` function that exists only to hold an `await`.

**The naming is what keeps that from being a trap.** The blocking call is the one with the longer name and
the suffix, so reaching for it is a decision rather than an accident. The two halves agree on everything
but the waiting: a `Sync` call answers the same result its promise would have settled to, error and all.
