// `files(root)` — what a static server refuses, on both back ends.
//
// **A traversal is a question about the PATH a request wrote, so nothing here may go through
// `fetch`.** A URL parser resolves `..` and reads `%2e%2e` as a dotted segment before a byte reaches
// the network, so a client that builds a URL cannot ask the question at all — `curl` needs
// `--path-as-is` for the same reason. The request line is written onto a socket here instead, which
// is what an attacker does and what `slate:net` makes ordinary.
//
// **The root is made, served and taken away by the program**, so running it twice says the same
// thing and running it leaves nothing behind. `pubsecret.txt` sits OUTSIDE the root and is what a
// successful climb would hand back — every answer below says whether it leaked, so a refusal is
// checked against the file it was refusing rather than only against its own status line.

import { connect, onData, send, close, localPort } from slate:net
import { serve, files, close as shutServer } from slate:http
import { writeFileSync, mkdirSync, removeSync, rmdirSync, existsSync } from slate:fs

val Root = "tests/js/pubroot"
val Secret = "tests/js/pubsecret.txt"

// Whatever a previous run left, so that this one starts from nothing.
sweep()
    if existsSync(s"${Root}/a.txt") then removeSync(s"${Root}/a.txt")
    if existsSync(s"${Root}/sub") then rmdirSync(s"${Root}/sub")
    if existsSync(Root) then rmdirSync(Root)
    if existsSync(Secret) then removeSync(Secret)

lay()
    mkdirSync(Root)
    mkdirSync(s"${Root}/sub")
    writeFileSync(s"${Root}/a.txt", "under the root")
    writeFileSync(Secret, "LEAKED")

// One request, written as text onto a socket and read back whole.
//
// **`Connection: close` is what ends it**, so the answer is complete when the socket says there is
// no more rather than after a number of milliseconds.
async ask(port, target)
    val dialled = await connect("127.0.0.1", port)
    val c = dialled.value
    var got = ""
    var ended = false

    onData(c, chunk ->
        if chunk == null
            close(c)
            ended = true
        else
            got = got + chunk)

    await send(c, "GET " + target + " HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n")

    var turns = 0

    while !ended && turns < 400
        await sleep(10)
        turns = turns + 1

    got

// The status line, and whether the file above the root came back with it. Nothing else is compared:
// an `ETag` carries the moment the file was written, which the two back ends write at two different
// moments.
said(answer) =
    val line = split(answer, "\r\n")[0]

    if contains(answer, "LEAKED") then line + " LEAKED" else line

async main()
    sweep()
    lay()

    val server = serve(0, files(Root))
    val port = localPort(server)

    // What is under the root is served, and a percent-escape that decodes to an ordinary character
    // is decoded and served — the refusals below are about what a part MEANS, not about the `%`.
    print("plain           ", said(await ask(port, "/a.txt")))
    print("escaped dot     ", said(await ask(port, "/a%2etxt")))
    print("a dot part      ", said(await ask(port, "/%2e/a.txt")))

    // The climb, written the four ways. The first is the one every server refuses; the other three
    // are the same climb wearing a percent-escape, and each of them was answered `200` before the
    // parts were decoded before they were judged.
    print("plain climb     ", said(await ask(port, "/../pubsecret.txt")))
    print("encoded climb   ", said(await ask(port, "/%2e%2e/pubsecret.txt")))
    print("encoded slash   ", said(await ask(port, "/..%2fpubsecret.txt")))
    print("both encoded    ", said(await ask(port, "/%2e%2e%2fpubsecret.txt")))
    print("climb twice     ", said(await ask(port, "/%2e%2e%2f%2e%2e%2fetc%2fpasswd")))

    // An encoded separator is refused even where it climbs nothing: it is one part naming two, and a
    // server that took it would be deciding for itself what the client meant.
    print("bare encoded /  ", said(await ask(port, "/%2f...")))

    // A NUL truncates a name at the system call rather than here, so it never gets that far.
    print("a nul           ", said(await ask(port, "/a%00.txt")))

    // A `%` that is not two hex digits is a literal `%` to a browser and to `percentDecode`. A path
    // is the one place where taking that guess makes the guess a file name.
    print("bad escape      ", said(await ask(port, "/%zz")))
    print("short escape    ", said(await ask(port, "/a%2")))

    // **A file that is not there and a directory with no index answer the same 404**, which is the
    // rule that was already here: telling a client which is which maps out the disk for it.
    print("nothing there   ", said(await ask(port, "/nope.txt")))
    print("a directory     ", said(await ask(port, "/sub")))

    shutServer(server)
    sweep()

    print("cleaned up      ", !existsSync(Root), !existsSync(Secret))

main()
