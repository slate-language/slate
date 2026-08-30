// The file system and the environment -- what a program gets from the host it runs on.
//
// Ten file operations, each in a blocking and a promise-shaped form, and the one environment call.
//
// **It writes into a directory of its own under the working directory and takes it away again**, so
// that running it twice says the same thing and running it leaves nothing behind. Everything it
// looks at is something it just made -- nothing here depends on the machine it runs on.

import { readFile, readBytes, writeFile, readDir, stat, exists, remove, mkdir, rmdir, rename,
    readFileSync, readBytesSync, writeFileSync, readDirSync, statSync, existsSync, removeSync,
    mkdirSync, rmdirSync, renameSync } from slate:fs
import { env } from slate:process

val Dir = "tests/js/scratch"

// Whatever a previous run left, so that this one starts from nothing.
sweep()
    if existsSync(Dir)
        for name in sorted(readDirSync(Dir).value)
            removeSync(s"${Dir}/${name}")

        rmdirSync(Dir)

said(r) = if r.ok then s"ok ${r.value}" else s"no ${r.error}"

blocking()
    print("-- blocking")
    print(said(mkdirSync(Dir)))
    print(said(writeFileSync(s"${Dir}/one.txt", "hello")))
    print(said(writeFileSync(s"${Dir}/two.txt", 42)))
    print(said(readFileSync(s"${Dir}/one.txt")))
    print(said(readFileSync(s"${Dir}/two.txt")))
    print(said(readBytesSync(s"${Dir}/one.txt")))
    print(said(statSync(s"${Dir}/one.txt")))
    print(existsSync(s"${Dir}/one.txt"), existsSync(s"${Dir}/nope.txt"))

    // The names in a directory arrive in whatever order the file system keeps them, which is not a
    // thing either back end promises -- so what is compared is the sorted list.
    val listed = readDirSync(Dir)

    print(s"ok ${sorted(listed.value)}")
    print(said(renameSync(s"${Dir}/two.txt", s"${Dir}/three.txt")))
    print(said(readFileSync(s"${Dir}/three.txt")))
    print(said(removeSync(s"${Dir}/three.txt")))

    // And the failures, which are an answer rather than a fault.
    print(said(readFileSync(s"${Dir}/gone.txt")))
    print(said(readDirSync(s"${Dir}/gone")))
    print(said(statSync(s"${Dir}/gone")))
    print(said(removeSync(s"${Dir}/gone")))
    print(said(rmdirSync(s"${Dir}/gone")))
    print(said(mkdirSync(s"${Dir}/one.txt")))
    print(said(readFileSync(Dir)))

// **The promise-shaped ten answer the same shape as the blocking ten**, which is the part worth
// pinning: reaching the disk is expected to fail, so a failure is an answer and not a fault, and the
// pair differ in when the answer arrives and in nothing else.
async waiting()
    print("-- waiting")
    print(said(await readFile(s"${Dir}/one.txt")))
    print(said(await readBytes(s"${Dir}/one.txt")))
    print(said(await stat(s"${Dir}/one.txt")))
    print(await exists(s"${Dir}/one.txt"), await exists(s"${Dir}/nope.txt"))
    print(said(await writeFile(s"${Dir}/four.txt", "written later")))
    print(said(await readFile(s"${Dir}/four.txt")))

    val listed = await readDir(Dir)

    print(s"ok ${sorted(listed.value)}")
    print(said(await rename(s"${Dir}/four.txt", s"${Dir}/five.txt")))
    print(said(await readFile(s"${Dir}/five.txt")))
    print(said(await remove(s"${Dir}/five.txt")))

async refusals()
    print("-- refusals")
    print(said(await readFile(s"${Dir}/gone.txt")))
    print(said(await readDir(s"${Dir}/gone")))
    print(said(await stat(s"${Dir}/gone")))
    print(said(await remove(s"${Dir}/gone")))
    print(said(await rmdir(s"${Dir}/gone")))
    print(said(await mkdir(s"${Dir}/one.txt")))
    print(said(await readFile(Dir)))

// A path is a string, and a builtin that takes one says so before it reaches the file system.
refused()
    print("-- refused")

    val said = try
        readFileSync(5)
    catch e
        e.message

    print(said)

    val more = try
        writeFileSync(s"${Dir}/one.txt")
    catch e
        e.message

    print(more)

// **What a variable HOLDS is the machine's and is not compared** -- only that a variable which is
// set is there and one that is not answers null, which is the whole of what the call promises.
environment()
    print("-- environment")
    // `env(5)` is not here because the static check refuses it before either back end sees it, which
    // is the checker's job and not this program's.
    print(env("PATH") != null)
    print(env("SLATE_NO_SUCH_VARIABLE"))

async everything()
    blocking()
    await waiting()
    await refusals()
    refused()
    environment()

    // And away again, so that the next run starts where this one did.
    sweep()

    print(existsSync(Dir))

sweep()
everything()
