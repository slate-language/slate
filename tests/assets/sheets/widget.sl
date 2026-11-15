// A module that brings in two stylesheets of its own, the second of which its importer asks for
// again after it -- so the importer's second ask adds nothing and `a.css` keeps this position.
import "./b.css"
import "./a.css"

export val name = "widget"
