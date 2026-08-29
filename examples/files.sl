// The file system, in both forms, and what a call that can fail answers with.
//
// **Every one of these answers a result rather than raising.** A file that is not there is not a
// defect in the program asking for it, so it comes back as `{ ok: false, error: ... }` and the
// caller decides. What `catch` is for is the other kind -- the failures nothing could have
// anticipated -- and `try.sl` is the example for those.

import { mkdir, writeFile, readFile, readDir, stat, exists, readBytes, rename, readFileSync, remove, rmdir } from slate:fs

async main()
    await mkdir("scratch")
    await writeFile("scratch/notes.txt", "one line")

    // The plain reading: ask, then look at what came back.
    val notes = await readFile("scratch/notes.txt")

    if notes.ok
        print(notes.value)
    else
        print("could not read the notes:", notes.error)

    // A result is an ordinary object, so a pattern takes one apart with no syntax of its own.
    await readDir("scratch") match
        { ok: true, value: names } -> print(names)
        { error: e } -> print("could not list it:", e)

    val about = (await stat("scratch/notes.txt")).value

    print(about.size, about.isFile, about.isDir)

    // `exists` is the one call with no failure case, so it answers a plain `true` or `false`.
    print(await exists("scratch/notes.txt"), await exists("scratch/gone.txt"))

    // Bytes, for a file that is not text -- `readFile` answers an error naming `readBytes`.
    print((await readBytes("scratch/notes.txt")).value)

    // And a file that really is not there. Nothing stops; the program reads the answer and carries
    // on, which is the whole of what a result buys over a fault.
    val missing = await readFile("scratch/nothing-here.txt")

    print(missing.ok, missing.error)

    await rename("scratch/notes.txt", "scratch/kept.txt")
    print((await readDir("scratch")).value)

    // The blocking half answers exactly the same shape, and needs no `async` around it.
    print(readFileSync("scratch/kept.txt").value)

    // Everything made is taken away again, so the example leaves nothing behind.
    await remove("scratch/kept.txt")
    await rmdir("scratch")
    print(await exists("scratch"))

main()
