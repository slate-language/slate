# `slate:dom`

The document. **The one module that works in one host out of three** — it is real only in a browser,
reached through [`slate js`](../reference/javascript.md).

```slate
import { byId, setText, on } from slate:dom
```

| | |
|---|---|
| `createElement(tag)`, `createText(s)`, `createComment(s)` | |
| `setAttribute`, `removeAttribute`, `setProperty` | |
| `on(node, event, fn)`, `off(node, id)` | |
| `setChildren(node, kids)`, `setText(node, s)` | |
| `insertBefore(parent, node, before)` | one child, in front of another; `null` appends |
| `removeChild(parent, node)` | one child, out |
| `byId(id)`, `query(selector)` | |
| `children(node)` | the child nodes, as handles, in order |
| `tagName(node)` | the tag in lower case, or `null` for a text node |
| `nodeText(node)` | what the node says, as text |
| `attribute(node, name)` | one attribute, or `null` where there is none |
| `nodeKind(node)` | `"element"`, `"text"`, `"comment"`, `"fragment"`, `"document"` or `"other"` |
| `property(node, name)` | what the node HOLDS, or `null` |
| `splitText(node, at)` | cut a text node in two; answers the tail |
| `markup(node)` | |
| `release(node)` | give a handle back |
| `dispatch(node, event)` | send an event; answers whether nothing cancelled it |
| `observe(node, options, fn)` | be told what changed; answers `{ disconnect }` |
| `events(url, options)` | read a server's event stream; answers `{ close }` |
| `location()` | where the page is, as a record |
| `pushPath(url)`, `replacePath(url)` | move the address bar without a reload |
| `back()`, `forward()` | move through what the page has visited |
| `onNavigate(fn)` | the user moved — **not** a push the program made |
| `stored(key)`, `store(key, v)` | `localStorage`, as results |
| `unstore(key)`, `storedKeys()`, `clearStored()` | |

**`on` and `off` rather than `addEventListener`**, and `byId` rather than `getElementById`. The DOM's names
are long because JavaScript had no modules when they were chosen; these are reached through an import that
already says `dom`.

## Reading a page somebody else rendered

**`children`, `tagName`, `nodeText` and `attribute` are what hydration walks with**, and three more
are what it walks with once the markup came from a server rather than from the same program.

**`nodeKind(node)` tells a comment from a text node**, which `tagName` calls `null` alike — so a
reconciler counting children read a comment as a piece of text and adopted the wrong node from there
on. It is asked outright rather than by widening what `tagName` answers: a program reading `null` as
*not an element* is right and stays right.

**`property(node, name)` is what the node HOLDS, where `attribute` is what its markup said.** They are
the pair a form turns on: setting the `value` attribute says what a field started as and setting the
property says what is in it now, so a re-render comparing what it would set against what is there has
to read the property. Only a value slate can hold comes back — a string, a boolean or a number — and
anything else answers `null`, exactly as a name the node does not carry does.

```slate
setAttribute(field, "value", "written")
setProperty(field, "value", "typed")

print(attribute(field, "value"), property(field, "value"))
```

**`splitText(node, at)` cuts one text node in two and answers a handle for the tail.** A component
rendering `{a}{b}` writes two text nodes and a server's markup carries the one string they made, so a
hydrating reconciler that cannot split has to throw the text away and rebuild it. **The offset is in
characters**, which is slate's rule wherever a string is measured and is not the DOM's — `splitText`
counts UTF-16 units there, so a cut written after an emoji would land inside one.

`createComment(s)` is the other half of `nodeKind`: a comment is what a server writes to mark a place
a component's output begins, and a page could read one and not write one.

## Sending an event, and watching for a change

**`dispatch(node, event)` sends what `on` reads**, which is the whole of why its shape is the event
record's fields and not the DOM's constructors: `type`, and optionally `key`, `button`, `mods`,
`bubbles` and `cancelable`. A string is the ordinary spelling.

```slate
dispatch(button, "click")
dispatch(button, { type: "click", button: 1, mods: { meta: true } })
dispatch(field, { type: "keydown", key: "Enter" })
```

