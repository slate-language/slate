// **A package's own asset, imported by a relative path from inside the package.** That is what a
// component library shipping a `.css` beside its `.slx` does, and it needs nothing of the package
// system: the file travels with the package, and what a consumer imports is the string.
import panel from "./panel.css"

export more() = "more"

export also() = "a second export, so the did-you-mean has a list to draw from"

export style() = panel
