// Types named for slate's own kinds, for `p46.sl` to import -- and the control: this file declares
// no `Set`, so here the word still names the kind, whatever the file importing it declares.

export class Map
    var size

export class Ledger
    var rows

export aBuiltinSet() = Set([1, 2])

export isTheSetKind(v) = v is Set
