// `slate:dom`'s three page doors, driven against a real DOM.
//
// **jsdom rather than a document written beside the code it checks**, which is the whole reason this
// is worth running: a shim agrees with the code by construction and would pass for every mistake the
// runtime could make. jsdom is somebody else's reading of the same specification and is free to
// disagree. `slate-language/lath` checks the element half of `slate:dom` the same way.
//
//     npm install jsdom
//     slate js check/page.sl -o check/page.js
//     node check/drive.mjs check/page.js
//
// It prints `ok` and nothing else when the runtime is right, and names what it wanted otherwise.
//
// **It is not part of `sysl test .`**, jsdom not being a dependency of this repo and adding one
// putting an `npm install` in front of the suite's one command.

import { JSDOM } from "jsdom"
import { readFileSync } from "node:fs"

// **A real origin and not `about:blank`.** `localStorage` is per origin, and an opaque one has no
// store at all -- a page loaded from a file gets a `SecurityError` on the first access, which is
// exactly the condition the module answers as a result rather than as a fault.
const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    url: "https://example.test/start?q=1#frag",
    runScripts: "outside-only"
})

const w = dom.window
const said = []

// The program prints with `print`, which the runtime writes through the host's console.
w.console = { ...w.console, log: (...parts) => said.push(parts.join(" ")) }

w.eval(readFileSync(process.argv[2], "utf8"))

// **Back is asynchronous in a browser and in jsdom**, the navigation being queued rather than done
// on the spot, so the `popstate` line cannot be read until the queue has turned.
w.history.back()

await new Promise((r) => setTimeout(r, 50))

let failed = 0

const want = (what, got, wanted) => {
    if (got === wanted) return

    console.log("FAIL " + what + ": got " + JSON.stringify(got) + ", wanted " + JSON.stringify(wanted))
    failed += 1
}

const line = (n) => said[n] === undefined ? "<nothing>" : said[n]

want("the protocol", line(0), "protocol https:")
want("the host", line(1), "host example.test")
want("the hostname", line(2), "hostname example.test")
want("the path", line(3), "path /start")
want("the query carries its `?`", line(4), "query ?q=1")
want("the hash carries its `#`", line(5), "hash #frag")

want("a push moves the address bar", line(6), "pushed /one?a=1#top")
want("a replace moves it without a new entry", line(7), "replaced /two")

want("a store answers a result", line(8), 'store {"ok":true,"value":null}')
want("what was stored comes back", line(9), 'stored {"ok":true,"value":"v"}')
want("a key that is not there is null and not a failure", line(10),
    'missing {"ok":true,"value":null}')
want("a number is stored as slate prints it", line(11), 'number {"ok":true,"value":"42"}')
want("the keys are the keys", line(12), 'keys ["k","n"]')
want("unstore takes one away", line(13),
    'unstore {"ok":true,"value":null} then {"ok":true,"value":null}')
want("clear takes them all", line(14),
    'clear {"ok":true,"value":null} then {"ok":true,"value":[]}')
want("the program reached the end", line(15), "ready")

// **The push above must NOT have raised `onNavigate`** -- so the only `navigated` line there can be
// is the one the driver's `back()` caused.
const navigations = said.filter((s) => s.startsWith("navigated "))

want("a push does not raise onNavigate and a back does", navigations.length, 1)

// **And where back LANDS is what says `replacePath` replaced rather than pushed.** The page pushed
// `/one` and then replaced it with `/two`, so the history is the start and `/two` -- two entries and
// not three. One step back is therefore the page it started on, and a `replace` that had quietly
// pushed would land on `/one` here instead.
want("back lands where a replaced entry says it should", navigations[0],
    "navigated /start?q=1#frag")

if (failed === 0) console.log("ok")

process.exit(failed === 0 ? 0 : 1)
