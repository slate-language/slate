# `slate:sqlite`

SQLite — the database that needs no server, and the one a program can have without asking anybody to
install anything.

```slate
import { sqlite } from slate:sqlite

val db = sqlite(":memory:")

db.exec("create table notes (id integer primary key, title text, weight real)")
db.run("insert into notes (title, weight) values (?, ?)", "a note", 1.5)

val put = db.run("insert into notes (title) values (?)", "another")

print(put.changes, put.lastInsertRowid)

for row in db.query("select id, title from notes order by id")
    print(row.id, row.title)

db.close()
```

```output
1 2
1 a note
2 another
```

`sqlite(path)` answers the database and everything else is a method on it, which is
[`slate:redis`](redis.md)'s shape and is the same one [`pg`](https://github.com/slate-language/pg)
has — so the two databases a program might reach for do not have to be learned twice.

| | |
|---|---|
| `db.exec(sql)` | run every statement in the text, for its effect |
| `db.query(sql, ...params)` | the rows, each an object keyed by column name |
| `db.run(sql, ...params)` | `{ changes, lastInsertRowid }` |
| `db.transaction(work)` | everything `work` did, or nothing of it |
| `db.compiledWith(option)` | whether this SQLite was built with a named option |
| `db.close()` | the statements go, and then the connection |

## The path is SQLite's own, and is not always a file

`:memory:` is a private database living as long as the connection, which is what a test wants, and
`""` is a temporary one on disk that is deleted when the connection goes. Anything else is a path.

```slate
val db = sqlite("notes.db", { busyTimeout: 5000 })

db.exec("create table if not exists notes (title text)")
db.run("insert into notes (title) values (?)", "kept")

db.close()
```

**`{ readOnly: true }` opens a database that is already there** and fails where there is none, rather
than making an empty one. **`{ busyTimeout: ms }` is how long to wait for a lock** before giving up,
and is worth setting on anything more than one process writes to. Those are the two options there is,
and an option spelled any other way is refused by name rather than ignored.

## `exec` runs several statements and `query` runs one

**That is SQLite's own behaviour rather than this module's.** `sqlite3_prepare` compiles the *first*
statement in a piece of text and hands back a pointer to what is left — so a schema of six
`create table`s run through `query` would create one table and say nothing about the other five.
`exec` walks that pointer, which is why it is the call a schema goes through.

## The parameters are the arguments after the SQL

`db.query(sql, ...params)`, and a list a program worked out is spread: `db.query(sql, ...values)`.

**A parameter is never interpolated into the SQL.** SQLite compiles the statement before it is given
a single value, so nothing a parameter holds can become part of the query — `?` is the whole of the
defence against injection, and there is no escaping function here because there is nothing to escape.

**A `?` nobody bound is refused** rather than quietly bound to SQL NULL, which is what SQLite would
do: `where id = ?` called with no parameter would otherwise run, match nothing, and say nothing.

## What crosses, in each direction

| SQLite | slate |
|---|---|
| `INTEGER` | an integer, read as 64 bits |
| `REAL` | a real |
| `TEXT` | text |
| `BLOB` | an array of bytes |
| `NULL` | `null` |

**The type belongs to the value and not to the column.** SQLite is dynamically typed: a column
declared `integer` holds whatever was put in it, and two rows of one column may differ — so what a
cell comes back as is decided per row, by what is actually stored there.

Going out: text as itself, an integer and a real as themselves, `null` as SQL NULL, `true` and
`false` as 1 and 0 (SQLite has no boolean storage class), and **an array as a blob**. That last one is
simpler here than in PostgreSQL, which has both `int[]` and `bytea` and needs to be told which.

## A transaction commits on a return and rolls back on a fault

```slate
import { sqlite } from slate:sqlite

val db = sqlite(":memory:")

db.exec("create table notes (title text)")

move()
    db.run("insert into notes (title) values ('a')")

    throw "something went wrong"

print(db.transaction(move) catch e -> e.message)
print(db.query("select count(*) as n from notes")[0].n)
```

```output
something went wrong
0
```

**The rollback path is the one a program forgets**, and that is the whole argument for the method: a
failure between `begin` and `commit` that simply returns leaves the transaction open, holding its
locks, until the connection closes. Here the fault is caught, the transaction is undone, and the fault
carries on with its own words.

**SQLite has no nested transactions**, so a `transaction` inside a `transaction` is refused by the
database rather than counted.

## Statements are prepared once and kept

`query` and `run` take the SQL rather than a statement object, and the connection keeps what it
compiled — so parsing and planning happen once per piece of SQL for the life of the connection and a
program gets that without holding anything. The cache is bounded, the oldest statement going when the
room runs out, so a program that builds its SQL as text in a loop does not accumulate one per string.

## Full-text search, where the machine's SQLite has it

**What SQLite can do is a property of the machine**, it being the library the machine supplies rather
than one slate carries. `db.compiledWith("ENABLE_FTS5")` is how a program asks — the `SQLITE_` prefix
is optional — and the alternative is finding out at the `create virtual table`, which fails with
`no such module: fts5`.

```slate
import { sqlite } from slate:sqlite

val db = sqlite(":memory:")

db.exec("create virtual table search using fts5(body)")
db.run("insert into search (body) values (?)", "the quick brown fox")
db.run("insert into search (body) values (?)", "a lazy dog sleeping")

val hits = db.query("select body, bm25(search) as score from search where search match ? order by score", "fox")

print(len(hits), hits[0].body)
print(hits[0].score is real, hits[0].score < 0)
```

```output
1 the quick brown fox
true true
```

**`bm25` is negative**, FTS5 ordering a better match first by making its score smaller.

## Faults, not results

**Everything here faults with a sentence**, which is the one place slate's rule reads the other way
round. The rule is that [text from outside the program is an answer and a value the program built
itself is a fault](../reference/faults.md) — and a local database is on the second side of that line
nearly everywhere it can fail: the SQL is in the program, the number of parameters is a property of
that SQL, and a call on a closed database is a mistake in the order the program did things.
[`pg`](https://github.com/slate-language/pg) answers a result instead, and the difference is the
machine: a server that is down, a password that is wrong and a role that does not exist are all
conditions a program was always going to handle.

A program that wants an answer rather than a fault writes `catch`:

```slate
val rows = db.query(sql) catch e -> []
```

## Both hosts have it

**node has carried `node:sqlite` since 22.5**, so this module is whole under `slate js` as well as
here — the same object with the same methods, over node's own copy of SQLite rather than the
machine's. `tests/js/p28.sl` is what says the two agree: the storage classes, the transaction, the
full-text search and every sentence either back end says about SQL it will not take.

**A browser has no SQLite and `node:sqlite` is not coming to one** — what a page has instead is
IndexedDB and the long-deprecated Web SQL, neither of which is this — so the module refuses there
naming node's module, exactly as [`slate:brotli`](brotli.md) does.

**Two builds of SQLite are two builds**, so a version number, a `bm25` score and anything else the
library is free to change between releases are properties of the machine rather than claims about
slate.
