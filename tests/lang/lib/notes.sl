// Bases for `inherit.sl`, reached across a file so a subclass is built through a class it cannot see
// the fields of.

export class Notes
    var served = 0

    show(self, req) = 2

    bump(self)
        self.served += 1

export class Keeper
    var log = []

    new(var n)
        self.log.push(s"kept ${n}")
