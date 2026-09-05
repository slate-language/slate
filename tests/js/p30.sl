// `slate:crypto`'s Argon2id, on both back ends.
//
// The interpreter derives with monocypher and a JavaScript host derives with node's own
// `crypto.argon2`, so this is the one corpus file where two entirely separate implementations of a
// memory-hard function have to answer the same bytes. A fixed salt is what makes that visible: with
// the kernel's own salt every record differs from every other and the comparison could only be a
// round trip, which each host would pass alone.
//
// The two directions are both here. `made` below is a record the INTERPRETER wrote, checked by
// whichever host is running; the fixed-salt records are written afresh by each host and compared as
// text, so a JavaScript host's own output is measured against the interpreter's.
//
// A browser has no Argon2 at all and refuses, which nothing here can see -- node is the host these
// run on. `docs/reference/javascript.md` says which half is which.

import { argon2, argon2Verify, argon2NeedsRehash } from slate:crypto

// A record the interpreter made, salt and all.
val made = "$argon2id$v=19$m=19456,t=2,p=1$r4sbZmsG138SCHlHRMqEZA$TKhpkYsEAjK8SUF4SfecoO2ZABzH6pCzLZ2lRRWwMx8"

// Eight blocks and one pass -- below anything a real login writes, which is what `argon2NeedsRehash`
// is asked about. Nothing derives from it, so its cost is nobody's.
val weak = "$argon2id$v=19$m=8,t=1,p=1$AgICAgICAgICAgICAgICAg$AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM"

// The same shape asking for just under four gibibytes of working memory.
val greedy = "$argon2id$v=19$m=4000000,t=2,p=1$AgICAgICAgICAgICAgICAg$AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM"

// **What hands the machine a value the checker cannot see**, an unannotated function answering `any`
// by design -- without it these are refused at the compile and the run-time check is never reached.
anything(v) = v

async main()
    // -- the derivation itself, which is what this file is for ---------------------------------

    val fixed = await argon2("correct horse", { salt: "slatefixedsalt16" })

    print(fixed)
    print(await argon2Verify(fixed, "correct horse"), await argon2Verify(fixed, "wrong"))

    // The parameters that are not the defaults travel in the record and are read back out of it.
    print(await argon2("root", { salt: "slatefixedsalt16", memoryCost: 32, timeCost: 1, parallelism: 2, hashLength: 16 }))

    // An empty password is a password, and it is not the same as any other.
    val empty = await argon2("", { salt: "0123456789abcdef" })

    print(empty)
    print(await argon2Verify(empty, ""), await argon2Verify(empty, " "))

    // -- a record one back end made, checked by the other --------------------------------------

    print(await argon2Verify(made, "correct horse"), await argon2Verify(made, "Correct horse"))

    // -- what a record says it was made with ---------------------------------------------------

    print(argon2NeedsRehash(weak), argon2NeedsRehash(made))
    print(argon2NeedsRehash(made, { memoryCost: 65536, timeCost: 3 }))
    print(startsWith(fixed, "$argon2id$v=19$m=19456,t=2,p=1$"), len(split(fixed, "$")))

    // -- and every way of getting it wrong -----------------------------------------------------

    // **A wrong password is `false` and a record that will not parse is a FAULT**, which is the one
    // confusion a login path must not have.
    print(argon2Verify("hello", "x") catch e -> e.message)
    print(argon2Verify("", "x") catch e -> e.message)
    print(argon2NeedsRehash("hello") catch e -> e.message)
    print(argon2Verify("x", made) catch e -> e.message)
    print(argon2Verify(greedy, "x") catch e -> e.message)

    print(argon2(anything(42)) catch e -> e.message)
    print(argon2() catch e -> e.message)
    print(argon2Verify("a") catch e -> e.message)
    print(argon2NeedsRehash() catch e -> e.message)

    print(argon2("x", anything(65536)) catch e -> e.message)
    print(argon2("x", { memoryCosts: 1 }) catch e -> e.message)
    print(argon2("x", { memoryCost: 4 }) catch e -> e.message)
    print(argon2("x", { timeCost: 0 }) catch e -> e.message)
    print(argon2("x", { hashLength: 3 }) catch e -> e.message)
    print(argon2("x", { memoryCost: anything("lots") }) catch e -> e.message)
    print(argon2("x", { salt: "short" }) catch e -> e.message)
    print(argon2("x", { salt: anything(7) }) catch e -> e.message)

main()
