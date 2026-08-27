// The file system, which is ten builtins and no blocking form.

async main()
    await mkdir("scratch")
    await writeFile("scratch/notes.txt", "one line")

    print(await readFile("scratch/notes.txt"))
    print(await readDir("scratch"))

    val about = await stat("scratch/notes.txt")

    print(about.size, about.isFile, about.isDir)

    // `exists` answers rather than failing, which is the whole of what it adds over `stat`.
    print(await exists("scratch/notes.txt"), await exists("scratch/gone.txt"))

    // Bytes, for a file that is not text -- `readFile` refuses one by name.
    print(await readBytes("scratch/notes.txt"))

    await rename("scratch/notes.txt", "scratch/kept.txt")
    print(await readDir("scratch"))

    // Everything made is taken away again, so the example leaves nothing behind.
    await remove("scratch/kept.txt")
    await rmdir("scratch")
    print(await exists("scratch"))

main()
