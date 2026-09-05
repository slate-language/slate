# `slate:dom`'s page doors, against a real DOM

**This directory is NOT under `tests/`, and that is deliberate.** `sysl test .` runs the suite in this
process, where there is no document — and `page.sl` calls `location`, which faults there. Putting it
where the suite could reach it would fail the run with the very refusal that proves `slate:dom` is
working.

    npm install jsdom
    slate js check/page.sl -o check/page.js
    node check/drive.mjs check/page.js

It prints `ok` and nothing else when the runtime is right, and names what it wanted otherwise.

**jsdom rather than a document written beside the code it checks.** A shim agrees with that code by
construction: every mistake `js_rt_dom.sysl` could make about what `pushState`, `replaceState`,
`popstate` or `localStorage` do, the shim would make too, and the run would pass. jsdom is somebody
else's reading of the same specification and is free to disagree.

`slate-language/lath` keeps `check/` for the same reason and checks the *element* half of `slate:dom`
there; this is the half lath's driver does not touch.

## What it asserts, and why each one is here rather than in the suite

| | |
|---|---|
| every field of `location()` | nothing else runs these at all, and a record built wrong is silent |
| `query` and `hash` carry their punctuation | a router concatenating them is the reason they do |
| a push moves the address bar | |
| **a push does NOT raise `onNavigate`** | the browser's rule, and a router that assumed otherwise renders twice |
| back lands where a *replaced* entry says it should | a `replace` that quietly pushed would land one entry short, and nothing else would show it |
| a store round-trips, and a missing key is `null` rather than a failure | |
| a number is stored as slate prints it | a store holds strings and nothing else |
| `storedKeys` and `clearStored` | |

## Why the origin in the driver is a real one

`localStorage` is per origin and an opaque origin has none — a page loaded from a file gets a
`SecurityError` on the first access. That is exactly the condition the module answers as a **result**
rather than as a fault, so the driver uses `https://example.test/...` to check the ordinary path; the
refusing path is the one a browser's private mode produces and is not reachable here.

## What is NOT checked here, and cannot be

A real browser. jsdom is a faithful DOM and not a browser: it has no address bar, no session history
UI and no user. Nothing here says that pressing the browser's own back button reaches `onNavigate` —
only that the `popstate` it raises does.
