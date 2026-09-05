// The three doors a browser has and nothing else does, driven against a real DOM.
//
// **This is not under `tests/` and it cannot be.** Every name it imports faults under the
// interpreter -- that refusal is what says `slate:dom` is working -- so a suite that walked this
// file would fail on the very thing it is checking. `check/README.md` says how to run it, and
// `slate-language/lath` keeps its own DOM check the same way and for the same reason.

import { location, pushPath, replacePath, back, onNavigate } from slate:dom
import { byId, createElement, createText, setAttribute, setChildren, on } from slate:dom
import { children, tagName, nodeText, attribute } from slate:dom
import { insertBefore, dispatch, observe, events } from slate:dom
import { stored, store, unstore, storedKeys, clearStored } from slate:dom

heard(path) = print("navigated " + path)

onNavigate(heard)

// -- where the page is ---------------------------------------------------------------------------

val here = location()

print("protocol " + here.protocol)
print("host " + here.host)
print("hostname " + here.hostname)
print("path " + here.path)
print("query " + here.query)
print("hash " + here.hash)

// -- moving without a reload ---------------------------------------------------------------------

pushPath("/one?a=1#top")

val one = location()

print("pushed " + one.path + one.query + one.hash)

replacePath("/two")

print("replaced " + location().path)

// **A push does NOT raise `onNavigate`**, and the absence of a `navigated` line above this one is
// what says so. A browser raises `popstate` for a movement the user made and never for one the
// program made itself; the driver presses back afterwards, and that line has to appear then.

// -- what the page remembers ---------------------------------------------------------------------

print("store " + toJSON(store("k", "v")))
print("stored " + toJSON(stored("k")))
print("missing " + toJSON(stored("nope")))

// A value that is not a string is written as slate prints it, the store holding nothing else.
store("n", 42)

print("number " + toJSON(stored("n")))
print("keys " + toJSON(sorted(storedKeys().value)))
print("unstore " + toJSON(unstore("k")) + " then " + toJSON(stored("k")))
print("clear " + toJSON(clearStored()) + " then " + toJSON(storedKeys()))

// -- a handler is given as many arguments as it declares -------------------------------------------

// **`on` supplies an event record, and a handler that does not read it need not name it** -- which
// is the shape every UI framework's user writes, `onClick={() -> count(n + 1)}`. The driver clicks
// both of these; the assertion is that each ran and that the one asking for the event got it.
val app = byId("app")
val quiet = createElement("button")
val curious = createElement("button")

setAttribute(quiet, "id", "quiet")
setAttribute(curious, "id", "curious")

// -- which modifiers were down, and which button ---------------------------------------------------

// **A LINK CANNOT BE WRITTEN WITHOUT THESE.** A framework intercepting a click has to let a
// cmd-click, a ctrl-click, a shift-click and a middle click through to the browser, or it swallows
// the most ordinary thing anybody does to a link. The driver sends a plain left click and then a
// cmd-click on the middle button, and the two lines are what says the record carries the difference.
val marked = createElement("button")

setAttribute(marked, "id", "marked")
setChildren(app, [quiet, curious, marked])

sawClick(e)
    print("click button " + toJSON(e.button) + " mods " + toJSON(e.mods))

on(quiet, "click", () -> print("clicked, reading nothing"))
on(curious, "click", (e) -> print("clicked, and the event says " + e.type))
on(marked, "click", sawClick)

// -- reading a page that is already there ----------------------------------------------------------

// **The read side, against a document somebody else built.** These four are what hydration walks a
// server's markup with, and a fake document written beside them would agree with them by
// construction -- which is the whole reason this file is run under jsdom.
val shelf = createElement("ul")
val first = createElement("li")
val gap = createText(" ")
val second = createElement("li")

setAttribute(first, "class", "one")
setAttribute(first, "hidden", true)
setChildren(first, [createText("apple")])
setChildren(second, [createText("pear")])
setChildren(shelf, [first, gap, second])
setChildren(app, [quiet, curious, marked, shelf])

val kids = children(shelf)

print("kids " + string(len(kids)))
print("tags " + toJSON([tagName(kids[0]), tagName(kids[1]), tagName(kids[2])]))
print("texts " + toJSON([nodeText(kids[0]), nodeText(kids[1]), nodeText(kids[2])]))
print("class " + toJSON(attribute(kids[0], "class")))
print("bare " + toJSON(attribute(kids[0], "hidden")))
print("absent " + toJSON(attribute(kids[0], "title")))
print("whole " + nodeText(shelf))

// -- watching the page change ----------------------------------------------------------------------

// **A framework's own tests reached jsdom's `MutationObserver` directly until this existed**, which
// is somebody else's API leaking into code written against this one. The records carry no nodes on
// purpose -- see the runtime -- so what is checked is the kind, the attribute's name and the counts.
val watched = createElement("div")

setAttribute(watched, "id", "watched")
insertBefore(app, watched, null)

// **The callback disconnects itself**, which is what makes the driver's later mutation a check of
// `disconnect` rather than a second helping of the same records. Disconnecting where the observer
// was made would have been earlier than the first delivery -- a browser queues the records as a
// microtask -- and would have thrown them away with nothing to say it had.
heardChanges(records)
    print("changed " + toJSON(records))

    watcher.disconnect()

val watcher = observe(watched, { children: true, attributes: true }, heardChanges)

setAttribute(watched, "data-state", "on")
setChildren(watched, [createText("one"), createText("two")])

// -- sending an event ------------------------------------------------------------------------------

// **What `dispatch` may send is what `on` may read**, which is the whole of why the shape is the
// event record's four fields and not the DOM's constructors.
val poked = createElement("button")

setAttribute(poked, "id", "poked")
insertBefore(app, poked, null)

on(poked, "click", (e) -> print("poked " + toJSON(e.button) + " " + toJSON(e.mods)))
on(poked, "keydown", (e) -> print("typed " + toJSON(e.key)))

print("plain " + toJSON(dispatch(poked, "click")))
print("modified " + toJSON(dispatch(poked, { type: "click", button: 1, mods: { meta: true, shift: true } })))
print("keyed " + toJSON(dispatch(poked, { type: "keydown", key: "Enter" })))

// A handler that prevents the default makes `dispatch` answer false, which is what the DOM's own
// `dispatchEvent` answers and is the only thing a sender can learn.
val vetoed = createElement("button")

setAttribute(vetoed, "id", "vetoed")
insertBefore(app, vetoed, null)

on(vetoed, "click", (e) -> e.prevent())

print("prevented " + toJSON(dispatch(vetoed, "click")))

// -- reading a stream of events from a server --------------------------------------------------------

// **The reading end of `slate:http`'s `sse`, which slate could write and could not consume.** jsdom
// has no `EventSource`, so the driver supplies the smallest one that can be wrong -- which proves
// the SHAPING and nothing about a browser's own: what the record's fields are called, that a
// message reaches the handler, and that `close` reaches the source. What a real browser does is
// still checked by the refusal below, which is what jsdom says without the stub.
val feed = events("http://example.test/e", {
    onMessage: (m) -> print("message " + toJSON(m)),
    onError: (e) -> print("error " + toJSON(e)) })

print("closed " + toJSON(feed.close()))

// A `lastEventId` is refused rather than ignored: a browser sends the last id it saw itself and
// gives a page no way to set one on the first request.
print("resume " + (events("http://example.test/e", { lastEventId: "7" }) catch e -> e.message))

// An observer that watches nothing is refused here rather than by a browser's own `TypeError`.
print("nothing " + (observe(watched, {}, heardChanges) catch e -> e.message))

print("ready")
