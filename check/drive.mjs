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
const dom = new JSDOM("<!doctype html><html><body><div id=\"app\"></div></body></html>", {
    url: "https://example.test/start?q=1#frag",
    runScripts: "outside-only"
})

const w = dom.window
const said = []

// **jsdom has no `EventSource`, and this is the smallest one that can be wrong.** It proves the
// SHAPING and nothing about a browser's own: what the record's fields are called, that a message
// reaches the handler, and that `close` reaches the source. A shim agrees with the code it checks by
// construction, which is why every other name on this page is driven against jsdom's own DOM and
// this one is not -- what a real host does with `events` is a thing to check in a browser.
const closed = []

w.EventSource = class {
    constructor(url) {
        this.url = url
        this.readyState = 1
        this.onmessage = null
        this.onerror = null
        eventSources.push(this)
    }

    close() {
        this.readyState = 2
        closed.push(this.url)
    }
}

const eventSources = []

// The program prints with `print`, which the runtime writes through the host's console.
w.console = { ...w.console, log: (...parts) => said.push(parts.join(" ")) }

w.eval(readFileSync(process.argv[2], "utf8"))

// One message and one error through the stub, delivered after the program has registered for them.
for (const source of eventSources) {
    if (source.onmessage !== null)
        source.onmessage({ data: "hello", lastEventId: "7", type: "message" })

    if (source.onerror !== null) {
        source.readyState = 2
        source.onerror({})
    }
}

// **A handler that declares nothing and one that declares the event**, both clicked, which is the
// callback rule where a person actually meets it: `onClick={() -> ...}` is what gets written for a
// handler that does not read the event, and making it name one would be a tax on the common case.
for (const id of ["quiet", "curious"])
    w.document.getElementById(id).dispatchEvent(new w.MouseEvent("click", { bubbles: true }))

// **A plain left click and then a cmd-click on the middle button.** These two are what a router has
// to tell apart: the first it may intercept, the second it must let the browser have.
const marked = w.document.getElementById("marked")

marked.dispatchEvent(new w.MouseEvent("click", { bubbles: true, button: 0 }))
marked.dispatchEvent(new w.MouseEvent("click", { bubbles: true, button: 1, metaKey: true, shiftKey: true }))

// **Back is asynchronous in a browser and in jsdom**, the navigation being queued rather than done
// on the spot, so the `popstate` line cannot be read until the queue has turned.
w.history.back()

await new Promise((r) => setTimeout(r, 50))

// **A mutation AFTER the observer disconnected itself**, which is the whole of what `disconnect`
// has to be checked by: the records are queued as a microtask, so an observer that had not really
// stopped would report this one and the count below would be two.
w.document.getElementById("watched").appendChild(w.document.createTextNode("three"))

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
// **The read side, against a document jsdom built rather than one written beside the code.**
want("children counts every child node and not only the elements", line(15), "kids 3")
want("a text node's tag is null, which is how the two are told apart", line(16),
    'tags ["li",null,"li"]')
want("text comes back as text", line(17), 'texts ["apple"," ","pear"]')
want("an attribute comes back", line(18), 'class "one"')
want("a bare attribute is true, which is what setAttribute writes", line(19), "bare true")
want("an attribute that is not there is null", line(20), "absent null")
want("an element says everything under it", line(21), "whole apple pear")

// **What `dispatch` sends is what `on` reads**, which is why each of these is a pair: the line the
// handler printed and the line saying whether the event was cancelled.
want("a dispatched click is a MouseEvent, so button 0 and not null", line(22),
    'poked 0 {"meta":false,"ctrl":false,"shift":false,"alt":false}')
want("and dispatch answers that nothing cancelled it", line(23), "plain true")
want("a button and modifiers go where a handler reads them", line(24),
    'poked 1 {"meta":true,"ctrl":false,"shift":true,"alt":false}')
want("and that one was not cancelled either", line(25), "modified true")
want("a key goes where a handler reads it", line(26), 'typed "Enter"')
want("and a keydown is a KeyboardEvent", line(27), "keyed true")

// **The one thing a sender can learn**, and it is the DOM's own answer: a handler that prevented
// the default makes `dispatchEvent` false.
want("a handler that prevents the default says so through dispatch", line(28), "prevented false")

want("close reaches the source", line(29), "closed null")
want("a lastEventId is refused rather than ignored", line(30),
    "resume `events` cannot be given a `lastEventId`: a browser's `EventSource` sends the last id " +
    "it saw itself and gives a page no way to set one -- read `lastEventId` off each message and " +
    "ask the server for what was missed")
want("an observer that watches nothing is refused here rather than by a TypeError", line(31),
    "nothing `observe` watches for at least one of `children`, `attributes` and `text`, and this asks for none")

want("the program reached the end", line(32), "ready")

// The stub's message and its error, delivered after the program registered for them.
want("a message carries its data, its id and its type", line(33),
    'message {"data":"hello","lastEventId":"7","type":"message"}')
want("an error says whether it is over rather than a retry", line(34), 'error {"closed":true}')

// The two clicks, in the order the driver made them.
want("a handler that declares nothing is called", line(35), "clicked, reading nothing")
want("and one that declares the event is given it", line(36), "clicked, and the event says click")

// **The two a router has to tell apart.** A plain left click is one it may intercept; a cmd-click on
// the middle button is one it must hand to the browser, and without these fields the two are the
// same event.
want("a plain left click reads as button 0 with nothing down", line(35 + 2),
    'click button 0 mods {"meta":false,"ctrl":false,"shift":false,"alt":false}')
want("a cmd-shift middle click says so", line(35 + 3),
    'click button 1 mods {"meta":true,"ctrl":false,"shift":true,"alt":false}')

// **Both mutations in ONE batch and neither of them carrying a node**, which is the record's own
// decision: a handle per added node is a table slot the program would have to give back, and a
// re-render makes hundreds of records.
want("an observer is told what changed and how much", line(35 + 4),
    'changed [{"type":"attributes","attribute":"data-state","added":0,"removed":0},' +
    '{"type":"children","attribute":null,"added":2,"removed":0}]')

const changes = said.filter((s) => s.startsWith("changed "))

want("and it is told once, the observer having disconnected itself", changes.length, 1)
want("the source that was closed is the one the page opened", closed.join(","),
    "http://example.test/e")

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
