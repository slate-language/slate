// The exporting half of `tests_predicates.sysl`: each of these is one test of its parameter, so a
// call in another file narrows what it was handed as the test written there would.
export isPresent(m: object | null) -> boolean = m != null
export isText(v: string | integer) = v is string

// More than one statement, so not a predicate.
export isThere(m: object | null)
    val ok = m != null
    ok
