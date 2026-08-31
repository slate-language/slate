// The DOM host, driven against a real DOM.
//
// **jsdom rather than a shim written here**, and that is the whole reason this is worth running: a
// fake document written beside the code it checks agrees with that code by construction, and would
// have passed for every mistake the host could make. jsdom is somebody else's reading of the same
// specification, so it is free to disagree -- which is what makes a pass evidence.
//
//     npm install jsdom
//     slate js tests/js/dom/counter.slx -o tests/js/dom/counter.js
//     node tests/js/dom/drive.mjs tests/js/dom/counter.js
//
// It prints `ok` and nothing else when the host is right, and says what it wanted otherwise. It is
// not part of `sysl test .`: jsdom is not a dependency of this repo and adding one would put an
// `npm install` in front of the suite's one command. See `tests/js/README.md`.

import { JSDOM } from "jsdom"
import { readFileSync } from "node:fs"

const dom = new JSDOM(`<!doctype html><html><body><div id="app"></div></body></html>`,
    { runScripts: "outside-only" })

const w = dom.window
const doc = w.document

// The compiled program runs inside the page's global, which is what a `<script>` tag does.
w.eval(readFileSync(process.argv[2], "utf8"))

let failed = 0

const reading = (id) => {
    const el = doc.getElementById(id)

    return el === null ? "<gone>" : el.textContent
}

// **A render is scheduled on the microtask queue and not done on the spot**, which is React's
// batching and slate's: two changes in one handler are one render. So a click is followed by
// letting the queue run before anything is read.
const click = async (selector) => {
    const el = doc.querySelector(selector)

    if (el === null) throw new Error("nothing matches " + selector)

    el.dispatchEvent(new w.MouseEvent("click", { bubbles: true }))

    await new Promise((r) => setTimeout(r, 0))
}

const want = (what, got, wanted) => {
    if (got === wanted) return

    console.log("FAIL " + what + ": got " + JSON.stringify(got) + ", wanted " + JSON.stringify(wanted))
    failed += 1
}

const first = ".counter:nth-of-type(1)"
const second = ".counter:nth-of-type(2)"

// What mounting put on the page, attributes included -- `class` is slate's spelling and reaches the
// document as itself.
want("the tree is in the page",
    doc.querySelectorAll(".counter").length, 2)
want("an attribute is set", doc.getElementById("first").getAttribute("class"), "reading")
want("both counters start where they were told", reading("first") + " " + reading("second"), "0 100")

// **Three clicks with a render between each**, which is the case a handler that was not taken back
// would get wrong: a host that only ever added listeners would run every closure the component had
// ever had and the reading would climb by more than one.
await click(first + " .up")
await click(first + " .up")
await click(first + " .up")
want("three clicks are three", reading("first"), "3")

await click(first + " .down")
want("down takes one off", reading("first"), "2")

await click(first + " .reset")
want("reset goes back to where it started", reading("first"), "0")

// The other counter has its own state and its own step, and neither click above touched it.
await click(second + " .up")
want("the second counter is its own", reading("second"), "105")

// **Text reaches the page as TEXT.** A renderer that put what it was given straight into the markup
// would hand whoever supplied the string control of the page, and the DOM host does not build markup
// at all -- it makes text nodes -- so this is asserting that it stayed that way.
want("text is text and not markup",
    doc.getElementById("risky").innerHTML,
    "&lt;script&gt;alert(1)&lt;/script&gt; &amp; co")
want("and nothing was executed", doc.querySelectorAll("script").length, 0)

// A node that goes away. **The framework tells the host to drop it**, which is what gives the handle
// back; nothing on screen would show the difference, so it is asserted here or nowhere.
await click("#hide")
want("a node that is gone is gone", reading("maybe"), "<gone>")

// And the page is still live afterwards, which is what would break if dropping a node had taken a
// handle that was still in use.
await click(first + " .up")
want("the page still works after a node was dropped", reading("first"), "1")

if (failed === 0) console.log("ok")

process.exit(failed === 0 ? 0 : 1)
