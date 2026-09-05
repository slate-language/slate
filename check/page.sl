// The three doors a browser has and nothing else does, driven against a real DOM.
//
// **This is not under `tests/` and it cannot be.** Every name it imports faults under the
// interpreter -- that refusal is what says `slate:dom` is working -- so a suite that walked this
// file would fail on the very thing it is checking. `check/README.md` says how to run it, and
// `slate-language/lath` keeps its own DOM check the same way and for the same reason.

import { location, pushPath, replacePath, back, onNavigate } from slate:dom
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

print("ready")
