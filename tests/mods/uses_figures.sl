// A variant is imported under an ALIAS on purpose. A pattern carries the name it was DECLARED under,
// and one still asking for `Circle` where the import bound it as `Round` would look up a name that is
// not there -- and, patterns having nowhere to report from, would match nothing and say nothing.
// Without the alias this fixture would pass with that bug in.
import { Figure, Circle as Round, Rect, Empty } from "./figures.sl"

name(s) = s match
    Round(r) -> "circle"
    Rect(_, _) -> "rect"
    Empty -> "empty"

print(Round(4).area(), Rect(3, 5).area(), Empty.area())
print(Round(1) is Figure, Empty is Empty, Round(1) is Rect)
print(name(Round(1)), name(Rect(1, 2)), name(Empty))
