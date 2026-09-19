// A module the actor suite imports twice over -- directly, and again through `shop.sl` -- so that a
// VM can be ASKED how many times its own top level ran. A module is instantiated once per VM however
// many files import it, and counting it is what says so without measuring anything.

var loads = 0

loads += 1

export val Prefix = "tag-"

export timesLoaded() = loads

export tagged(n) = Prefix + string(n)
