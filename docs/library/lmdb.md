# `slate:lmdb`

An ordered key-value store in a memory-mapped file — the one place a slate server can keep something
across a restart without a second process being up.

```slate
import { lmdbOpen, lmdbWrite, lmdbRead, lmdbDb, lmdbPut, lmdbGet, lmdbCommit, lmdbAbort } from slate:lmdb

// The directory has to exist; LMDB writes `data.mdb` and `lock.mdb` into it.
val store = lmdbOpen("/var/db/sessions", { mapSize: 1 << 30, maxDbs: 4 })

val w = lmdbWrite(store)
val sessions = lmdbDb(w, "sessions")

lmdbPut(w, sessions, "s:abc", toJSON({ user: "ed", at: 1 }))
lmdbCommit(w)

val r = lmdbRead(store)

print(parseJSON(fromBytes(lmdbGet(r, lmdbDb(r, "sessions"), "s:abc")).value).value.user)
print(lmdbGet(r, lmdbDb(r, "sessions"), "s:nothing"))     // null — a key that is not there

lmdbAbort(r)
```

**The blocks on this page are quoted rather than run**, which is what every page here does for a
module that needs somewhere on disk of its own: a program that made a store would be picking a path,
and the one it picked would be the suite's business rather than the reader's.
`dev/slatelang/slate/tests_lmdb.sysl` runs all of this against a real store in a directory of its
own.

## Why it is here

**Every server slate is aimed at wants the same three things and had nowhere to put them**: a session
store, a rate-limit bucket per client, and a replay ring for the events a reconnecting browser
missed. Each is small, is read far more often than it is written, and is worthless if it evaporates
when the process restarts — and until this module the answers were a file rewritten by hand or
[`slate:redis`](redis.md), which is a second process to run and a network hop for a lookup that
should cost a page fault.

**A read takes no lock and blocks nothing.** Readers never block writers, writers never block
readers, and there is exactly one writer at a time across the whole store and across every process
using it. That last part is the trade — this is not the store for a write-heavy queue — and it is
exactly right for the three uses above, where a write is a session being created and a read is every
request after it.

## A handle is an integer

An environment, a transaction, a database and a cursor are each a number into a table inside slate,
which is what every handle in slate is — a socket, a timer, a compiled pattern, an HTTP/2 session.
So `==` compares what slate says it compares, `print` has something to say, and a number from one
table handed to a call that wants another is refused rather than misread.

## The nineteen names

| | |
|---|---|
| `lmdbOpen(path, options)` `lmdbClose(env)` `lmdbInfo(env)` | the store |
| `lmdbRead(env)` `lmdbWrite(env)` `lmdbCommit(txn)` `lmdbAbort(txn)` | a transaction |
| `lmdbDb(txn, name)` `lmdbClear(txn, db)` `lmdbStat(txn, db)` | a database inside it |
| `lmdbGet` `lmdbHas` `lmdbPut` `lmdbDelete` | one key |
| `lmdbCursor(txn, db)` `lmdbFirst` `lmdbNext` `lmdbSeek(cur, key)` `lmdbCursorClose` | a range |

**A key or a value may be text or bytes, and what comes back is always bytes.** Text crosses as its
UTF-8, which is what `toBytes` would have made of it and what would have gone onto a wire either
way; LMDB records nothing about which of the two it was given, so `fromBytes` is how a program that
wrote text reads it back.

**A named database is itself a key in the unnamed one**, which is where LMDB keeps the name-to-handle
mapping — so the unnamed database of a store with three named ones has three keys in it before a
program writes anything. Keep ordinary keys somewhere else, or behind a prefix.

**`lmdbDb(txn, null)` is the store's unnamed database**, which is always there. A named one needs
`maxDbs` to have been large enough at `lmdbOpen`, and — the first time — a write transaction, since
making it writes. **Whether it is created is decided by which transaction asked** rather than by an
option: a reader cannot write, so a reader asking for a database that does not exist wanted
`lmdbWrite`.

## What is an answer and what is a failure

**A key that is not there is `null`**, and `lmdbDelete` on one is `false`. A store is asked about
keys it does not have as a matter of course — that is what a session lookup on a first request is —
so the ordinary case must not be the exceptional one.

