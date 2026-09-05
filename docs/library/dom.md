# `slate:dom`

The document. **The one module that works in one host out of three** — it is real only in a browser,
reached through [`slate js`](../reference/javascript.md).

```slate
import { byId, setText, on } from slate:dom
```

| | |
|---|---|
| `createElement(tag)`, `createText(s)` | |
| `setAttribute`, `removeAttribute`, `setProperty` | |
| `on(node, event, fn)`, `off(node, id)` | |
| `setChildren(node, kids)`, `setText(node, s)` | |
| `byId(id)`, `query(selector)` | |
| `markup(node)` | |
| `release(node)` | give a handle back |
| `location()` | where the page is, as a record |
| `pushPath(url)`, `replacePath(url)` | move the address bar without a reload |
| `back()`, `forward()` | move through what the page has visited |
| `onNavigate(fn)` | the user moved — **not** a push the program made |
| `stored(key)`, `store(key, v)` | `localStorage`, as results |
| `unstore(key)`, `storedKeys()`, `clearStored()` | |

**`on` and `off` rather than `addEventListener`**, and `byId` rather than `getElementById`. The DOM's names
are long because JavaScript had no modules when they were chosen; these are reached through an import that
already says `dom`.

## A node is a slate integer

**That is the decision everything else follows from.** The engine keeps the elements in a table and hands
out the index, so **no foreign object ever becomes a slate value**: `==` compares what slate says it
compares, `print` has something to say, a node travels through an array or a pattern like any other value,
and the checker learns nothing new. It is the arrangement the timers already use.

The cost is that **a handle is held until `release` gives it back**.

## An event arrives as a slate object

`{ type, value, checked, key, stop, prevent }`, built when the handler fires. A `MouseEvent` has no
representation in slate, and inventing one would mean inventing a value that could not be printed, compared
or stored.

**`value` and `checked` are set as properties and not attributes**, and an input is where the difference
shows: the attribute says what the field started as and the property says what it holds now, so a re-render
that set the attribute would leave a typed-in field alone and the page would appear frozen.

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