It answers `true` where nothing cancelled the event, which is what the DOM's own `dispatchEvent`
answers and is all a sender can learn. **The event's class is chosen from its name** — a `click` is
a `MouseEvent` and a `keydown` a `KeyboardEvent` — because a handler reading `e.button` off a plain
`Event` gets `null`, and a router telling a left click from a middle one would let every dispatched
click through to the browser.

**`observe(node, options, fn)` is a `MutationObserver`**, and it answers an object whose
`disconnect` is the one thing that stops it. The options are `children`, `attributes`, `text` and
`subtree`, and at least one of the first three has to be asked for.

```slate
val watcher = observe(list, { children: true, subtree: true }, (records) -> redraw(records))

watcher.disconnect()
```

**A record carries no nodes**, which is the decision an event record already makes: a handle is a
table slot the program has to give back, and a re-render makes hundreds of records. What a record
says is `type` (`"children"`, `"attributes"` or `"text"`), `attribute` (the name, or `null`), and
`added` and `removed` as counts. A program that needs the nodes asks the page with `children` or
`query`.

## Reading a server's event stream

**`events(url, options)` is the reading end of [`slate:http`](http.md)'s `sse`**, which slate could
write and had no way at all to consume. It answers an object whose `close` ends the subscription.

```slate
val feed = events("/updates", {
    onMessage: (m) -> apply(m.data),
    onError: (e) -> if e.closed then warn("the stream is over") })

feed.close()
```

A message is `{ data, lastEventId, type }`. An error record says only `closed`: an `EventSource`
reconnects by itself, so nearly every error a page sees is a retry in progress, and a program that
stopped on those would stop on a hiccup.

**A `lastEventId` is refused rather than ignored.** A browser's `EventSource` sends the last id it
saw on its own reconnections and gives a page no way to set one on the first request — so taking the
option and dropping it would be a program that believed it had resumed and had not. What a program
resuming after a reload does instead is keep the `lastEventId` it read off each message and ask the
server for what it missed.

## A node is a slate integer

**That is the decision everything else follows from.** The engine keeps the elements in a table and hands
out the index, so **no foreign object ever becomes a slate value**: `==` compares what slate says it
compares, `print` has something to say, a node travels through an array or a pattern like any other value,
and the checker learns nothing new. It is the arrangement the timers already use.

The cost is that **a handle is held until `release` gives it back**.

## An event arrives as a slate object

`{ type, value, checked, key, mods, button, stop, prevent }`, built when the handler fires. A `MouseEvent`
has no representation in slate, and inventing one would mean inventing a value that could not be printed,
compared or stored.

**`mods` is `{ meta, ctrl, shift, alt }` and `button` is an integer or `null`** — `0` for the left button,
`1` for the middle, `2` for the right, and `null` for every event that is not a mouse event. They are here
because **a link cannot be written without them**: a framework that intercepts a click has to let a
cmd-click, a ctrl-click, a shift-click and a middle click through to the browser, or it swallows the most
ordinary thing anybody does to a link.

**`value` and `checked` are set as properties and not attributes**, and an input is where the difference
shows: the attribute says what the field started as and the property says what it holds now, so a re-render
that set the attribute would leave a typed-in field alone and the page would appear frozen.

## Reading a page that is already there

**Four of the names above read rather than write, and they exist because hydration needs exactly
them.** Everything else either makes a node or changes one; a program adopting markup a server
rendered has to walk what is there and ask what it found.

```slate
import { byId, children, tagName, nodeText, attribute } from slate:dom

val app = byId("app")

for kid in children(app)
    if tagName(kid) == null
        print("text: " + nodeText(kid))
    else
        print("<" + tagName(kid) + "> class=" + string(attribute(kid, "class")))
```

- **`children` answers EVERY child node and not only the elements**, because a text node between two
  elements is a position: a reconciler counting children has to count what the browser counts, or it
  adopts the wrong node. `tagName` answering `null` is how the two are told apart.
