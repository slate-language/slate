// A module the examples on `actor.md` import, so that the page can show what a module means to an
// actor: a constant every copy has, and a table each copy owns.

export val Limit = 512

val entries = Map()

export record(name, n) = entries.set(name, n)

export count() = entries.size
