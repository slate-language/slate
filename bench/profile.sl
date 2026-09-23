// Sample every `bench/*.sl` program under macOS `sample` and collect each one's top self-time
// symbols into one Markdown report.
//
// Usage:
//
//   slate bench/profile.sl --out=PATH [--binary=./slate] [--duration=10] [--interval=1] [program.sl ...]
//
// `--out` is required and names the Markdown file to write. `--binary` is the executable each program
// is run under (default `./slate`); the bare arguments are the programs, each handed to `<binary>` as
// its one argument -- every `*.sl` directly under `bench/` where none is named, this file excluded.
// `--duration` is how many seconds `sample` watches (default 10) and `--interval` its sampling
// interval in milliseconds (default 1), both handed straight to `sample`.
//
// Each program is started, sampled where it stands, and killed once the sample is in hand, one at a
// time. A program that ends before `sample` can attach gets a section saying so rather than failing
// the run. The rows are `sample`'s own "Sort by top of stack, same collapsed" section, which is self
// time and is what every sampled profile under `bench/results/` reads.

import { args, exit, run, spawn } from slate:process
import { readDirSync, readFileSync, removeSync, writeFileSync } from slate:fs

val TableRows = 12
val Marker = "Sort by top of stack, same collapsed"

// -- the command line ----------------------------------------------------------------------------

flag(name, fallback)
    val prefix = "--" + name + "="

    for a in args
        if a.startsWith(prefix)
            return a[prefix.length..<a.length]

    fallback

given()
    args.filter(a -> !a.startsWith("--"))

// Every `*.sl` directly under `bench/`, this program excluded, in name order.
everyProgram()
    readDirSync("bench") match
        { ok: true, value: names } ->
            names.filter(n -> n.endsWith(".sl") && n != "profile.sl").sorted().map(n -> "bench/" + n)
        { error: e } ->
            print("cannot read bench/:", e)
            exit(2)

// -- reading `sample`'s report --------------------------------------------------------------------

// One row of the collapsed section, `symbol  (in image)        count`, as `{ symbol, samples }` --
// or null for a line that is not one.
row(line)
    val t = line.trim()
    val gap = t.lastIndexOf(" ")

    if gap == null
        return null

    val count = number(t[gap + 1..<t.length])

    if count == null
        return null

    val head = t[0..<gap].trim()
    val cut = head.indexOf("  (in ") ?? head.length

    { symbol: head[0..<cut].trim(), samples: count }

// The rows under `Marker`, which run to the first line that is not one. `[]` where the marker never
// appears, which is what a `sample` that could not attach leaves behind.
collapsed(text)
    val lines = text.split("\n")
    val at = lines.findIndex(l -> l.startsWith(Marker))
    var rows = []

    if at == null || at < 0
        return rows

    for line in lines.slice(at + 1)
        val r = row(line)

        if r == null
            break

        rows.push(r)

    rows

// -- the report ------------------------------------------------------------------------------------

percent(part, whole) = toFixed(part * 100.0 / whole, 1)

section(program, rows)
    val total = rows.reduce((sum, r) -> sum + r.samples, 0)

    if total == 0
        return "## " + program + "\n\nNo samples: the program ended before `sample` could attach.\n"

    val top = rows.sorted((a, b) -> a.samples > b.samples).slice(0, TableRows)
    val table = top.map(r -> "| `" + r.symbol + "` | " + string(r.samples) + " | " + percent(r.samples, total) + " |")

    "## " + program + "\n\n" + string(total) + " samples.\n\n| symbol | samples | % |\n|---|---:|---:|\n" +
        table.join("\n") + "\n"

// -- driving `sample` ----------------------------------------------------------------------------

// Start `program` under `binary`, sample it, kill it, and answer its section of the report.
async profiled(binary, program, duration, interval, scratch)
    print("sampling", program)

    val started = spawn(binary, [program])

    if !started.ok
        return "## " + program + "\n\n`" + binary + "` could not be started: " + string(started.error) + "\n"

    val child = started.value
    val limit = (number(duration) + 30) * 1000
    val sampled = await run("/usr/bin/sample", [string(child.pid), duration, interval, "-mayDie", "-file", scratch],
        { timeout: limit })

    child.kill()
    await child.exited

    val text = readFileSync(scratch) match
        { ok: true, value: t } -> t
        _ -> ""

    removeSync(scratch)
    section(program, collapsed(text))

async main()
    val out = flag("out", "")

    if out == ""
        print("usage: slate bench/profile.sl --out=PATH [--binary=./slate] [--duration=10] [--interval=1] [program.sl ...]")
        exit(2)

    val binary = flag("binary", "./slate")
    val duration = flag("duration", "10")
    val interval = flag("interval", "1")
    val named = given()
    val programs = if named.length > 0 then named else everyProgram()
    val scratch = out + ".sample.txt"
    var sections = []

    for p in programs
        sections.push(await profiled(binary, p, duration, interval, scratch))

    val head = "# slate bench profile\n\nSelf time from macOS `sample`: binary `" + binary + "`, " + duration +
        " s per program at " + interval + " ms.\n"

    writeFileSync(out, head + "\n" + sections.join("\n"))
    print("wrote", out)

main()
