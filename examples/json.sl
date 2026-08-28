// JSON, whose two directions use slate's two failure channels.
//
// Text that will not parse is a result: it arrived from a file, a socket or a person, and every
// caller was always going to handle it. A value with no JSON form is a fault: a function or a circle
// is a defect in the program that built it. `JSON.parse` and `JSON.stringify` both throw, so node
// treats the two alike.

val document = "{\"name\": \"Ada\", \"born\": 1815, \"fields\": [\"maths\", \"computing\"], \"peer\": null}"
val read = parseJSON(document)

if read.ok
    val person = read.value

    print(person.name, "was born in", person.born)
    print("fields:", person.fields.join(", "))
    print("peer:", person.peer ?? "none recorded")
else
    print("could not read it:", read.error)

// Out again, compactly for a wire and laid out for a person.
val record = { id: 7, tags: ["a", "b"], nested: { ok: true } }

print(toJSON(record))
print(toJSON(record, 2))

// A document that will not parse answers rather than raising, and the error is the whole rendering:
// a JSON document is usually machine-written and long, so "expected a string" on its own says
// nothing a person can act on.
val broken = parseJSON("{oops}")

print("ok:", broken.ok)
print(broken.error)

// Both kinds of number survive the round trip, which is why `sh.sysl.json` has two: a real cannot
// hold an identifier past 2^53 and a long cannot hold 0.5.
print(toJSON(parseJSON("[9007199254740993, 0.5]").value))
