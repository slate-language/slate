// **A package's own stylesheet, brought in bare from inside the package.** A component library's
// module does this so that a program using the component carries its styles; the sheet is part of
// the program like every other file the package's modules read.
import "./panel.css"

export ready() = "kit/sheet"
