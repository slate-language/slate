# The DOM host, against a real DOM

`packages/react/dom.slx` is the second implementation of the host adapter, and the argument for the
adapter is that one set of components renders in two places. **A contract only one implementation is
ever checked against is a contract with one implementation** — so this is where the other one is run.

    npm install jsdom
    slate js tests/js/dom/counter.slx -o tests/js/dom/counter.js
    node tests/js/dom/drive.mjs tests/js/dom/counter.js

It prints `ok` and nothing else when the host is right, and names what it wanted otherwise.

**jsdom rather than a fake document written here, and that is the point.** A shim written beside the
code it checks agrees with that code by construction: every mistake `dom.slx` or `js_rt_dom.sysl`
could make about what `setAttribute`, `replaceChildren` or `addEventListener` do, the shim would make
too, and the run would pass. jsdom is somebody else's reading of the same specification and is free
to disagree.

## What it asserts, and why each one is here rather than in `sysl test .`

| | |
|---|---|
| the tree reaches the page, with its attributes | nothing else runs `slate:dom` at all |
| three clicks are three | a host that only ever ADDED listeners would run every closure the component had ever had, and the reading would climb by more than one |
| the second counter is its own | state per instance, through a real event rather than a call to `flush` |
| text reaches the page as text | the DOM host builds text nodes and never markup, which is what makes a renderer safe by construction rather than by escaping — this says it stayed that way |
| a node that stops being rendered leaves the page | a component at the very top has no host node above it, so the reconciler has nobody to tell — `mounted` on every commit is what closes that, and the string host cannot show it |
| the page still works after a node was dropped | `release` giving back a handle that was still in use would be silent until something else took the slot |

**It is not part of `sysl test .`.** jsdom is not a dependency of this repo, and making it one puts an
`npm install` in front of the suite's one command — the same kind of decision as the `quickjs-ng`
question in `../README.md`, and the user's to make. Until then this is run by hand, and it has been.

## What is NOT checked here, and cannot be

A real browser. jsdom is a faithful DOM and not a rendering engine: it has no layout, no paint and no
compositor, so nothing here says the counter is *visible*. Open `examples/web/index.html` for that —
it is the same components, built the same way.
