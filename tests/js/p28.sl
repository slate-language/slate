// `slate:sqlite`, on both back ends.
//
// **The module above is one piece of slate source and the floor under it is two different
// libraries**, which is what makes a differential file worth having here: the interpreter links the
// machine's libsqlite3 through `sh.sysl.sqlite`, and a JavaScript host uses node's `node:sqlite`,
// which carries its own copy. Two libraries, one SQL and one set of sentences.
//
// **Everything opens `:memory:`**, so the corpus needs no scratch directory and leaves nothing
// behind. **Nothing prints a version and nothing prints a bm25 SCORE** — the two copies of SQLite are
// different builds, and a number either of them is free to change between releases is not a claim
// about slate.

import { sqlite } from slate:sqlite

val db = sqlite(":memory:")

db.exec("create table notes (id integer primary key, title text, weight real, body blob)")

// -- what a write says it did -------------------------------------------------------------------------

val first = db.run("insert into notes (title, weight) values (?, ?)", "first", 1.5)

print("changes", first.changes, "rowid", first.lastInsertRowid)
print("second rowid", db.run("insert into notes (title) values (?)", "second").lastInsertRowid)

// **0 is not an error**, an update that matched nothing being an ordinary thing to happen.
print("matched nothing", db.run("update notes set title = ? where id = ?", "x", 99).changes)
print("matched one", db.run("update notes set title = ? where id = ?", "kept", 2).changes)

// -- a row is an object keyed by column name -----------------------------------------------------------

for row in db.query("select id, title, weight from notes order by id")
    print("row", row.id, row.title, row.weight)

print("shape", toJSON(db.query("select id, title from notes where id = ?", 1)[0]))
print("no rows", toJSON(db.query("select id from notes where id = ?", 404)))

// -- the five storage classes ---------------------------------------------------------------------------

db.exec("create table anything (v)")

db.run("insert into anything values (?)", 42)
db.run("insert into anything values (?)", 2.5)
db.run("insert into anything values (?)", "words")
db.run("insert into anything values (?)", toBytes("hi"))
db.run("insert into anything values (?)", null)

// **The type belongs to the value and not to the column**, SQLite being dynamically typed — so one
// column answers five different kinds of slate value here and both back ends have to agree which.
for row in db.query("select v from anything")
    print("stored", row.v is integer, row.v is real, row.v is string, row.v is array, row.v == null)

print("bytes back", toJSON(db.query("select v from anything where typeof(v) = 'blob'")[0].v))

// **A boolean is 0 or 1**, SQLite having no boolean storage class.
print("a boolean", toJSON(db.query("select ? as t, ? as f", true, false)[0]))

// **A 64-bit integer survives**, which the 32-bit reader would have truncated.
print("big", db.query("select ? as n", 9007199254740993)[0].n)

// -- transactions --------------------------------------------------------------------------------------

both()
    db.run("insert into notes (title) values ('a')")
    db.run("insert into notes (title) values ('b')")

    "committed"

print("transaction", db.transaction(both))
print("after commit", db.query("select count(*) as n from notes")[0].n)

half()
    db.run("insert into notes (title) values ('c')")

    throw "halfway"

print("rolled back", db.transaction(half) catch e -> e.message)
print("after rollback", db.query("select count(*) as n from notes")[0].n)

// -- full-text search ------------------------------------------------------------------------------------

print("fts5", db.compiledWith("ENABLE_FTS5"), db.compiledWith("SQLITE_ENABLE_FTS5"))
print("no such option", db.compiledWith("AN_OPTION_NOBODY_HAS"))

db.exec("create virtual table search using fts5(body)")
db.run("insert into search (body) values (?)", "the quick brown fox")
db.run("insert into search (body) values (?)", "a lazy dog sleeping")

val hits = db.query("select body, bm25(search) as score from search where search match ? order by score", "fox")

// **The score itself is not printed** — it is a number two builds of SQLite may compute differently.
print("hits", len(hits), hits[0].body, hits[0].score is real, hits[0].score < 0)

// -- what it refuses -------------------------------------------------------------------------------------

// **Every one of these is a fault and every one is a sentence**, which is slate's rule read for a
// local database: the SQL is in the program, the parameter count is a property of that SQL, and a
// call on a closed database is a mistake in the order the program did things.
print(db.query("select nope from notes") catch e -> e.message)
print(db.exec("this is not sql") catch e -> e.message)
print(db.query("select ?, ?", 1) catch e -> e.message)
print(db.query("select ?", 1, 2) catch e -> e.message)
print(db.query("select ?", both) catch e -> e.message)
print(db.run("insert into notes (id, title) values (1, 'clash')") catch e -> e.message)
print(sqlite(":memory:", { busytimeout: 5 }) catch e -> e.message)
print(sqlite(":memory:", { readOnly: 1 }) catch e -> e.message)

db.close()

print(db.query("select 1") catch e -> e.message)
print(db.exec("select 1") catch e -> e.message)

// **Closing twice is not an error**, a database being a thing a program closes on a path it may
// reach more than once.
db.close()

print("closed twice")
