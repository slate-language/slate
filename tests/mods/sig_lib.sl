// The exporting half of `tests_imported_signatures.sysl`: a call to any of these from another file
// is checked against the signature written here.
export pair(a: integer, b: integer) = a + b
export greet(name: string, punct = "!") = name + punct
export count(first, ...rest) = 1 + rest.length
export loose(x) = x
export val label = "lib"
export parsed(s: string) -> integer | null = if s == "" then null else 3

export refuse(text)
    throw "@" + text
