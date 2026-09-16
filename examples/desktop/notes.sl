// A notes app in a desktop window: a textarea, a Save button, and a clock the program writes into.
//
// RUN IT FROM AN ACCOUNT THAT OWNS THE CONSOLE:
//
//     sysl run . --features webview -- examples/desktop/notes.sl
//
// `slate:window` is behind the `webview` feature, which is the one feature that is not on by
// default -- see the README's "The desktop build".
//
// **It is in `examples/desktop/` rather than beside the others deliberately.** The suite runs every
// example at the top level of `examples/` and this one opens a window, which is a thing that has to
// be looked at rather than asserted about: on a machine with no window server it would not fail, it
// would never return.
//
// What it is here to show:
//
//   - a page calls into slate with `windowBind`, and `await save(...)` in the page is an ordinary
//     slate function on this side;
//   - slate writes into the page with `windowEval`, driven by an ORDINARY `setInterval` -- which is
//     the whole claim of the module: the window is a guest on the loop the program already had, so
//     everything else a slate program does keeps working while one is up;
//   - `await windowDone(w)` is how a program waits for the user to be finished.

import { window, windowBind, windowEval, windowClose, windowDone } from slate:window
import { readFileSync, writeFileSync } from slate:fs

val Notes = "notes.txt"

val page = [
    "<!doctype html>",
    "<html>",
    "  <head>",
    "    <meta charset='utf-8'>",
    "    <style>",
    "      :root { color-scheme: light dark }",
    "      body { font: 15px/1.5 -apple-system, system-ui, sans-serif; margin: 0;",
    "             height: 100vh; display: grid; grid-template-rows: auto 1fr auto }",
    "      header, footer { display: flex; gap: .75rem; align-items: center;",
    "                       padding: .6rem .9rem; opacity: .8 }",
    "      footer { justify-content: flex-end }",
    "      textarea { font: inherit; border: 0; outline: 0; padding: .9rem;",
    "                 resize: none; background: transparent; color: inherit }",
    "      button { font: inherit; padding: .3rem .9rem; border-radius: .4rem }",
    "      #clock { margin-left: auto; font-variant-numeric: tabular-nums }",
    "    </style>",
    "  </head>",
    "  <body>",
    "    <header><strong>Notes</strong><span id='clock'>--:--:--</span></header>",
    "    <textarea id='text' placeholder='type something'></textarea>",
    "    <footer>",
    "      <span id='said'></span>",
    "      <button onclick='store()'>Save</button>",
    "      <button onclick='quit()'>Quit</button>",
    "    </footer>",
    "    <script>",
    "      const text = document.getElementById('text')",
    "      const said = document.getElementById('said')",
    "",
    "      // `load`, `save` and `quit` are slate functions. Each one answers a promise here,",
    "      // whatever it does on the other side -- which is what lets a handler be `async`.",
    "      load().then((t) => { text.value = t; text.focus() })",
    "",
    "      async function store() {",
    "        said.textContent = await save(text.value)",
    "      }",
    "    </script>",
    "  </body>",
    "</html>"
].join("\n")

val w = window({ title: "Notes", width: 640, height: 480, html: page })

windowBind(w, "load", () -> readFileSync(Notes).value ?? "")

windowBind(w, "save", (text) ->
    writeFileSync(Notes, text)
    "saved ${len(text)} characters")

windowBind(w, "quit", () -> windowClose(w))

// **An ordinary slate timer writing into the page**, and it is the proof rather than the decoration:
// a counter that goes up on its own while a window is up is libuv still turning, which is the thing
// the whole design was chosen for.
val clock = setInterval(
    () -> windowEval(w, "document.getElementById('clock').textContent = new Date().toLocaleTimeString()"),
    1000)

// Top-level `await` is refused (see docs/reference/asynchrony.md), so the wait is an `async main`.
async main()
    await windowDone(w)
    clearInterval(clock)
    print("window closed; notes are in ${Notes}")

main()
