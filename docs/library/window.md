---
title: "slate:window"
weight: 220
---

# `slate:window`

A desktop window with a web page in it, and a bridge between that page and the program — the
platform's own web view, so nothing is bundled and a window weighs what the system already loaded.

**This module is in the desktop edition of slate, and not in the standard one.** The desktop
edition is `brew install slate-language/tap/slate-desktop`; its binary is still called `slate`, so a
script and a `#!` line never care which edition runs them, and the two formulas are alternatives to
each other rather than companions. Building from source, the edition is the `webview` build feature
— the one feature that is _not_ on by default — so a desktop build is
`sysl build . --features webview`, and the library it needs is
`brew install sysl-lang/tap/webview`. A build without it says so when a program imports this module,
naming the edition and the feature rather than claiming slate has no such module:

```slate
import { window } from slate:window
```

```text
error: `slate:window` is not in this build -- it is the desktop edition's: install `slate-desktop`, or build with `--features webview`
```

## A window in fourteen lines

```slate
import { window, windowBind, windowEval, windowDone } from slate:window

val w = window({ title: "Notes", width: 720, height: 520, html: page })

windowBind(w, "save", (text) -> writeFileSync("notes.txt", text))
windowBind(w, "load", () -> readFileSync("notes.txt").value ?? "")

// An ordinary slate timer, writing into the page while the window is up.
setInterval(() -> windowEval(w, "clock.textContent = new Date().toLocaleTimeString()"), 1000)

await windowDone(w)

print("window closed")
```

**The blocks on this page are quoted rather than run**, except the refusal above. Every one of them
opens a window, and a window has to be looked at: `dev/slatelang/slate/tests_window.sysl` runs what
can be checked without one, and `examples/desktop/notes.sl` is the program to run by hand.

## Why it is here, and why it did not need a thread

**A program that already runs on libuv gains a window without changing how it runs.** slate is one
thread with an event loop on it; a platform's window system is also a loop, and the ordinary way to
have both is a second thread with a lock between them. This module has neither. The platform's loop
is turned over from a libuv timer — eight milliseconds at a time, about 120 Hz — so every callback a
page makes lands on slate's own thread by construction.

What that buys is that nothing about the rest of the program changes. A server keeps serving while a
window is up. A `for await` over a stream keeps stepping. A timer keeps firing and can write into
the page, which is what the `setInterval` above is doing. None of it is arranged; it is what falls
out of the window being a guest on the loop the program already had.

**The window keeps the program alive exactly as a listening socket does.** While one is open the
program does not exit; when the last one closes, the timer stops and the program ends on its own.

## A window is an integer

`window(...)` answers a number into a table inside slate, which is what every handle in slate is: a
socket, a timer, a store and a child process are all numbers. So `==` compares what slate says it
compares, `print` has something to say, and a number that names no window is refused by the table it
is looked up in.

```slate
import { windowTitle } from slate:window

windowTitle(4, "hello")
```

```error
`windowTitle` was given something that is not a window
```

## Making one

`window(options)` takes an object and every member of it is optional:

| option | what it is |
|---|---|
| `title` | what the title bar says |
| `width`, `height` | how big the window is, in points — 800 by 600 by default |
| `html` | the page, as markup the program holds |
| `url` | the page, as somewhere to load it from |
| `debug` | open the platform's web inspector with the window |

**`html` and `url` are alternatives and naming both is refused**, a window showing one page. First
wins and last wins would each throw away something somebody wrote, which is the rule a manifest's
repeated key already follows.

```slate
val w = window({ title: "Notes", width: 720, height: 520, url: "http://localhost:8080/" })
```

Everything else can be set afterwards, and a window is an ordinary thing to change while it is up:
`windowTitle(w, text)`, `windowSize(w, width, height)`, `windowNavigate(w, url)` and
`windowHtml(w, markup)`.

## Talking to the page

**`windowBind(w, name, fn)` makes `name` a function on the page's `window` object**, and it is
asynchronous there: the page writes `await save(text)` and gets a promise.

The page's arguments arrive as slate values — JSON on the wire, and the same reader `parseJSON`
uses — and what the handler answers goes back as the page's resolved value:

```slate
windowBind(w, "add", (a, b) -> a + b)
windowBind(w, "settings", () -> { theme: "dark", size: 14 })
```

```javascript
await add(2, 3)        // 5
await settings()       // { theme: "dark", size: 14 }
```

**A handler may be `async`, and that is the point of the design.** It is answered whenever it is
ready — a turn later, a file read later, a request later — and the page's promise stays pending until
then, which is what a page asking for something that takes time needs:

```slate
windowBind(w, "search", async (q) -> (await fetch("https://example.com/s?q=" + q)).value.body)
```

**A fault in a handler rejects the page's promise** and does not stop the program. A page asking for
something impossible is a bad request, and the program is a server to it:

```javascript
try { await save(42) } catch (e) { console.log(e) }   // the slate fault's own sentence
```

## Running JavaScript, and ending

`windowEval(w, js)` runs a script in the page and answers nothing: the page's own thread runs it, and
anything the program wants back comes through a bound function. That asymmetry is the platform's
rather than slate's.

`windowClose(w)` closes the window as the user closing it would; closing one that has already gone is
not a failure, which is what `close` on a socket does. `windowClosed(w)` answers whether it has gone,
and `windowDone(w)` answers a promise that settles when it does — the idiom `child.exited` already
uses, and what a program awaits instead of polling.

## It is the interpreter only

**Every name here refuses under `slate js`**, and that is a shape case rather than something owed. A
browser page is already inside a window and cannot make a native one — what it has is `window.open`,
a second tab a pop-up blocker governs, with no title bar to set and no way to bind a function into
itself. node has no window system in its standard library either: Electron, Tauri and node-gui are
separate runtimes rather than modules, so a program compiled by `slate js` would depend on something
the tool cannot see and did not install.

```javascript
`window` opens a native window, and no JavaScript host has one to open -- a browser page is already
inside a window and node has no window system, so this module runs in the interpreter only
```

## What is not here

**No component model, no router, and no way to write a page in slate rather than in HTML.** Each of
those is a design decision with several defensible answers, and this module is a door onto somebody
else's window system with no policy of its own — which is [`slate:lmdb`](lmdb.md)'s tier exactly.
What sits on top is a package's job, and [`lath`](https://github.com/slate-language/lath) is the one
already written.
