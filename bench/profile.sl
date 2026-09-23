// Sample every `bench/*.sl` program under macOS `sample` and collect each one's top self-time
// symbols into one Markdown report -- the shell script every profile agent had been hand-rolling
// beside `bench/results/`, written once.
//
// Usage:
//
//   slate bench/profile.sl --out=PATH [--binary=./slate] [--duration=10] [--interval=1] [program.sl ...]
//
// `--out` is required and names the Markdown file to write. `--binary` is the executable `sample`
// attaches to (default `./slate`); the remaining bare arguments are the programs to run under it,
// each one a path handed to `<binary>` as its sole argument -- default is every `*.sl` file directly
// under `bench/`, this file excluded. `--duration` is the number of seconds `sample` watches for
// (default 10) and `--interval` the sampling interval in milliseconds (default 1), both passed
// straight through to `sample`.
//
// Each program is started, sampled where it stands, and killed once the sample has what it wants --
// serially, one shell call per program, exactly as `bench/results/2026-09-22-sampled-profile-5.md`
// describes doing this by hand. A program that exits before the sampler can attach (`startup`,
// `strindex`, `strwalk`) is reported with no rows rather than failing the whole run.

import { args, exit, run, spawn } from slate:process
import { readDirSync, writeFileSync } from slate:fs

val TableRows = 12

// -- command line -----------------------------------------------------------------------------------

flag(name, fallback) ->
    val prefix = "--" + name + "="

    for a in args
        if startsWith(a, prefix)
            return a[prefix.length..<a.length]

    fallback

positional() ->
    var out = []

    for a in args
        if !startsWith(a, "--")
            out.push(a)

    out

// Every `*.sl` file directly under `bench/`, this tool excluded, in a stable order.
defaultPrograms() ->
    readDirSync("bench") match
        { ok: true, value: names } ->
            names.filter(n -> endsWith(n, ".sl") && n != "profile.sl")
                .sorted((a, b) -> if a < b then -1 elif a > b then 1 else 0)
                .map(n -> "bench/" + n)
        { error: e } ->
            print("cannot read bench/: " + string(e))
            exit(1)

// -- reading `sample`'s own report -------------------------------------------------------------------

// The rows of `sample`'s "Sort by top of stack, same collapsed" section: a count and a symbol name,
// which is self time and is what every figure in `bench/results/` reads. Answers `[]` where the
// marker never appears, which is what a `sample` that never attached looks like.
parseCollapsed(text) ->
    val lines = split(text, "\n")
    var marker = -1
    var i = 0

    while i < lines.length
        if indexOf(lines.at(i), "Sort by top of stack, same collapsed") != null
            marker = i

        i = i + 1

    var rows = []

    if marker >= 0
        var j = marker + 1
        var going = true

        while going && j < lines.length
            val t = trim(lines.at(j))

            if t.length == 0
                if rows.length > 0
                    going = false
            elif t.at(0) >= "0" && t.at(0) <= "9"
                val sp = indexOf(t, " ")

                if sp != null
                    val count = number(t[0..<sp])
                    val rest = trim(t[sp..<t.length])
                    val cut = indexOf(rest, "  (in ")
                    val two = indexOf(rest, "  ")
                    val symEnd = if cut != null then cut elif two != null then two else rest.length

                    rows.push({ symbol: trim(rest[0..<symEnd]), samples: count })
            else
                if rows.length > 0
                    going = false

            j = j + 1

    rows

// -- the report ---------------------------------------------------------------------------------------

formatPct(n) -> string(round(n * 10) / 10)

// The table and the one-line summary for a single program's rows, as one Markdown section.
reportFor(name, rows) ->
    val total = rows.reduce(0, (acc, r) -> acc + r.samples)
    val ranked = rows.sorted((a, b) -> b.samples - a.samples)
    val topRows = ranked.slice(0, min(TableRows, ranked.length))

    val body = topRows
        .map(r -> "| " + r.symbol + " | " + string(r.samples) + " | " + formatPct(r.samples / total * 100) + "% |")
        .join("\n")

    val summary = if topRows.length > 0
        then string(total) + " samples; top: `" + topRows.at(0).symbol + "` at " +
            formatPct(topRows.at(0).samples / total * 100) + "%."
        else "no samples -- the program likely exited before `sample` could attach."

    "### " + name + "\n\n| symbol | samples | % |\n|---|---|---|\n" + body + "\n\n" + summary + "\n"

// -- driving `sample` -----------------------------------------------------------------------------

// Start `program` under `binary`, sample the child for `duration` seconds at `interval` milliseconds,
// and answer its Markdown section. The child is killed once the sample is in hand, whether or not it
// was still running.
async profileOne(binary, program, duration, interval)
    print("sampling " + program + " ...")

    spawn(binary, [program]) match
        { ok: false, error: e } ->
            "### " + program + "\n\nfailed to start `" + binary + " " + program + "`: " + string(e) + "\n"
        { ok: true, value: worker } ->
            val timeoutMs = (number(duration) + 10) * 1000
            val sampled = await run("/usr/bin/sample",
                [string(worker.pid), duration, interval, "-mayDie"], { timeout: timeoutMs })

            worker.kill()
            await worker.exited

            sampled match
                { ok: true, value: res } -> reportFor(program, parseCollapsed(res.out))
                { ok: false, error: e } -> "### " + program + "\n\n`sample` failed: " + string(e) + "\n"

async main()
    val outPath = flag("out", "")

    if outPath == ""
        print("usage: slate bench/profile.sl --out=PATH [--binary=./slate] [--duration=10] [--interval=1] [program.sl ...]")
        exit(2)

    val binary = flag("binary", "./slate")
    val duration = flag("duration", "10")
    val interval = flag("interval", "1")
    val given = positional()
    val programs = if given.length > 0 then given else defaultPrograms()

    var sections = []

    for p in programs
        sections.push(await profileOne(binary, p, duration, interval))

    val header = "# slate bench profile\n\nBinary: `" + binary + "`, duration " + duration +
        "s, interval " + interval + "ms.\n\n"

    writeFileSync(outPath, header + sections.join("\n"))
    print("wrote " + outPath)

main()
