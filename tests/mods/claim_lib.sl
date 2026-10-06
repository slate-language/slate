// The exporting half of `tests_claims.sysl`: each says in its result annotation what a call to it
// proves, over a body of more than one statement that no inference would read as a test.
export type Box = { size: integer }

export isBox(v: any) -> v is Box =
    if !(v is object) then return false
    val size = v.size
    size is integer

export ensureBox(v: any) -> asserts v is Box =
    if !isBox(v) then throw "not a box"
