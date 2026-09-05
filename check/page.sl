// The three doors a browser has and nothing else does, driven against a real DOM.
//
// **This is not under `tests/` and it cannot be.** Every name it imports faults under the
// interpreter -- that refusal is what says `slate:dom` is working -- so a suite that walked this
// file would fail on the very thing it is checking. `check/README.md` says how to run it, and
// `slate-language/lath` keeps its own DOM check the same way and for the same reason.

import { location, pushPath, replacePath, back, onNavigate } from slate:dom
import { byId, createElement, setAttribute, setChildren, on } from slate:dom
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

print("ready")
