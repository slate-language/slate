# `slate:password`

Argon2id — the one hash in slate meant to be slow.

```slate
import { hash, check, needsRehash } from slate:password

val stored = hash("correct horse")      // a PHC record, 19 MiB and two passes

print(startsWith(stored, "$argon2id$"))
print(check(stored, "correct horse"))
print(check(stored, "wrong"))
print(needsRehash(stored))
```

```output
true
true
false
false
```

| | |
|---|---|
| `hash(password)` | 19 MiB, two passes |
| `hashStrong(password)` | 64 MiB, three passes |
| `check(stored, attempt)` | `true` or `false` |
| `needsRehash(stored)` | ask after a successful check |

The salt comes from the operating system's entropy.

## Nothing here answers a result, and that is a decision

**A wrong password is `false`; a stored record that will not parse faults.** They are not the same failure —
a record that is not an Argon2 record is a defect in whatever wrote the column — and collapsing them would
make a corrupted row read as an intruder, which is the one confusion a login path must not have.

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
