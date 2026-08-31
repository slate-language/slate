# A counter in a web page

The smallest thing that is a whole application: two counters with their own state, three buttons
each, and a page.

    slate js examples/web/counter.slx -o examples/web/counter.js

Then open `index.html`. There is no bundler and nothing to install — `slate js` writes one
self-contained file holding the runtime, the framework and the program, which is what a `<script>`
tag wants.

**The interesting line is the last one.** `mount(<App/>, domHost("#app"))` is the only place the page
appears; everything above it is components, and the same components render to markup beside
`slate:http` with no host given at all. That is what the adapter in `packages/react/` is for, and
this directory is the second implementation that makes the claim true rather than a hope.

**`counter.js` is not checked in.** A committed one would open without the build step above and be
wrong the first time anybody changed the framework under it, with nothing to say so.
