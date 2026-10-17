// `slate:process`'s `run`, on both back ends.
//
// **`run` is one question with one answer**: start a program, wait for it and both its pipes, and
// hand back `{ ok: true, value: { status, signal, out, err } }` where there was a child and
// `{ ok: false, error }` where there was none, where it was stopped for taking too long, or where
// what it printed is not text. A child that ran and failed is a success with a non-zero status.
//
// Every program here is `/bin/sh`, a child both back ends have and neither has anything to do with.
// The two sentences that differ between hosts -- none -- are asserted whole, libuv's own words for a
// program that is not there being what the JavaScript host spells too.

import { run } from slate:process
import { seconds } from slate:time

printing(letter, n) = "i=0; while [ $i -lt " + string(n) + " ]; do " +
    "printf '%0200d\\n' 0 | tr 0 " + letter + "; sleep 0.005; i=$((i+1)); done"

whole(text, letter, n) = text.split("\n").filter(l -> l != "").length == n &&
    text.split("\n").filter(l -> l != "").every(l -> l == letter.repeat(200))

async main()
    val ok = await run("/bin/sh", ["-c", "echo out; echo err >&2"])
    print("success", ok.ok, ok.value.status, ok.value.signal, ok.value.out.trim(), ok.value.err.trim())

    val bad = await run("/bin/sh", ["-c", "echo said; echo complained >&2; exit 3"])
    print("non-zero", bad.ok, bad.value.status, bad.value.signal, bad.value.out.trim(), bad.value.err.trim())

    val arg = await run("/bin/sh", ["-c", "echo \"$1|$2\"", "sh", "a b", "c"])
    print("arguments", arg.value.out.trim())

    val noArgs = await run("/bin/echo")
    print("no arguments", noArgs.ok, noArgs.value.status, noArgs.value.out == "\n")

    val here = await run("/bin/sh", ["-c", "pwd"], { cwd: "/" })
    print("cwd", here.value.out.trim())

    val vars = await run("/bin/sh", ["-c", "echo \"$ONE $TWO\""], { env: { ONE: "1", TWO: "2" } })
    print("env", vars.value.out.trim())

    val replaced = await run("/bin/sh", ["-c", "echo \"[$HOME]\""], { env: { ONE: "1" } })
    print("env replaces", replaced.value.out.trim())

    val gone = await run("no-such-program-anywhere", [])
    print("missing", gone.ok, gone.error)

    val absent = await run("/no/such/dir/program", [])
    print("missing path", absent.ok, absent.error)

    val badCwd = await run("/bin/sh", ["-c", "true"], { cwd: "/no/such/dir" })
    print("missing cwd", badCwd.ok, badCwd.error)

    val killed = await run("/bin/sh", ["-c", "kill -TERM $$"])
    print("signal", killed.ok, killed.value.status, killed.value.signal)

    val hup = await run("/bin/sh", ["-c", "kill -KILL $$"])
    print("kill", hup.ok, hup.value.status, hup.value.signal)

    val slow = await run("/bin/sh", ["-c", "sleep 5"], { timeout: 100 })
    print("timeout", slow.ok, slow.error)

    val orphan = await run("/bin/sh", ["-c", "(sleep 0.5) & exit 0"], { timeout: 100 })
    print("timeout after exit", orphan.ok, orphan.error)

    val quick = await run("/bin/sh", ["-c", "echo quick"], { timeout: seconds(30) })
    print("timeout not reached", quick.ok, quick.value.out.trim())

    val big = await run("/bin/sh", ["-c", "yes a | head -c 200000; yes b | head -c 100001 >&2"])
    print("large", big.value.out.length, big.value.err.length, big.value.out[199998], big.value.err[100000])

    val bare = await run("/bin/sh", ["-c", "printf abc; printf x >&2"])
    print("no newline", bare.value.out == "abc", bare.value.err == "x")

    val stdin = await run("/bin/sh", ["-c", "cat; echo done"])
    print("stdin is closed", stdin.value.out.trim())

    val utf = await run("/bin/sh", ["-c", "printf '\\303\\251\\342\\202\\254'"])
    print("utf-8", utf.value.out, utf.value.out.length)

    val raw = await run("/bin/sh", ["-c", "printf '\\377'"])
    print("not text", raw.ok, raw.error)

    val rawErr = await run("/bin/sh", ["-c", "printf '\\377' >&2"])
    print("not text on stderr", rawErr.ok, rawErr.error)

    val ignored = await run("/bin/sh", ["-c", "echo ok"], { ipc: 5, unknown: true })
    print("unknown options are ignored", ignored.value.out.trim())

    // Two children read at once never see each other's bytes.
    val a = run("/bin/sh", ["-c", printing("A", 60)])
    val b = run("/bin/sh", ["-c", printing("B", 60)])
    val rb = await b
    val ra = await a
    print("two children", ra.value.status, rb.value.status, whole(ra.value.out, "A", 60), whole(rb.value.out, "B", 60))

    // The answer is a promise and never arrives during the call.
    var during = "after"
    val p = run("/bin/sh", ["-c", "exit 0"])
    during = "before"
    print("promise", (await p).value.status, during)

    // Refusals at the call are faults, in the interpreter's words.
    print((await run()) catch e -> e.message)
    print((await run(1)) catch e -> e.message)
    print((await run("/bin/sh", "x")) catch e -> e.message)
    print((await run("/bin/sh", [1])) catch e -> e.message)
    print((await run("/bin/sh", [], 5)) catch e -> e.message)
    print((await run("/bin/sh", [], { cwd: 5 })) catch e -> e.message)
    print((await run("/bin/sh", [], { env: 5 })) catch e -> e.message)
    print((await run("/bin/sh", [], { env: { A: 1 } })) catch e -> e.message)
    print((await run("/bin/sh", [], { timeout: "x" })) catch e -> e.message)
    print((await run("/bin/sh", [], {}, 4)) catch e -> e.message)
main()
