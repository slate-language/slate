// A user interface in a browser window, driven from slate.
//
// **This is the Electron shape without Chromium in the binary.** The view is HTML and CSS, the logic
// is here, and the two talk over a WebSocket this program serves. What Electron adds beyond that is
// a copy of Chromium inside the executable -- worth having when you must ship one file, and not
// worth having while you are finding out whether the thing is any good.
//
// Run it, then open the URL it prints. For a window with no address bar and no tabs, which is what
// makes it look like an application rather than a page, start the browser with `--app=` instead:
//
//     open -na "Google Chrome" --args --app=http://127.0.0.1:8410
//
// **Nothing here is browser-specific.** Safari and Firefox show the same page; only the `--app=`
// flag is Chrome's.

import { serve, close } from slate:http
import { accept } from slate:ws

val Port = 8410

// The page, and the whole of the JavaScript it needs. **Four lines of it are the bridge** -- open a
// socket, send on a click, apply what arrives -- and everything else is presentation.
//
// **Written as lines and joined**, because a string literal here is one line.
val Page = join([
    "<!doctype html>",
    "<html>",
    "<head>",
    "<meta charset=\"utf-8\">",
    "<title>slate</title>",
    "<style>",
    "  body { font: 16px system-ui, sans-serif; margin: 0; display: grid; place-items: center;",
    "         height: 100vh; background: #0f1115; color: #e8eaed; }",
    "  main { text-align: center; }",
    "  #count { font-size: 88px; font-weight: 600; font-variant-numeric: tabular-nums; margin: 0 0 8px; }",
    "  #said { color: #9aa0a6; min-height: 24px; margin: 0 0 24px; }",
    "  button { font: inherit; padding: 10px 22px; margin: 0 4px; border: 0; border-radius: 8px;",
    "           background: #2d63e2; color: white; cursor: pointer; }",
    "  button:hover { background: #3d73f2; }",
    "</style>",
    "</head>",
    "<body>",
    "<main>",
    "  <p id=\"count\">0</p>",
    "  <p id=\"said\">connecting...</p>",
    "  <button onclick=\"tell('up')\">up</button>",
    "  <button onclick=\"tell('down')\">down</button>",
    "  <button onclick=\"tell('reset')\">reset</button>",
    "</main>",
    "<script>",
    "  const ws = new WebSocket('ws://' + location.host + '/socket')",
    "  const tell = (what) => ws.send(what)",
    "",
    "  ws.onmessage = (e) => {",
    "      const m = JSON.parse(e.data)",
    "",
    "      document.getElementById('count').textContent = m.count",
    "      document.getElementById('said').textContent = m.said",
    "  }",
    "",
    "  ws.onclose = () => document.getElementById('said').textContent = 'the program has stopped'",
    "</script>",
    "</body>",
    "</html>",
    ""
], "\n")

// The state the page is a view of. **It lives here rather than in the browser**, which is the whole
// point of the arrangement: a reload shows the same number, and a second window shows it too.
var count = 0

// Everyone currently looking at it.
var watching = []

// Tell every open window what the state is now.
show(said)
    val message = toJSON({ count: count, said: said })

    for ws in watching
        ws.send(message)

val server = serve(Port, req -> ({ headers: { "Content-Type": "text/html; charset=utf-8" }, body: Page }),
    (req, socket, head) ->
        val opened = accept(req, socket, head)

        if !opened.ok
            print("a handshake was refused:", opened.error)
            return

        val ws = opened.value

        push(watching, ws)

        ws.onMessage(m ->
            if m == "up" then count = count + 1
            else if m == "down" then count = count - 1
            else if m == "reset" then count = 0

            show("you pressed " + m))

        ws.onClose((code, why) ->
            var left = []

            for w in watching
                if w != ws then push(left, w)

            watching = left

            print("a window closed:", code))

        show("connected"))

print("open http://127.0.0.1:" + string(Port))
print("or, for a window with no browser around it:")
print("  open -na \"Google Chrome\" --args --app=http://127.0.0.1:" + string(Port))
