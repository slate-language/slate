// An importer whose own declaration is built out of a class another module declared.

import { Rect } from "./decl_shapes.sl"

print("the importer ran")

export areaOf() = Rect.new(3, 4).area()
