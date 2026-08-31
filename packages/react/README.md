# `slate:react` — React in slate

A component is a function of its props, state lives in hooks kept on call-order slots, and a change
re-renders the component that owns it while the reconciler matches the new children against the old
by key. That is React's model **and** React's mechanism, which is what was asked for.

```
import { createElement, Fragment, mount, html, flush, useState } from "./packages/react/react.slx"

Counter(props) =
    val [count, setCount] = useState(0)

    <div class="counter">
        <h1>Count: {count}</h1>
        <button onClick={() -> setCount(count + 1)}>+1</button>
    </div>

val root = mount(<Counter/>)

print(html(root))
```

`createElement` and `Fragment` have to be imported wherever an element is written: slx desugars
`<div/>` into a call to them, and slate itself has no idea what an element means.

**A COMPONENT TAKES ITS PROPS, EVEN WHEN IT IGNORES THEM.** `Counter(props)` or
`Counter({ start = 0 })` — never `Counter()`. React allows the empty parameter list; slate checks
arity, and the framework calls every component with one argument. Writing `Counter()` gets

    error: this function takes 0 arguments and was given 1
       --> packages/react/react.slx:199:19

which names *this file* rather than the component, because the call is here. Read past the path: the
line that is wrong is the one in your own program.

## What is here

| | |
|---|---|
| `createElement`, `Fragment` | what slx desugars into |
| `useState`, `useReducer`, `useRef`, `useMemo`, `useCallback`, `useEffect` | hooks |
| `mount(element, host)` | render, and keep the tree so it can render again |
| `flush(root)` | render every change since the last one, now |
| `html(root)` | the tree as markup — the string host's answer |
| `stringHost()` | the default host |
| `domHost(selector)` | the other one, in `dom.slx` — a real page |

## The host is behind an adapter, and there are two of them

Nothing in the reconciler knows what a node is. `stringHost` builds plain objects and serialises
them; `domHost` creates real elements through the same functions — `element`, `text`, `setProps`,
`setKids`, `setText`, `serialise`, `drop` and `mounted`. **So one set of components renders to HTML
beside `slate:http` and into the document in a browser**, which is the thing that makes this worth
writing in slate rather than reaching for React.

```
import { createElement, Fragment, mount, useState } from "./packages/react/react.slx"
import { domHost } from "./packages/react/dom.slx"

mount(<Counter/>, domHost("#app"))
```

Then `slate js app.slx -o app.js` and a `<script src="app.js">` beside a `<div id="app">`. The
emitted file is self-contained — the runtime, the framework and the program in one — so there is no
bundler and nothing to install.

**`drop` and `mounted` are the two the string host does not need**, and they were added when the DOM
host was written rather than guessed at in advance:

- **`drop(node)`** is a node the framework has torn down. A string host's node is an ordinary object
  the collector takes; a DOM host hands out a handle into a table it keeps, and a node nobody tells
  it about is a slot held for the life of the page.
- **`mounted(nodes)`** is the top of the tree, handed over on **every** commit. A component at the
  very top has no host node above it, so when it renders a different set of nodes the reconciler has
  nobody to tell — for a string host that is invisible, `html` walking the tree afresh whenever it is
  asked, and for a DOM host it is an element left on the page after the program stopped rendering it.

`tests/host.slx` pins both against a recording host, which is how a contract with two
implementations gets checked without a document in the room.

## What a handler is given

**A record, not the event.** `MouseEvent` has no representation in slate and inventing one would mean
inventing a foreign value, so `slate:dom` builds an object at the moment the handler fires:

| | |
|---|---|
| `type` | `"click"`, `"input"`, … |
| `value` | what the target holds now, as a string, or `null` |
| `checked` | a checkbox's state, or `null` |
| `key` | for a keyboard event |
| `stop()`, `prevent()` | `stopPropagation` and `preventDefault` |

A counter reads none of it. A form reads `e.value`, which is a *property* and not the attribute — the
host sets it as one, which is what keeps a re-render from freezing a field somebody is typing in.

## Where it diverges from React, deliberately

- **Dependencies are compared with slate's `==`, which is structural.** `[1, 2] == [1, 2]` is true
  here and false in JavaScript, so an object rebuilt with the same fields is not a change. It is the
  host language's own answer and it removes the surprising direction — recomputing when nothing
  changed.
- **`class`, not `className`.** React's spelling exists because JSX compiles into a JavaScript object
  literal where `class` was reserved. Nothing here is.
- **Children arrive as one array**, not as trailing arguments: slate has no rest parameter, and an
  array is what `props.children` holds anyway.
- **An `undefined` child is refused by slate before the framework sees it** — an element's children
  travel as an array literal and slate refuses `undefined` in an array. `<p>{props.title ?? null}</p>`
  is what a program writes, and `null` renders nothing.

  **The better answer is to take the props apart with defaults**, which is what React code does
  anyway and what slate's patterns learned in order to make this pleasant:

  ```
  Card({ title = "Untitled", size = 1, children }) =
      <div class={"card s" + string(size)}><h2>{title}</h2>{children}</div>
  ```

  A default fires on **absence and nothing else** — a `title` of `0`, `false`, `""` or `null` is the
  value that was given, where JavaScript's `||` would have replaced all four.

## Not here yet

`useContext`, `memo`, error boundaries and portals. **The reconciler replaces a host node's whole
child list rather than moving children**, which was right when the only host was a string and is now
the obvious next thing: `replaceChildren` on a list of a thousand rows rebuilds the lot, where a real
diff would move a handful. It is correct and it is not fast.

## This is going to be a package

It lives in the repo while its shape is still moving, imported by path. When it settles it becomes
`slate-language/react`, reached with `slate add` — which is why nothing outside `packages/react/`
knows it exists except the one sysl test that runs its tests.
