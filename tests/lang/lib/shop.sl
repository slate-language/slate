// A module with a constant, a table of its own, a module it imports in turn, and an actor
// declaration -- everything the actor suite asks about a module reached from a handler.
//
// **The table is the point of it.** Every VM that loads this module builds its own, so what the main
// program put in `stock` is not what an actor spawned afterwards can see.

import { tagged } from "./tag.sl"

export val Limit = 512

val stock = Map()

export addStock(name, n) = stock.set(name, n)

export stockCount() = stock.size

export label(n) = tagged(n)

export actor Keeper
    on limit(self) = Limit

    on count(self) = stockCount()

    on add(self, name, n)
        addStock(name, n)

        stockCount()