- **`tagName` is lower case**, because that is what a program wrote — the DOM answers `DIV` for HTML.
- **`attribute` answers `true` for a bare attribute**, which is the reading `setAttribute` writes: it
  puts the empty string for `true`, so a program comparing what it would set against what is there
  gets the same value back.
- **A handle from `children` is released like any other, and `release` gives back the HANDLE and not
  the node.** The element stays exactly where it is in the page. That reads oddly the first time and
  is the rule handles have always followed: `byId` and `query` have minted one for an element the
  program never created since this module shipped.

**`parent`, the siblings and an `innerHTML` reader are deliberately absent.** A page is walked
downwards from something the program already holds; the rest is a general traversal API, which is a
different thing to want and a much larger one.

## Where the page is, where it has been, and what it remembers

**A browser has `location`, `history` and `localStorage`, and nothing else does** — there is no address
bar in an interpreter and no per-origin store on a server. So these refuse everywhere else, naming
*which* of the three is missing rather than saying something about the document. That is the same rule
`slate:time`'s `abbrev` follows, read from the other side.

```slate
import { location, pushPath, onNavigate, stored, store } from slate:dom

val here = location()          // { href, protocol, host, hostname, port, path, query, hash }

show(path) = render(path)

onNavigate(show)               // the user pressed back, or forward

pushPath("/notes/7")           // the address bar moves; onNavigate does NOT fire
show("/notes/7")               // so a router renders after its own push

store("theme", "dark")
print(stored("theme").value)   // "dark", or null when nothing is stored
```

**`query` and `hash` carry their punctuation** — `"?a=1"` and `"#top"` — which is what a program pasting
one back into a url needs. An empty one is `""` and never null.

**A push does not raise `onNavigate`.** A browser raises it for a movement the *user* made and never for
one the program made itself, so a router renders after its own push and waits to be told about everything
else. Getting this wrong is how a router renders twice.

**There is no state object, and that is a measurement.** `pushState` structured-clones what it is given
and `structuredClone` strips the prototype, so a slate object put in comes back a plain object nothing in
the language could read. The url is the whole of the state — which is also what keeps a router's two
sources of truth from disagreeing after a `back`.

**The store answers results**, which is [`readFileSync`](fs.md)'s channel and its reason: what comes back
was written by somebody else — another tab, an earlier visit, a user who cleared it. A key that is not
there is `{ ok: true, value: null }` and not a failure; a browser told to keep no data is
`{ ok: false, error }`. A value that is not a string is stored as slate prints it, a store holding nothing
else.

## Under the interpreter

**Every name faults, and the module still exists.** Leaving it out would make `import { byId } from
slate:dom` a complaint about the *module*, which sends a reader looking for a spelling mistake in the one
line that is right. The refusal instead names the **command**, because the command is the mistake — the
same program is correct in a browser.

## The framework

`slate:dom` is the seam, not the framework. `lath` is React's model *and* React's mechanism, written in
slate over [elements](../reference/elements.md), with this module as one of its two hosts — the other
rendering to markup beside [`slate:http`](http.md), so server-side rendering is a by-product rather than a
project.

```
$ slate add github.com/slate-language/lath
```

**It is a package rather than part of the language, and deliberately so**: a UI framework iterates far
faster than a compiler, and baking one in would tie every framework fix to a language release.

## Moving one child

**`setChildren` writes the whole list and the two beside it move one node.** Both spellings are here
because they cost different things: replacing a list is what makes a re-render idempotent, and it is
what a browser records a mutation for per child — a keyed reconciler moving three rows of a thousand
should not make the page do a thousand pieces of work.

```slate
insertBefore(list, row, list.children()[2])
insertBefore(list, row, null)
removeChild(list, row)
```

**`before` of `null` appends**, which is `Node.insertBefore`'s own rule and is what makes the last
position no more work than any other. **A node already in the page MOVES rather than being copied**,
so it keeps its focus, its scroll position and whatever it was playing. **The parent is named for the
removal too**, where a browser needs only the child: a reconciler holds both, and naming the parent
is what turns "that node is somewhere else entirely" from a silent success into a sentence.