**Everything else faults with a sentence.** A store is opened once at start-up and every call after
it is a program touching its own data, so there is no result to thread through every call site; a
`catch` is there for the two that a running server really can hit, which are a full map and a disk
that will not take a write.

## `mapSize` is a hard ceiling and never a hint

LMDB reserves that much address space when the store is opened and **never grows it**. A write past
it fails and the store has to be reopened larger — there is no growing it in place, and no amount of
free disk changes that.

It costs nothing until it is used, the map being sparse, so **naming a figure far larger than the
data is the normal thing to do**: a gigabyte for a session store is not a gigabyte of anything.
`lmdbInfo` answers `{ mapSize, used, maxReaders, readers, lastTransaction }`, and `used` against
`mapSize` is the only meaningful fraction — the number of keys says nothing about how much room is
left.

The default is 10 MB, which is deliberately small enough to be wrong for anything real. `maxDbs`
defaults to 16, which is not LMDB's own default of *none*: a program that asked for a database by
name would otherwise be refused on its very first call.

## Two readers at once, which is what most bindings get wrong

**LMDB's default gives each thread ONE reader slot**, and a second read transaction on a thread that
already holds one is refused with `MDB_BAD_RSLOT` — whose own message, *"Invalid reuse of reader
locktable slot"*, reads as a damaged lock file rather than the design decision it is.

slate opens every store with `MDB_NOTLS`, which moves the slot onto the transaction. Two request
handlers each holding a reader is the ordinary case here, so **there is no option for this** and a
program cannot turn the refusal back on.

## A transaction that is merely dropped aborts

That is the safe way round: a handler that throws halfway through a sequence of writes leaves the
store as it was, and one that meant to keep the work has already said so with `lmdbCommit`. The end
of a program does the same to everything still open.

**`lmdbClose` ends every transaction still open on the store**, cursors first, in the order LMDB
requires — a server shutting down must not be stopped by a handler that was mid-write.

**A cursor dies with its transaction.** LMDB frees the transaction structure when one ends and a
cursor holds a pointer into it, so a cursor used afterwards would be reading pages LMDB has
reclaimed; slate refuses instead. `lmdbCursorClose` is for a long-lived reader making many walks,
where the cursors would otherwise pile up until it committed.

## A range is a cursor and byte order

Keys come out in byte order, so **a prefix is a contiguous run**: `lmdbSeek(cur, "u:")` moves to that
key or the first one after it, and `lmdbNext` walks from there. That is the whole of a prefix scan,
and it works whether or not `u:` is itself a key.

```slate
val cur = lmdbCursor(r, db)
var at = lmdbSeek(cur, "u:")

while at != null && startsWith(fromBytes(at.key).value, "u:")
    print(fromBytes(at.key).value)
    at = lmdbNext(cur)
```

`lmdbFirst` starts at the beginning, and the end of a walk is `null`.

## What is not here

**A session store, a token bucket, a replay ring.** Each is a key layout and an expiry rule — a
policy — and policy belongs in a package rather than in the compiler. What is here is the store they
are all written over, which is [`slate:llhttp`](llhttp.md)'s arrangement exactly: the state machine
is slate's and what is built on it is not.

**Duplicate-key databases, custom orderings and nested transactions**, all of which LMDB has. None
has been needed yet, and a comparator that disagrees between two openings of one database corrupts it
silently — a sharp enough edge to want a design rather than a wrapper.

## The interpreter only

**No JavaScript host has LMDB and every name here refuses under `slate js`.** A browser has no
memory-mapped file at all — `IndexedDB` and the Origin Private File System are what a page stores
things in, and neither is an ordered B+tree walked with a cursor — and node has no LMDB in its
standard library either: every binding on npm is a native addon, so a compiled program would depend
on something the tool cannot see and did not install.

So this is a refusal naming LMDB rather than a `not in the JavaScript back end yet` stub, which is
[`slate:brotli`](brotli.md)'s case and gets its treatment. `docs/reference/javascript.md` lists it
with the rest.

## The library

**Not vendored** — LMDB is the library the machine has: `brew install lmdb` on macOS, `liblmdb-dev`
on Debian and Ubuntu, `lmdb` on Arch. pkg-config finds it on all three.
