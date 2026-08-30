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

## What is here

| | |
|---|---|
| `createElement`, `Fragment` | what slx desugars into |
| `useState`, `useReducer`, `useRef`, `useMemo`, `useCallback`, `useEffect` | hooks |
| `mount(element, host)` | render, and keep the tree so it can render again |
| `flush(root)` | render every change since the last one, now |
| `html(root)` | the tree as markup — the string host's answer |
| `stringHost()` | the default host |

## The host is behind an adapter, and that is the point

Nothing in the reconciler knows what a node is. `stringHost` builds plain objects and serialises
them; a DOM host will create real elements through the same six functions — `element`, `text`,
`setProps`, `setKids`, `setText`, `serialise`. **So one set of components renders to HTML on a server
and to the document in a browser**, which is the thing that makes this worth writing in slate rather
than reaching for React.

The DOM host is waiting on the JavaScript back end growing a way to reach the DOM. Nothing else here
is.

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

`useContext`, `memo`, error boundaries, portals, and a DOM host. The reconciler replaces a host node's
whole child list rather than moving children, which is right for a string and wants a real diff once
there is a DOM under it.

## This is going to be a package

It lives in the repo while its shape is still moving, imported by path. When it settles it becomes
`slate-language/react`, reached with `slate add` — which is why nothing outside `packages/react/`
knows it exists except the one sysl test that runs its tests.
