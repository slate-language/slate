# `slate:password`

Argon2id — the one hash in slate meant to be slow.

```slate
import { hash, check, needsRehash } from slate:password

async main()
    val stored = await hash("correct horse")    // a PHC record, 19 MiB and two passes

    print(startsWith(stored, "$argon2id$"))
    print(await check(stored, "correct horse"))
    print(await check(stored, "wrong"))
    print(needsRehash(stored))

main()
```

```output
true
true
false
false
```

| | |
|---|---|
| `hash(password)` | a promise of a record — 19 MiB, two passes |
| `hashStrong(password)` | a promise of a record — 64 MiB, three passes |
| `check(stored, attempt)` | a promise of `true` or `false` |
| `needsRehash(stored)` | `true` or `false`, at once |

The salt comes from the operating system's entropy.

## The derivation runs on a thread, which is why three of these are promises

**Hashing a password is supposed to take a tenth of a second, and a loop is one thread.** Done on the
loop, that tenth of a second is a tenth of a second in which the server answers nobody — so ten
simultaneous logins were ten seconds of a dead process. `hash`, `hashStrong` and `check` hand the
derivation to libuv's thread pool and answer promises; everything else the server is doing carries on
while it runs.

**`needsRehash` is not one of them**, and the difference says what the pool is for: it reads the
parameters out of the record and compares them, which is microseconds and no derivation at all. A
promise there would be ceremony.

**The pool is four threads unless `UV_THREADPOOL_SIZE` says otherwise**, and it is shared with file
reads and name resolution — so a login that is being hashed is one of four things the process can be
waiting on at once. A server expecting many at a time raises it in the environment before it starts.

## Nothing here answers a result, and that is a decision

**A wrong password is `false`; a stored record that will not parse faults.** They are not the same failure —
a record that is not an Argon2 record is a defect in whatever wrote the column — and collapsing them would
make a corrupted row read as an intruder, which is the one confusion a login path must not have.

**Becoming promises changed none of that.** `await hash(p)` is the record itself and `await check(r, p)` is
a boolean — not the `{ ok, value }` a file read or a socket send answers. Those carry a result because what
they read came from outside the program and may not be there; a derivation is a value the program built, and
every way it can go wrong is a fault raised where the call is written, before anything reaches a thread.

## The parameters travel inside the record

So raising what `hash` writes invalidates nothing, and `needsRehash` names the rows to upgrade. `check`
allocates *after* reading the record rather than from the profile it prefers, which is what makes that work.

## `hashStrong` rather than an option

`hash(p, true)` says nothing at the call about what was asked for, where `hashStrong(p)` says it outright —
and a login path is the code a reader most needs to check by eye.

## The names

**`hash` and `check` are the argument for a module in its strongest form.** A table with a `hash` of its own
and a validator with a `check` are both ordinary things to write, and either would have shadowed a builtin
without meaning to. `check` is also what `verify` had to become, since [`slate:jwt`](jwt.md) exports that
name and a server wants both modules at once.
