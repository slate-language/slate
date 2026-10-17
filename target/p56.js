"use strict";

// The slate runtime, as JavaScript.
//
// A slate value is a JavaScript one wherever the two agree, and the disagreements are what this
// file is: an integer is a BigInt, because slate's has no width -- it grows rather than wrapping,
// and it divides towards zero where a double does not; an object is an `SObj`, because slate's keeps
// insertion order and delegates through a field called `proto`; and a string is counted in
// characters rather than in UTF-16 units.
const $ = (() => {
    // **`i64` NO LONGER IMPLEMENTS THE LANGUAGE'S RULE AND IS KEPT FOR THE PROTOCOLS THAT HAVE
    // ONE.** It wrapped every arithmetic answer while a slate integer was 64 bits wide;
    // integers grow now, so the arithmetic has no use for it and what is left is the places a
    // SIXTY-FOUR-BIT value is genuinely what is being computed -- a timeline in microseconds,
    // a process's exit signal. Those are widths of a thing, not of the language.
    const i64 = (x) => BigInt.asIntN(64, x)

    // How far a shift may move a number, in places. **The interpreter's `MaxShift`, and it is
    // here so the two back ends refuse the same program**: a `BigInt` shift has no bound of
    // its own, so without this `1 << (10n ** 10n)` would be an allocation failure on one host
    // and a sentence on the other.
    const MaxShift = 16777216n

    // Whether an integer is one a call needing a MACHINE integer can take.
    //
    // **The interpreter answers this by the variant a value is in and this host has to ask**,
    // a `BigInt` being one kind at every width. It is what the three sites that turn an
    // integer into a `Number` -- an index, a byte, a count -- test before they do, so that a
    // number too wide is refused with the sentence the interpreter refuses it with rather than
    // rounded into a `Number` and reported as `1e+30`.
    const fitsI64 = (v) => v >= -9223372036854775808n && v <= 9223372036854775807n

    // How deep a `proto` chain may go before slate calls it a circle. The interpreter's ceiling.
    const MaxProtoDepth = 64

    // -- faults and throws -------------------------------------------------------------------

    class Fault extends Error {
        constructor(message) {
            super(message)
            this.slate = "fault"
            this.reason = message
            this.line = $line
            this.file = $file
        }
    }

    // `throw v`, which carries a slate value rather than a sentence.
    //
    // **Where it was thrown is stamped here and does not travel**, which is the interpreter's rule:
    // a caught fault put back with `throw e` says the words of the original and points at the line
    // that put it back.
    // **The `Error`'s own message is the sentence the value renders to**, which is what an
    // uncaught fault prints: node reports a raised `Error` by its message, so a fixed word here
    // would make `throw NotFound(3)` say nothing at all. `thrownMessage` is declared in a later
    // block of this one program and is initialised long before a program can throw.
    class Thrown extends Error {
        constructor(value) {
            super(thrownMessage(value))
            this.slate = "thrown"
            this.value = value
            this.line = $line
            this.file = $file
        }
    }

    let $line = 0
    let $file = ""

    // The files the program was written in, in the order the loader read them. A marker names one
    // by index, which is what keeps a line table from carrying a path per statement.
    let $files = [""]

    const fault = (message) => { throw new Fault(message) }

    // `skip("...")` leaving a test.
    //
    // **A class of its own and not a `Fault`, which is the interpreter's `Signal.Skip`**: a
    // `catch` in a slate program passes it straight through, so a test that leaves itself out
    // cannot have that decision swallowed by a library it called.
    class Skipped extends Error {
        constructor(reason) {
            super(reason)
            this.slate = "skip"
            this.reason = reason
        }
    }

    // `exit(n)` on its way out of a program -- the interpreter's `Signal.Quit`, told the same way
    // `Skipped` tells `Signal.Skip`: a class of its own, so `caught` can pass it straight through
    // every `catch` a program wrote, exactly as `guarded` passes a `Quit` through every handler.
    class Exited extends Error {
        constructor(status) {
            super("exited")
            this.slate = "exit"
            this.status = status
        }
    }

    // **Whether `exit` is a program stopping or a test asking to stop one it is not.** `B.exit`
    // reads this to decide between the two; `$suite` is the only thing that ever turns it on, for
    // the run of a test file it drives, and never turns it back off -- `slate test --js` runs one
    // suite and then the process, having nothing left to run under the other rule, ends anyway.
    let $testMode = false

    // -- objects ---------------------------------------------------------------------------------

    // An object: insertion-ordered string keys, delegating through its own `proto` field.
    //
    // **`proto` is an ordinary field and not a slot of its own**, which is the interpreter's
    // arrangement: a program reads it, writes it and prints it like any other, and `field_from`
    // walks it. A `Map` holds the fields because a slate key may be any string at all, `__proto__`
    // and `constructor` included, and none of JavaScript's inherited furniture should be reachable
    // by writing a field name.
    // **A SLATE KEY IS ANY VALUE, AND THIS USED TO BE A `Map` OF STRINGS.** `t[[1, 2]] = "x"` and
    // `t[{a: 1}] = "y"` work in the interpreter and were refused outright here -- *"an object is
    // indexed by a string, and this is an array"* -- so a `hash` hook could never be reached under
    // `slate js` at all, an object never getting as far as being a key.
    //
    // **The map is keyed by a SLOT STRING and holds `[key, value]`**, so the original key comes
    // back out for `keys`, `entries` and the printer. A slot is worked out two ways:
    //
    // - **a scalar is its own exact slot** -- `"s"` and the text, `"i"` and the digits -- which
    //   keeps a field name one string concatenation away from the `Map` it was always in, and that
    //   is the whole of what this costs on the path every program takes.
    // - **anything else is HASHED AND THEN COMPARED**, `"h" + hash + "#" + n`, walking `n` upward
    //   until the slot is free or its key is `eq` to this one. That is a hash table with linear
    //   probing written in three lines, and it is what an exact canonical string cannot do: a
    //   cyclic key has no finite spelling, and a class with its own `equals` decides equality by
    //   rules no spelling could reproduce.
    //
    // **The hash is INTERNAL and deliberately not the interpreter's number.** Nothing compares one
    // across the two back ends -- `hash` is a hook and not a readable method, exactly so that this
    // stays free -- so all it owes is agreement with `eq` in this runtime.
    const scalarSlot = (k) => {
        if (typeof k === "string") return "s" + k
        if (typeof k === "bigint") return "i" + k

        // **An integer and a real that are numerically equal MUST share a slot**, because `==`
        // says they are equal: `1 == 1.0` is true in slate, so `t[1]` and `t[1.0]` have to find
        // each other.
        if (typeof k === "number") return Number.isInteger(k) ? "i" + BigInt(k) : "r" + k
        if (typeof k === "boolean") return k ? "b1" : "b0"
        if (k === null) return "z"

        // **Each kind is salted with its own letter**, so an instant and a duration holding the
        // same number never collide as table keys. `hash_plain` salts for the same reason.
        if (k instanceof SInstant) return "t" + k.us
        if (k instanceof SDuration) return "d" + k.us

        // The six calendar kinds salt themselves the same way, in `js_rt_cal.sysl` beside the
        // classes they are about. **Their letters are CAPITALS**, which is the whole of what
        // keeps them clear of the eight written here.
        const dated = calendarKey(k)

        if (dated !== null) return dated

        // A compiled pattern is its slot, which interning makes the same thing as its source
        // and its flags -- so `t[regex("a")]` finds what `t[regex("a")] = 1` put there.
        const patterned = regexKey(k)

        if (patterned !== null) return patterned

        if (k instanceof SRange) {
            const end = k.hasLo && k.hasHi ? k.last() : (k.inclusive ? k.hi : k.hi - 1n)

            return "g" + k.lo + ":" + end + ":" + k.step + ":" + (k.hasLo ? 1 : 0) + (k.hasHi ? 1 : 0)
        }

        return null
    }

    // Where a value hashes to, for the slot scan above.
    //
    // **A `hash` the program wrote decides**, with the receiver rule every other hook takes, so a
    // class keying a table by its own notion of sameness works here as it does in the interpreter.
    const hashValue = (v, depth) => {
        const said = callHook(v, "hash", [])

        if (said !== NO_HOOK) {
            if (typeof said !== "bigint")
                fault("`hash` must answer an integer, and this answered " + typeName(said))

            return Number(BigInt.asUintN(32, said))
        }

        const mix = (a, b) => (Math.imul(a, 31) + b) | 0

        // **A cycle stops at the cap rather than descending forever**, and that is free: a slot is
        // settled by `eq` and not by the hash, so two values landing on one number cost a probe
        // and nothing else.
        if (depth > 8) return 17

        if (Array.isArray(v)) {
            let h = 7

            for (const x of v) h = mix(h, hashValue(x, depth + 1))

            return h
        }

        if (v instanceof SObj) {
            let h = 0

            // **Summed rather than mixed in order, because `same` compares contents and not
            // order** -- an object that gained its fields in another order is the same object, so
            // an order-sensitive hash would lose one of the two.
            for (const [k, x] of v.entries())
                h = (h + Math.imul(hashValue(k, depth + 1), 31) + hashValue(x, depth + 1)) | 0

            return h
        }

        // An opaque value hashes as what `same` compares: its declaration and what it is made of.
        if (v instanceof SVeil) return mix(11 + v.kind, hashValue(v.rep, depth + 1))

        const scalar = scalarSlot(v)

        if (scalar !== null) {
            let h = 5

            for (let i = 0; i < scalar.length; i++) h = mix(h, scalar.charCodeAt(i))

            return h
        }

        // **An external hashes by the host value it holds, not by its own wrapper** -- two
        // wrappers around one host value `==` each other (`js_rt_ops.sysl`'s `a.held === b.held`),
        // so a map keyed by one has to find the other, which only holds if they hash alike.
        if (v instanceof SExt) return identityNumber(v.held)

        // A function, a promise and a generator compare by identity, so they hash by one: a lazy
        // serial number, which is what an address is for the interpreter.
        return identityNumber(v)
    }

    const IDENTITY = new WeakMap()
    let identityNext = 1

    const identityNumber = (v) => {
        if (v === null || (typeof v !== "object" && typeof v !== "function")) return 3

        const had = IDENTITY.get(v)

        if (had !== undefined) return had

        IDENTITY.set(v, identityNext)

        return identityNext++
    }

    // A value of the JavaScript host, which an `external` declaration named.
    //
    // **It is a wrapper and not the host value itself, which is the whole of the invariant**: a
    // foreign object can then never be mistaken for a slate one, `typeName` has something to say
    // about it, and every operation on it is one that has to go through `js_rt_ops.sysl`'s door.
    // `held` is what the host handed over; `receiver` is the object a path found it on, or
    // `undefined` for one read back out of another external.
    class SExt {
        constructor(held, receiver) {
            this.held = held
            this.receiver = receiver
        }
    }

    class SObj {
        // **`entries` is `[key, value]` pairs as a program wrote them**, not slots -- an object
        // literal is emitted as one of these and knows nothing about the table underneath. A COPY
        // goes through `SObj.copy`, which clones the slot map and hashes nothing a second time.
        constructor(entries) {
            this.fields = new Map()

            if (entries) for (const [k, v] of entries) this.setKey(k, v)

            // Whether this object is closed to writing, whatever closed it: a data variant's
            // `new` seals one and `freeze` closes any of them. The interpreter keeps the same
            // pair on its own object, and both refuse the same writes with the same sentences.
            this.frozen = false

            // Whether it is closed BECAUSE it is a data value, which is what picks the sentence
            // and what `with` carries into the copy.
            this.dataValue = false
        }

        // The slot this key occupies, or would occupy -- **always a string, never null**, so the
        // four operations below are one `Map` call each and the "is it there" question is asked
        // of the map rather than answered twice.
        slot(k) {
            const scalar = scalarSlot(k)

            if (scalar !== null) return scalar

            const at = "h" + hashValue(k, 0) + "#"

            for (let n = 0; ; n++) {
                const here = at + n
                const held = this.fields.get(here)

                if (held === undefined) return here
                if (eq(held[0], k)) return here
            }
        }

        getKey(k) {
            const held = this.fields.get(this.slot(k))

            return held === undefined ? undefined : held[1]
        }

        setKey(k, v) { this.fields.set(this.slot(k), [k, v]) }

        hasKey(k) { return this.fields.has(this.slot(k)) }

        deleteKey(k) { return this.fields.delete(this.slot(k)) }

        // The keys and values a program wrote, in the order it wrote them -- which is the `Map`'s
        // own order, the slot strings being incidental.
        *entries() { for (const [, kv] of this.fields) yield kv }

        // A copy carrying the slots already worked out. `with` makes one per expression, so
        // rehashing every key of the base would make that cost the size of the object.
        static copy(base) {
            const made = new SObj()

            made.fields = new Map(base.fields)

            return made
        }

        get size() { return this.fields.size }

        // A field by NAME, which is the path every program takes and the reason a scalar slot is a
        // concatenation rather than a hash.
        getName(name) { return this.getKey(name) }

        hasName(name) { return this.fields.has("s" + name) }

        setName(name, v) { this.fields.set("s" + name, [name, v]) }

        // What `name` is here or up the chain, and whether it was delegated to.
        //
        // The second half is the receiver rule: a method the object carries itself has captured what
        // it needs already, and a shared one reached through `proto` has not.
        //
        // **`new` is the one name the rule does not reach**, there being no object yet to hand it --
        // the interpreter's `field_from` says the same thing for the same reason.
        lookup(name) {
            if (this.hasName(name)) return [this.getName(name), false]

            let up = this
            let depth = 0

            for (;;) {
                const next = up.getName("proto")

                if (!(next instanceof SObj)) return [undefined, false]
                if (next.hasName(name)) return [next.getName(name), name !== "new"]

                depth += 1

                if (depth >= MaxProtoDepth)
                    fault("this object's `proto` chain is more than " + MaxProtoDepth +
                        " deep, which means it is a circle -- looking up `" + name + "` would never finish")

                up = next
            }
        }
    }

    // A set and a map, each of which is an `SObj` and nothing else.
    //
    // **The table above is already the whole of what a set and a map need**, and reaching for
    // the host's own `Map` and `Set` would have been the mistake: those key on SameValueZero, so
    // two equal arrays are two keys, a class's `==` and `hash` are never asked, and `1` and
    // `1.0` are two entries where slate says they are one value. `SObj`'s slot scheme answers
    // all three the way the interpreter answers them, so the two back ends agree by
    // construction rather than by a second implementation kept in step.
    //
    // **A set uses the key half and stores `null` in the value half**, which is what the
    // interpreter does with the same table.
    class SSet {
        constructor() { this.t = new SObj() }

        get size() { return this.t.size }

        *values() { for (const [k] of this.t.entries()) yield k }
    }

    class SMap {
        constructor() { this.t = new SObj() }

        get size() { return this.t.size }

        *entries() { for (const kv of this.t.entries()) yield kv }
    }

    // A range, which is a value in slate rather than a form of `for`.
    // `step` is a BigInt, `1n` for a range nobody gave a `by`, and never zero.
    class SRange {
        constructor(lo, hi, inclusive, hasLo, hasHi, step) {
            this.lo = lo
            this.hi = hi
            this.inclusive = inclusive
            this.hasLo = hasLo
            this.hasHi = hasHi
            this.step = step
        }

        // How many numbers it covers, counting by its step, and the `i`th of them. A step whose
        // sign disagrees with the ends covers nothing, which is the answer `10..0` already gave.
        count() {
            if (this.step > 0n) {
                const last = this.inclusive ? this.hi : this.hi - 1n

                return last < this.lo ? 0n : (last - this.lo) / this.step + 1n
            }

            const last = this.inclusive ? this.hi : this.hi + 1n

            return last > this.lo ? 0n : (this.lo - last) / -this.step + 1n
        }

        at(i) { return this.lo + this.step * i }

        // The last number it reaches, which is what equality and a table key compare: the same
        // numbers written two ways are one range.
        last() {
            const n = this.count()

            return n === 0n ? (this.inclusive ? this.hi : this.hi - 1n) : this.at(n - 1n)
        }
    }

    // A declared type, as a value. The pattern is the same data `is` is emitted against, and the
    // name is what the declaration called it.
    //
    // **Two shapes are equal only where they are the same declaration**, which `same` gives for
    // nothing by falling through to `===`. Two types written the same way are two types, where
    // two regular expressions written the same way are one.
    class SShape {
        constructor(pat, name) {
            this.made = pat
            this.name = name
        }

        // **The pattern may arrive as a THUNK, and a class's own shape always does.** A class is
        // emitted as one object literal and its shape sits inside it, so a pattern naming the
        // class -- which `["proto", Circle, "Circle"]` does -- would read the binding while it is
        // still being made. The interpreter has no such trouble, its patterns naming a class by
        // NAME and looking it up in the declaring scope as they match, so the laziness here is
        // what makes the two back ends agree rather than a JavaScript flourish.
        get pat() {
            if (typeof this.made === "function") this.made = this.made()

            return this.made
        }
    }

    // A value of an `opaque type`: what it is made of, and the declaration that made it.
    //
    // **The interpreter's `Value.Veiled`, field for field**, the declaration being the same
    // number in both (`Vm.veils`) -- so a pattern emitted as `["veil", k, name]` asks what the
    // machine asks. The name is for a complaint and `home` for `$.uh`, the declaring file's
    // operands being the one place the representation is handed out unasked.
    class SVeil {
        constructor(kind, name, home, rep) {
            this.kind = kind
            this.name = name
            this.home = home
            this.rep = rep
        }
    }

    // A socket, which is a SLOT and a GENERATION and never the host's own object.
    //
    // **The interpreter's `Socket(id, gen)` word for word**, and for its reason: the value a
    // program holds carries the generation that claimed the slot, so a socket held across a
    // `close` never comes to mean whatever opens next. Nothing foreign becomes a slate value,
    // which is the rule the timers' ids already follow.
    class SSocket {
        constructor(id, gen) {
            this.id = id
            this.gen = gen
        }
    }

    // A child process, which is a SLOT and a GENERATION -- the interpreter's `ChildVal(id, gen)`
    // word for word, and never node's own object. A slot is never given back, a child answering
    // for its pid and its exit long after it has died.
    class SChild {
        constructor(id, gen) {
            this.id = id
            this.gen = gen
        }
    }

    // This program's own end of the channel it was started with. **One number**, a program
    // having one parent and nothing that gives the slot back.
    class SChannel {
        constructor(id) {
            this.id = id
        }
    }

    // An actor's handle, and one of its handlers named on it.
    //
    // **BOTH ARE INTERNED, which is what makes `==` identity.** The interpreter's `ActorVal` is a
    // slot and a generation compared field by field, and `same` here falls through to `===` for
    // anything it has no arm for -- so two handles naming one actor have to BE one object.
    // `$.actorHandle` and `$.actorMessage` are the only two makers, and a handle rebuilt out of a
    // message that crossed a worker boundary comes back as the very object this side already had.
    class SActor {
        constructor(id) {
            this.id = id
        }
    }

    class SMessage {
        constructor(id, name) {
            this.id = id
            this.name = name
        }
    }

    // The two interning tables, and the only two makers. They are here, at the script's own
    // level, rather than in `js_rt_actor.sysl`, because `field` and `same` are here and both
    // answer about a handle.
    const $actors = new Map()
    const $messages = new Map()

    const $actorHandle = (id) => {
        let held = $actors.get(id)

        if (held === undefined) {
            held = new SActor(id)
            $actors.set(id, held)
        }

        return held
    }

    const $actorMessage = (id, name) => {
        const at = id + " " + name
        let held = $messages.get(at)

        if (held === undefined) {
            held = new SMessage(id, name)
            $messages.set(at, held)
        }

        return held
    }

    // A buffer of bytes -- slate's `bytes` kind on this host.
    //
    // **A WRAPPER AND NOT A BARE `Uint8Array`, AND `push` IS THE WHOLE REASON.** `push(b, v)`
    // changes the buffer every name for it holds, exactly as `push(xs, v)` changes the array --
    // and a typed array cannot grow, so a bare one would have to be replaced, which the other
    // names for it would never see. The wrapper keeps a typed array with room to spare and a used
    // length, doubles the room when it runs out, and stays the same object throughout.
    //
    // **`view()` IS THE ONE THING THE HOST EVER SEES**, and it is a `subarray` rather than a copy:
    // `socket.write`, `fs.writeFile`, `crypto` and every other node call take exactly the bytes
    // that are in use, with nothing allocated to hand them over.
    class SBytes {
        constructor(u, n) {
            this.u = u
            this.n = n === undefined ? u.length : n

            // Whether `freeze` has closed this buffer, which is `SObj.frozen`'s field on the one
            // other kind a program writes through.
            this.frozen = false
        }

        get length() { return this.n }

        view() { return this.u.subarray(0, this.n) }

        at(i) { return this.u[i] }

        set(i, b) { this.u[i] = b }

        // Room for `extra` more bytes, doubling rather than growing by what was asked for -- so a
        // buffer built a byte at a time costs a copy per doubling and not one per byte.
        room(extra) {
            if (this.n + extra <= this.u.length) return

            let want = this.u.length === 0 ? 16 : this.u.length

            while (want < this.n + extra) want *= 2

            const wider = new Uint8Array(want)

            wider.set(this.view())
            this.u = wider
        }

        pushByte(b) {
            this.room(1)
            this.u[this.n] = b
            this.n += 1
        }

        // **The source is read into a local FIRST**, so appending a buffer to itself appends what
        // was there rather than walking storage that is being replaced under it.
        pushBytes(xs) {
            const from = xs === this ? this.view().slice() : xs.view()

            this.room(from.length)
            this.u.set(from, this.n)
            this.n += from.length
        }
    }

    // A buffer over a run of bytes the host handed over, taking it as it stands.
    const bytesOf = (u) => new SBytes(u, u.length)

    // The bytes of whatever a program handed in, where either a buffer or an array of numbers is
    // meant -- the interpreter's `bytes_like`, and every builtin that took the array takes both.
    //
    // **It answers a `Uint8Array` the caller may not keep**, a buffer's being a view into storage
    // that `push` replaces; anything holding on past the call takes a copy of its own.
    const bytesLike = (v, name) => {
        if (v instanceof SBytes) return v.view()

        if (Array.isArray(v)) {
            const out = new Uint8Array(v.length)

            for (let i = 0; i < v.length; i++) {
                if (typeof v[i] !== "bigint")
                    fault("`" + name + "` takes an array of numbers, and one of these is " + typeName(v[i]))

                const b = Number(v[i])

                if (b < 0 || b > 255) fault("a byte is between 0 and 255, and this is " + b)

                out[i] = b
            }

            return out
        }

        fault("`" + name + "` takes bytes or an array of numbers, and this is " + typeName(v))
    }

    // -- what a value is ---------------------------------------------------------------------------

    const isInt = (v) => typeof v === "bigint"
    const isReal = (v) => typeof v === "number"
    const isNum = (v) => typeof v === "bigint" || typeof v === "number"
    const isStr = (v) => typeof v === "string"
    const isGen = (v) => v !== null && typeof v === "object" && typeof v.next === "function" &&
        typeof v.throw === "function"

    // **An `async` generator is a generator whose steps answer promises**, so it is one of
    // these and answers `"a generator"` like any other -- what it is not is something a walk
    // that wants its values now can read. `Symbol.asyncIterator` is what tells the two apart:
    // an `async function*` object carries it where a `function*` object carries
    // `Symbol.iterator`.
    const isAsyncGen = (v) => isGen(v) && typeof v[Symbol.asyncIterator] === "function"

    // `AsyncGenWalk` in `generator.sysl`, word for word -- which back end a program is on must
    // not decide what it is told.
    const ASYNC_GEN_WALK =
        "an `async` generator's values arrive one promise at a time -- `for await` is the only way to walk one"

    const typeName = (v) => {
        if (v === null) return "null"
        if (v === undefined) return "undefined"
        if (typeof v === "boolean") return "a boolean"
        // **IT SAYS THE WIDTH WHERE THE WIDTH IS WHAT IS WRONG, WHICH IS THE INTERPRETER'S
        // ONE RULE FOR THE SAME CASE.** An integer has no width in slate, so a call that
        // genuinely needs a machine one -- an index, a byte, a count -- is refused by a
        // sentence built out of this, and "an integer" would send the reader to stare at a
        // value that is exactly the kind asked for. `value.sysl`'s `type_name` carries the
        // argument.
        if (typeof v === "bigint") return fitsI64(v) ? "an integer" : "an integer too large to fit 64 bits"
        if (typeof v === "number") return "a real"
        if (typeof v === "string") return "a string"
        if (Array.isArray(v)) return "an array"

        // **No article, the word being plural** -- the interpreter's `type_name` says the same.
        if (v instanceof SBytes) return "bytes"
        if (v instanceof SObj) return "an object"
        if (v instanceof SSet) return "a set"
        if (v instanceof SMap) return "a map"

        // **The host's own two, which is what slate's weak pair IS on this back end** -- so both
        // are asked ahead of `typeof v === "object"` reaching anything below, exactly as a set
        // and a map are.
        if (v instanceof WeakMap) return "a weak map"
        if (v instanceof WeakRef) return "a weak reference"
        if (v instanceof SRange) return "a range"
        if (v instanceof SShape) return "a shape"

        // **Its own name, with the article read off the first letter whatever its case** --
        // `veil_type_name` in the interpreter, word for word.
        if (v instanceof SVeil) return (/^[aeiou]/i.test(v.name) ? "an " : "a ") + v.name
        if (v instanceof SInstant) return "an instant"
        if (v instanceof SDuration) return "a duration"
        if (v instanceof SDate) return "a date"
        if (v instanceof STime) return "a time"
        if (v instanceof SDateTime) return "a dateTime"
        if (v instanceof SZone) return "a zone"
        if (v instanceof SZoned) return "a zoned"
        if (v instanceof SPeriod) return "a period"
        if (v instanceof SRegex) return "a regular expression"
        if (v instanceof SExt) return "an external"
        if (v instanceof SSocket) return "a socket"
        if (v instanceof SChild) return "a child process"
        if (v instanceof SChannel) return "a channel"
        if (v instanceof SActor) return "an actor"
        if (v instanceof SMessage) return "a message"
        if (v instanceof Promise) return "a promise"
        if (isGen(v)) return "a generator"
        if (typeof v === "function") return "a function"

        return "a value"
    }

    // The word an annotation is written with, which is the word `is` tests.
    const test = (v, kind) => {
        if (kind === "null") return v === null
        if (kind === "boolean") return typeof v === "boolean"
        if (kind === "integer") return isInt(v)
        if (kind === "real") return isReal(v)
        if (kind === "number") return isNum(v)
        if (kind === "string") return isStr(v)
        if (kind === "array") return Array.isArray(v)
        if (kind === "bytes") return v instanceof SBytes
        if (kind === "object") return v instanceof SObj
        if (kind === "function") return typeof v === "function" && !isGen(v)
        if (kind === "generator") return isGen(v)
        if (kind === "promise") return v instanceof Promise

        if (kind === "instant") return v instanceof SInstant
        if (kind === "duration") return v instanceof SDuration
        if (kind === "date") return v instanceof SDate
        if (kind === "time") return v instanceof STime
        if (kind === "dateTime") return v instanceof SDateTime
        if (kind === "zone") return v instanceof SZone
        if (kind === "zoned") return v instanceof SZoned
        if (kind === "period") return v instanceof SPeriod
        if (kind === "regex") return v instanceof SRegex
        if (kind === "external") return v instanceof SExt
        if (kind === "Set") return v instanceof SSet
        if (kind === "Map") return v instanceof SMap

        // **A class or a data name is one too**, carrying its own shape under the hidden tag --
        // the interpreter's `is_kind` says the same, and a parameter annotated `shape` has to
        // take the names the types page calls type expressions.
        if (kind === "shape")
            return v instanceof SShape || (v instanceof SObj && v.getKey("(shape)") instanceof SShape)

        return false
    }

    // **This is JavaScript's own rule, unwrapped.** slate's truthiness IS the host's now, so this
    // is `!!v` in every way that matters; it stays a named function because `eq` below needs to
    // turn an `==` hook's answer into a real boolean, which is a different question from whether
    // an emitted condition is true.
    const truthy = (v) => !!v

    // What `??` asks, which is not what `||` asks: `0 ?? 1` is zero, because zero is not absent.
    const present = (v) => v !== null && v !== undefined

    // `undefined` is what a field that is not there answers, and it may not be stored or passed.
    const keep = (v, where) => {
        if (v === undefined)
            fault("this field is not there, and `undefined` cannot be " + where +
                " -- give it a value with `??`, or ask `has` first")

        return v
    }

    // The one keeping place with its own sentence: a bare `next()` sends `undefined`, and a
    // `yield` whose answer is bound, written or captured may not keep it -- but "this field is
    // not there" would be false of a `yield`, so this names the generator instead. The
    // interpreter's `resume_sent` in `generator.sysl` raises the same fault in the same words.
    const keepYielded = (v) => {
        if (v === undefined)
            fault("this generator was resumed with nothing, and `undefined` cannot be kept -- " +
                "give the `yield` a value with `??`, or call `next(v)`")

        return v
    }

    // -- printing -----------------------------------------------------------------------------------

    // A real as the host writes it, which is the shortest decimal that reads back as the same
    // double -- `NaN`, `Infinity` and `-Infinity` included. The interpreter's `real_text`
    // reconstructs this rule from `%g`; here it IS the rule, so leaning on `String` is both
    // shorter and the only way the two cannot drift.
    //
    // **A negative zero is the one disagreement, and it goes slate's way.** `String(-0)` is
    // `"0"`, which hides the thing a reader printing a zero is most likely asking about.
    const realText = (x) => {
        if (x === 0) return Object.is(x, -0) ? "-0" : "0"

        return String(x)
    }

    const escaped = (s) => {
        let out = '"'

        for (const c of s) {
            if (c === '"') out += '\\"'
            else if (c === "\\") out += "\\\\"
            else if (c === "\n") out += "\\n"
            else if (c === "\t") out += "\\t"
            else if (c === "\r") out += "\\r"
            else if (c < " ") out += "\\u" + c.codePointAt(0).toString(16).padStart(4, "0")
            else out += c
        }

        return out + '"'
    }

    const plainName = (s) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(s) && !SLATE_WORDS.has(s)

    // **A KEY IS ANY VALUE, SO A KEY IS WRITTEN THE WAY A VALUE IS.** `t[{ v: 1 }] = "s"` is an
    // ordinary table here -- `SObj` hashes a key through `hashValue` and compares it with `eq`,
    // both of which take anything -- and only the PRINTER assumed a string, so printing such a
    // table died inside `escaped` with node's own `s is not iterable` rather than saying
    // anything slate knows how to say. The interpreter writes `{{v: 1}: "s"}` and this now does.
    const keyText = (k, path, hooks) =>
        typeof k === "string" ? (plainName(k) ? k : escaped(k)) : write(k, true, path, hooks)

    // The words the lexer has its own meaning for, so a key spelled like one prints quoted: `{ if: 1 }`
    // is not a program a reader could hand back to slate.
    // How many bytes of a buffer `print` writes before it says how many there were -- a line of a
    // hex dump. `render.sysl`'s `BytesShown`, and the two may not drift.
    const BYTES_SHOWN = 16

    const SLATE_WORDS = new Set(["val", "var", "if", "then", "elif", "else", "while", "for", "in",
        "loop", "do", "match", "break", "continue", "return", "true", "false", "null", "undefined",
        "async", "await", "yield", "is", "with", "import", "export", "try", "catch", "throw"])

    // A value as a program prints it: a string bare at the top level and quoted inside a container,
    // and a container already on the path as `[...]` rather than descending forever.
    const write = (v, quoted, path, hooks) => {
        if (v === null) return "null"
        if (v === undefined) return "undefined"
        if (typeof v === "boolean") return v ? "true" : "false"
        if (typeof v === "bigint") return v.toString()
        if (typeof v === "number") return realText(v)
        if (typeof v === "string") return quoted ? escaped(v) : v

        // **An opaque value prints as what it is made of and a diagnostic names its type** --
        // `render.sysl`'s rule, with `hooks` telling the two apart here as it does there.
        if (v instanceof SVeil)
            return hooks ? write(v.rep, quoted, path, hooks) : v.name + "(" + write(v.rep, true, path, hooks) + ")"

        if (Array.isArray(v)) {
            if (path.indexOf(v) >= 0) return "[...]"

            path.push(v)

            const out = "[" + v.map((x) => write(x, true, path, hooks)).join(", ") + "]"

            path.pop()

            return out
        }

        // **`<bytes 6: 68 c3 a9 6c 6c 6f>` -- the count first and the bytes in hex**, at most
        // `BYTES_SHOWN` of them. `render.sysl` writes exactly these characters, and a megabyte of
        // them is not something anybody asked `print` for.
        if (v instanceof SBytes) {
            const u = v.view()
            const shown = u.length > BYTES_SHOWN ? BYTES_SHOWN : u.length
            let out = "<bytes " + u.length

            for (let i = 0; i < shown; i++)
                out += (i === 0 ? ": " : " ") + u[i].toString(16).padStart(2, "0")

            return out + (u.length > shown ? " ...>" : ">")
        }

        // **A set prints as the array of its members and a map as the array of its pairs**,
        // which is what each encodes as too. The interpreter writes the same characters.
        if (v instanceof SSet) {
            if (path.indexOf(v) >= 0) return "[...]"

            path.push(v)

            const out = "[" + [...v.values()].map((x) => write(x, true, path, hooks)).join(", ") + "]"

            path.pop()

            return out
        }

        if (v instanceof SMap) {
            if (path.indexOf(v) >= 0) return "[...]"

            path.push(v)

            const out = "[" + [...v.entries()].map(([k, x]) =>
                "[" + write(k, true, path, hooks) + ", " + write(x, true, path, hooks) + "]").join(", ") + "]"

            path.pop()

            return out
        }

        if (v instanceof SObj) {
            if (path.indexOf(v) >= 0) return "{...}"

            path.push(v)

            // **A `toString` the program wrote replaces everything below, at every depth**, so
            // `print([d, d])` renders each element the way its own class says -- and is not
            // consulted at all where a diagnostic is being composed.
            const said = hooks ? callHook(v, "toString", []) : NO_HOOK

            if (said !== NO_HOOK) {
                path.pop()

                if (typeof said !== "string")
                    fault("`toString` says how a value prints, so it answers a string -- and this one gave " + typeName(said))

                return said
            }

            // **A data value prints as the variant that made it** -- `Circle(3)` rather than the
            // object with its whole proto chain written out. The interpreter says the same, and
            // the two back ends printing one value differently is a difference between them.
            const made = variantName(v)

            if (made !== null) {
                const held = []

                for (const [k, x] of v.entries())
                    if (k !== "proto" && !tagKey(k)) held.push(write(x, true, path, hooks))

                path.pop()

                return held.length === 0 ? made : made + "(" + held.join(", ") + ")"
            }

            // **A class instance prints as its class and its own fields, WITH the names** --
            // a class's fields are named and mutable where a variant's are positional by
            // construction, so `Rect(3, 4)` would leave a reader guessing which is the width.
            const cls = className(v)

            if (cls !== null) {
                const shown = []

                for (const [k, x] of v.entries())
                    if (k !== "proto" && !tagKey(k))
                        shown.push(keyText(k, path, hooks) + " = " + write(x, true, path, hooks))

                path.pop()

                return shown.length === 0 ? cls : cls + "(" + shown.join(", ") + ")"
            }

            // **The class OBJECT says it is one** rather than printing a constructor and a table
            // of methods, which is never what a reader printing `Point` wanted to see.
            const own = classOwnName(v)

            if (own !== null) {
                path.pop()

                return "<class " + own + ">"
            }

            // **A data type's own object says what it is**, for the reason the class object
            // does -- what it holds is whatever its variants share. The shape tag is what names
            // it, the shared object carrying no other and a variant's maker carrying it too --
            // so a maker prints `<data Circle>`, which is what it is: the thing that makes one,
            // where `Circle(3)` prints as the value. A class is asked about first, having both
            // tags.
            const shape = v.getKey("(shape)")

            if (shape instanceof SShape) {
                path.pop()

                return "<data " + shape.name + ">"
            }

            const parts = []

            for (const [k, x] of v.entries())
                if (!tagKey(k)) parts.push(keyText(k, path, hooks) + ": " + write(x, true, path, hooks))

            path.pop()

            return "{" + parts.join(", ") + "}"
        }

        if (v instanceof SRange) {
            const lo = v.hasLo ? v.lo.toString() : ""
            const hi = v.hasHi ? v.hi.toString() : ""
            const by = v.step === 1n ? "" : " by " + v.step.toString()

            return lo + (v.inclusive ? ".." : "..<") + hi + by
        }

        // **By its NAME and not by its shape**, which is the whole of what a shape lets a
        // program see.
        if (v instanceof SShape) return "<shape " + v.name + ">"

        // **ISO 8601 for an instant, and `1h 30m` for a duration** -- `js_rt_time.sysl` writes
        // both, and `time.sysl` writes them the same way for the other back end. The six
        // calendar kinds are `js_rt_cal.sysl`'s, on the same terms.
        if (v instanceof SInstant || v instanceof SDuration) return temporalText(v)
        if (isCalendar(v)) return calendarText(v)

        // **Between slashes and as it was written**, which is `render.sysl`'s rendering and the
        // only one a reader can paste back into a program.
        if (v instanceof SRegex) return regexText(v)

        // **By its generation and not its slot**, which is `render.sysl`'s rendering: the slot
        // is a position two sockets may hold one after the other and the generation names one.
        if (v instanceof SSocket) return "<socket " + v.gen + ">"

        // **A child is shown by its process id**, which is the one number about it that means
        // anything outside this program: it is what `ps` and `kill` are written with.
        if (v instanceof SChild) {
            try {
                return "<child " + $b.$childPid(v) + ">"
            } catch (e) {
                return "<child 0>"
            }
        }

        if (v instanceof SChannel) return "<channel>"

        // **An actor by its number and a message by that number and the handler's name**, which
        // is `render.sysl`'s `<actor 3>` and `<message 3.total>` word for word: what a reader
        // wants to know about `c.total` is which actor and which name.
        if (v instanceof SActor) return "<actor " + v.id + ">"
        if (v instanceof SMessage) return "<message " + v.id + "." + v.name + ">"

        // **By the constructor name the host offers, and `<external>` where it offers none.** The
        // interpreter prints the second of those always, having no host to ask. It is a debugging
        // sentence in both: nothing about a host value is readable, so a program that wants a
        // field asks for the field.
        if (v instanceof SExt) {
            const named = extName(v)

            return named === "" ? "<external>" : "<external " + named + ">"
        }

        // **`<WeakMap>` and `<WeakRef>` with nothing in them, which is `render.sysl`'s
        // rendering and the only honest one**: what is in a weak map is the collector's to
        // change, and holding a target long enough to print it is the one thing a weak reference
        // promises not to do.
        if (v instanceof WeakMap) return "<WeakMap>"
        if (v instanceof WeakRef) return "<WeakRef>"

        if (v instanceof Promise) return "<promise>"
        if (isGen(v)) return "<generator>"
        if (typeof v === "function") return "<function>"

        return "<value>"
    }

    // **`text`/`show` are the PROGRAM's printers and `plain`/`plainShow` are the DIAGNOSTICS'.**
    // The split is the interpreter's `printed` against `value_text` and it exists for one reason:
    // a message about a fault may not run the program's own code to render its values, because a
    // `toString` can fault in turn and the second fault is the one the reader would be shown.
    //
    // **The two back ends have to draw the line in the SAME place**, and for one release they did
    // not: this file had the hook inside `write` with no way to turn it off, so `no arm of this
    // match applies to $150` under node was `... to Money(cents = 150)` under the interpreter.
    // Every caller below says which of the two it is.
    const text = (v) => write(v, false, [], true)
    const show = (v) => write(v, true, [], true)
    const plain = (v) => write(v, false, [], false)
    const plainShow = (v) => write(v, true, [], false)

    // The engine's own way of writing a line, taken NOW rather than when it is needed.
    //
    // **A BROWSER'S `print` IS THE PRINT DIALOG AND NOT A WRITER**, and reaching for it made a
    // page's every `print("hi")` ask the user which printer to use and write nothing. quickjs is
    // why this looks at `globalThis.print` at all -- that is quickjs's writer, and it has no
    // relation to the window method of the same name -- so **a document is what tells the two
    // apart**: a host with one is a page, and a page has a console.
    //
    // **The reason this was taken NOW is gone and the habit is kept anyway.** It used to be that
    // slate installed a global called `print` of its own, so a lookup deferred to write-time
    // would have found slate's and called itself forever; a builtin is a parameter of the
    // emitted program since 0.0.27 and nothing is installed at all. Reading the host once is
    // still right for the reason the timers are: what a host provides is settled before the
    // program starts.
    const enginePrint =
        (typeof globalThis.print === "function" && typeof globalThis.document === "undefined")
            ? globalThis.print.bind(globalThis)
            : (typeof console !== "undefined" ? (line) => console.log(line) : null)

    // One of the engine's timer functions, wherever it keeps it.
    const engineTimer = (name) => {
        if (typeof globalThis[name] === "function") return globalThis[name].bind(globalThis)
        if (typeof os !== "undefined" && typeof os[name] === "function") return os[name].bind(os)

        return null
    }

    // node's module loader, however this program is being read.
    //
    // **`require` IS ABSENT UNDER ESM, AND A HOST WITHOUT IT IS NOT A HOST WITHOUT MODULES.**
    // node reads a `.js` file as CommonJS and `slate js p.sl | node -` as CommonJS too, so
    // `require` is a global for both; it is not one for a `.mjs` file or under `"type":
    // "module"`, and asking `typeof require === "function"` there answered *no* for a machine
    // with node's whole standard library on it. Every module this runtime reaches for -- the
    // file system, sockets, `node:crypto`'s Argon2, `node:zlib`'s zstd, `node:sqlite` -- refused
    // on that one question, and `slate test --js` never saw it because the tests are scripts.
    //
    // **`import.meta.url` IS WHAT THE DOCUMENTATION SAYS TO USE AND IT CANNOT BE WRITTEN HERE.**
    // It is a SyntaxError in a script, and this is one runtime that has to parse as both -- so
    // it would take a second prologue chosen by the output's extension, and the extension is not
    // what decides whether node reads a file as a module anyway. `process.getBuiltinModule` is
    // the door that needs no base: node's own reader for its own modules, reachable as an
    // ordinary property. It gives `node:module`, and `createRequire` off that -- based on the
    // working directory, which is where a program's own relative imports would resolve from --
    // is a `require` for everything else as well.
    const nodeRequire = (() => {
        if (typeof require === "function") return require

        if (typeof process === "undefined" || process.versions == null ||
                process.versions.node === undefined) return null

        if (typeof process.getBuiltinModule !== "function") return null

        try {
            const mod = process.getBuiltinModule("node:module")

            if (mod != null && typeof mod.createRequire === "function")
                return mod.createRequire(process.cwd() + "/")
        } catch (e) {
            // A node that will not hand over `node:module` still hands over the rest one at a
            // time, which is every module named in this runtime.
        }

        return (name) => process.getBuiltinModule(name)
    })()

    // Whether this is node, which is the one host that brings a file system and an environment
    // with it.
    const engineModule = (name) => {
        try {
            if (nodeRequire !== null) return nodeRequire(name)
        } catch (e) {
            // A host with a loader that refuses is a host without the module.
        }

        return null
    }

    // Where a program's output goes. A host -- the quickjs binding, a browser, node -- replaces
    // `write`, and everything printed is kept so that a host with no console can read it back.
    const host = {
        lines: [],

        write(line) {
            host.lines.push(line)

            if (host.echo && enginePrint !== null) enginePrint(line)
        },

        // Whether writing also reaches the engine's console. A host reading `lines` itself turns
        // this off.
        echo: true,

        // **The engine's timers, which is the whole of what slate's event loop needs from a
        // host.** node, a browser and quickjs-ng all supply these four; an embedder with a loop
        // of its own replaces them here and every timer, `sleep` and promise builtin follows.
        //
        // **Taken NOW rather than when they are needed**, for `enginePrint`'s reason and with a
        // sharper edge: the prelude installs every builtin onto `globalThis`, so `setTimeout`
        // there is slate's own a moment after this runs. Reading the global later would find
        // slate's and call itself.
        //
        // **`quickjs` puts its timers on `os` rather than on the global**, and has only the
        // one-shot pair; node and a browser have all four as globals. So the globals are asked
        // first, `os` is the fallback, and a `setInterval` that is not there at all is built out
        // of `setTimeout` by the builtin that wants one.
        //
        // A host with none of them leaves these null, and a program that reaches for a timer is
        // told there is no event loop rather than failing as an undefined name.
        setTimeout: engineTimer("setTimeout"),
        clearTimeout: engineTimer("clearTimeout"),
        setInterval: engineTimer("setInterval"),
        clearInterval: engineTimer("clearInterval"),
        setImmediate: engineTimer("setImmediate"),
        clearImmediate: engineTimer("clearImmediate"),

        // **The file system, which only node brings.** A browser has none and quickjs keeps a
        // different one on `std`; an embedder with a file system of its own puts it here and
        // every `slate:fs` builtin follows.
        fs: engineModule("fs"),

        // **node's module loader, and it is HERE because the runtime is emitted as more than one
        // scope.** `nodeRequire` above is a local of this block; the builtins that need
        // `node:crypto`, `node:zlib`, `node:sqlite` and `node:net` are in another, and a host
        // door is how the two have always talked. An embedder that replaces the file system
        // above replaces the same thing, and one that leaves this out gets what a browser gets:
        // the modules refuse, in their own sentences.
        require: nodeRequire,

        // This program's own environment, which is node's `process.env` and nothing anywhere
        // else. A host without one answers every variable as unset rather than complaining --
        // an environment with nothing in it is a thing that can be true.
        env: typeof process !== "undefined" && process.env !== undefined ? process.env : null,

        // What the script was asked to do, and it is the same list the interpreter hands a
        // program: everything after the program's own name.
        //
        // **Two hosts count that differently and the slice is where they are reconciled.** node's
        // `process.argv` opens with the executable and the script, so the program's own arguments
        // start at two; quickjs's `scriptArgs` opens with the script alone, so they start at one.
        // A host with neither has no command line, and an empty list is the honest answer -- a
        // browser was not asked anything.
        args: typeof process !== "undefined" && Array.isArray(process.argv) ? process.argv.slice(2)
            : typeof scriptArgs !== "undefined" && Array.isArray(scriptArgs) ? scriptArgs.slice(1)
            : [],

        // A clock that only ever goes forward, in milliseconds with a fraction.
        //
        // **`performance.now()` and never `Date.now()` as a stand-in.** The wall clock can be
        // set backwards, which is the whole reason `monotonic` is a builtin of its own -- so a
        // host with no such clock leaves this null and `monotonic` says it has none, rather than
        // quietly becoming the thing it exists not to be.
        monotonic: typeof performance !== "undefined" && typeof performance.now === "function"
            ? () => performance.now() : null,

        // **What the host provides ITSELF, which is what `hostHas` answers about.** These are
        // not features slate needs -- it has its own compressor, its own fetch and, over a
        // socket, its own WebSocket. They are the cases where the host's implementation is the
        // ONLY one available, because a browser has no socket to build on: a module written in
        // slate asks `hostHas` and takes whichever of its two paths this host can run.
        //
        // **Taken NOW rather than read when they are wanted**, which is the timers' rule and
        // costs nothing: what a host provides is settled before the program starts, and a
        // record built once is one place to look when a name is missing.
        //
        // **Compression is two globals and one question.** `hostHas("compression")` asks whether
        // this host compresses, and a host with a `CompressionStream` and no
        // `DecompressionStream` does not.
        webSocket: typeof WebSocket === "function" ? WebSocket : null,
        compression: typeof CompressionStream === "function" ? CompressionStream : null,
        decompression: typeof DecompressionStream === "function" ? DecompressionStream : null,
        // **BOUND TO THE GLOBAL OBJECT, because a page's `fetch` is a METHOD of the window.**
        // A browser refuses `fetch` called on anything else with `TypeError: Illegal
        // invocation`, and a name kept in this record is called as `$.host.fetch(...)` --
        // whose receiver is the record. node's never looks at its receiver, so the
        // unbound spelling works on one JavaScript host and fails on every other.
        fetch: typeof fetch === "function" ? fetch.bind(globalThis) : null,
        // What `fetch`'s `timeout` abandons a request with. Every host with a `fetch` has one.
        abortController: typeof AbortController === "function" ? AbortController : null,

        // **The document is here for `host()` and not for `hostHas`.** Nothing in the language
        // reaches a page any more -- the document is a package written over `external` -- so
        // what is left of this is the one question a program asks for itself: whether it is
        // running in a browser or under node.
        document: typeof document !== "undefined" && document !== null ? document : null,

        // Stopping with a status. A host that cannot stop leaves this null, and the builtin says
        // so rather than pretending the program ended.
        exit: typeof process !== "undefined" && typeof process.exit === "function" ? (n) => process.exit(n)
            : typeof std !== "undefined" && typeof std.exit === "function" ? (n) => std.exit(n)
            : null
    }

    // -- arithmetic -----------------------------------------------------------------------------------

    const bothInt = (a, b) => isInt(a) && isInt(b)
    const asReal = (v) => (isInt(v) ? Number(v) : v)

    const arith = (op, a, b) => {
        if (op === "+" && isStr(a) && isStr(b)) return a + b

        if (isNum(a) && isNum(b)) {
            // **NOTHING HERE WRAPS ANY MORE, WHICH IS THE WHOLE OF WHAT THE JAVASCRIPT BACK
            // END HAD TO CHANGE.** An integer was always a `BigInt` on this host and every
            // one of these answers used to be wrapped back to 64 bits by `i64`, because that
            // was the language's rule. A slate integer grows instead, so the wrap comes off
            // and the host's own arithmetic IS the rule -- `BigInt` is arbitrary precision by
            // construction, which is why the interpreter is the side that needed a new value
            // kind and this side needed a deletion.
            if (bothInt(a, b)) {
                if (op === "+") return a + b
                if (op === "-") return a - b
                if (op === "*") return a * b
                // **`/` ANSWERS A REAL EVEN BETWEEN TWO INTEGERS**, so both sides leave
                // `BigInt` for the host's own number and the host's own division is the
                // rule -- which is where `1 / 0` being an infinity comes from. A `BigInt`
                // past what a double can name becomes an infinity in the conversion, which
                // is `to_real`'s answer in the interpreter.
                if (op === "/") return Number(a) / Number(b)

                // **`\` is the whole-number division and `BigInt`'s own `/` IS it** --
                // truncating toward zero, which is the half of `a == (a \ b) * b + a % b`
                // that `%` does not supply.
                if (op === "\\") {
                    if (b === 0n) fault("this divides by zero")

                    return a / b
                }
                if (op === "%") {
                    if (b === 0n) fault("this takes a remainder by zero")

                    return a % b
                }
                if (op === "&") return a & b
                if (op === "|") return a | b
                if (op === "^") return a ^ b
                if (op === "<<" || op === ">>") {
                    if (b < 0n) fault("a shift is by a number of places that is not negative, and this is by " + b)
                    if (op === "<<" && b > MaxShift) fault("a shift by " + b + " places would build a number of " + b + " bits, and slate stops at " + MaxShift)

                    return op === "<<" ? a << b : a >> (b > MaxShift ? MaxShift : b)
                }
            } else {
                const x = asReal(a)
                const y = asReal(b)

                if (op === "+") return x + y
                if (op === "-") return x - y
                if (op === "*") return x * y
                if (op === "/") return x / y
                if (op === "\\") fault("an integer division is of integers")
                if (op === "%") fault("a remainder is taken of integers")

                fault("`" + op + "` works on whole numbers, and a real is not one")
            }
        }

        // **An instant and a duration answer for themselves**, in `js_rt_time.sysl`. They are
        // tried here rather than folded into the arms above because what an operator means over
        // them depends on both sides: two instants subtract to a length and an instant and a
        // duration to a moment. `arith.sysl` puts the same call in the same place.
        const moved = temporalArith(op, a, b)

        if (moved !== undefined) return moved

        // The calendar's own, in `js_rt_cal.sysl`, tried second because its arithmetic is
        // written over the timeline's. **Two calls rather than one function** so that each file
        // keeps its subject; `arith.sysl`'s `temporal_arith` covers all eight kinds in one place
        // because sysl has no such split.
        const stepped = calendarArith(op, a, b)

        if (stepped !== undefined) return stepped

        // **Two sets are the set algebra**, which is Python's spelling of it: `|` a union, `&` an
        // intersection, `-` a difference and `^` a symmetric difference. `arith.sysl`'s
        // `set_arith` is the same table and the two must not drift. **Reached through `$b`**, the
        // seven operations being written once beside the methods that are their other names --
        // `js_rt_show.sysl` reaches `$b.$childPid` across the same seam.
        if (a instanceof SSet && b instanceof SSet) {
            if (op === "|") return $b.$setUnion(a, b)
            if (op === "&") return $b.$setIntersection(a, b)
            if (op === "-") return $b.$setDifference(a, b)
            if (op === "^") return $b.$setSymmetricDifference(a, b)
        }

        // **An object may answer for itself, and this is the LAST thing tried** -- so a hook can
        // never shadow what an operator already means. The interpreter's `overloaded` in
        // `arith.sysl` is the same rule and the two must not drift.
        const named = OPERATOR_METHODS[op]

        if (named !== undefined) {
            const answered = callHook(a, named, [b])

            if (answered !== NO_HOOK) return answered
        }

        fault("`" + op + "` does not apply to " + typeName(a) + " and " + typeName(b))
    }

    // The method an operator looks for on its LEFT operand: **the operator IS the method's
    // name**, so `+(self, o) = ...` in a class body and every `a + b` that reaches it read alike.
    // **The left decides and the right is never asked**, which is `a.equals(b)`'s rule already --
    // so there is no reflected form. `arith.sysl`'s `operator_method` is the same table and the
    // two must not drift.
    const OPERATOR_METHODS = { "+": "+", "-": "-", "*": "*", "/": "/", "\\": "\\", "%": "%" }

    // A sentinel, because a hook may legitimately answer `undefined`... which slate refuses to
    // store, but which a JavaScript function with no `return` produces. Telling "no hook here"
    // from "the hook said nothing" by value would conflate the two.
    const NO_HOOK = Symbol("no hook")

    // Call a hook on the left operand, with the receiver rule the rest of the language uses.
    //
    // **A method reached through a `proto` is handed the object and one stored on the object is
    // not** -- `SObj.lookup`'s second answer, which is what lets a class write `+(self, o)`
    // with the definition syntax every other member uses.
    const callHook = (a, name, extra) => {
        if (!(a instanceof SObj)) return NO_HOOK

        const [f, delegated] = a.lookup(name)

        if (typeof f !== "function") return NO_HOOK

        return call(f, delegated ? [a].concat(extra) : extra)
    }

    const compare = (op, a, b) => {
        const ordered = (x, y) => {
            if (op === "<") return x < y
            if (op === "<=") return x <= y
            if (op === ">") return x > y

            return x >= y
        }

        // **AN INTEGER AND A REAL ARE COMPARED WITHOUT CONVERTING EITHER, WHICH IS PYTHON'S
        // RULE AND IS FREE HERE.** JavaScript's relational operators over a `BigInt` and a
        // `Number` compare the two mathematically -- no rounding of the integer, no promotion
        // of the real -- so `pow(10, 30) < 1e30` answers what the interpreter's exact
        // comparison answers. Converting the integer with `asReal` first was right while an
        // integer fitted 64 bits and rounds away a million at the widths one may now reach.
        if (isNum(a) && isNum(b)) return ordered(a, b)
        if (isStr(a) && isStr(b)) return ordered(a, b)

        // Two instants order as moments and two durations as lengths; a moment and a length are
        // not ordered against each other at all.
        const timed = temporalCompare(op, a, b)

        if (timed !== undefined) return timed

        const dated = calendarCompare(op, a, b)

        if (dated !== undefined) return dated

        // **`<=` is a subset and `<` a strict one**, which is Python's reading of the four and
        // `setmap.sysl`'s `set_operator`. Two sets that share only some of their members order
        // no way at all, so all four can be false of one pair -- which is what a containment is
        // and not a defect in the comparison.
        if (a instanceof SSet && b instanceof SSet) {
            if (op === "<=") return $b.$setWithin(a, b, false)
            if (op === ">=") return $b.$setWithin(b, a, false)
            if (op === "<") return $b.$setWithin(a, b, true)
            if (op === ">") return $b.$setWithin(b, a, true)
        }

        // **The operator's own method is asked first**, a class that wrote `<` having said
        // exactly what `<` means for it.
        const own = callHook(a, op, [b])

        if (own !== NO_HOOK) return own

        // **`<=>` is the one-method form and answers all four.** A class writes it or the
        // comparisons and not both -- the parser refuses the pairing where it is written, so
        // reaching here means the class chose this one.
        const answered = callHook(a, "<=>", [b])

        if (answered !== NO_HOOK) {
            if (!isNum(answered))
                fault("`<=>` says how two values order, so it answers a number below, at or above zero -- and this one gave " + typeName(answered))

            return ordered(asReal(answered), 0)
        }

        fault("`" + op + "` does not apply to " + typeName(a) + " and " + typeName(b))
    }

    const neg = (v) => {
        if (isInt(v)) return -v
        if (isReal(v)) return -v

        // **`unary_-` and not `-`**, taking no other side: a type whose `-` has two operands
        // has said nothing about what `-v` should be. It is handed no second argument, which is
        // why `callHook` takes a list.
        const answered = callHook(v, "unary_-", [])

        if (answered !== NO_HOOK) return answered

        fault("`-` needs a number, and this is " + typeName(v))
    }

    const bitnot = (v) => {
        if (isInt(v)) return ~v

        fault("`~` needs a whole number, and this is " + typeName(v))
    }

    // -- equality --------------------------------------------------------------------------------------

    // Deep for arrays and objects, and coinductive on a cycle: a pairing already being compared
    // answers true, which is what stops `a == a` over a self-referential array from descending
    // forever.
    const same = (a, b, seen) => {
        // **`==` BETWEEN AN INTEGER AND A REAL IS `==` AND NOT `===`, WHICH IS THE ONE PLACE
        // JAVASCRIPT'S LOOSE EQUALITY IS THE RIGHT OPERATOR.** `1n == 1` compares the two
        // mathematically and `1n === 1` is false for every pair; converting the integer first
        // was right while it fitted 64 bits and rounds at the widths one may now reach. Both
        // operands are numbers by the test in front of it, so nothing else loose arrives here.
        if (isNum(a) && isNum(b)) return bothInt(a, b) ? a === b : a == b
        if (typeof a === "boolean" || typeof a === "string") return a === b
        // **The one special case in `==`: the two absences compare equal**, so `x == null` and
        // `x == undefined` are one question -- the interpreter's `same_plain` carries the
        // reasoning. JavaScript's own `==` would say the same here and `0 == null` besides, so
        // it is spelled out rather than borrowed: nothing else of loose equality is wanted.
        if (a === null || a === undefined) return b === null || b === undefined

        if (Array.isArray(a)) {
            if (!Array.isArray(b) || a.length !== b.length) return false
            if (a === b) return true

            for (const [x, y] of seen) if (x === a && y === b) return true

            seen.push([a, b])

            for (let i = 0; i < a.length; i++)
                if (!same(a[i], b[i], seen)) { seen.pop(); return false }

            seen.pop()

            return true
        }

        // **Bytes compare by CONTENTS, and against bytes only** -- a buffer does not equal the
        // array of the same numbers, for the reason a string does not equal the array of its
        // characters. Nothing in one is a value, so there is no seen-record and no descent.
        if (a instanceof SBytes) {
            if (!(b instanceof SBytes) || a.length !== b.length) return false
            if (a === b) return true

            const x = a.view()
            const y = b.view()

            for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return false

            return true
        }

        if (a instanceof SObj) {
            if (!(b instanceof SObj) || a.size !== b.size) return false
            if (a === b) return true

            for (const [x, y] of seen) if (x === a && y === b) return true

            seen.push([a, b])

            for (const [k, v] of a.entries()) {
                if (!b.hasKey(k)) { seen.pop(); return false }
                if (!same(v, b.getKey(k), seen)) { seen.pop(); return false }
            }

            seen.pop()

            return true
        }

        // **A temporal value is equal to one of its OWN kind naming the same thing, and to
        // nothing else** -- an instant and a duration holding one number are not equal, being
        // answers to different questions.
        if (a instanceof SInstant) return b instanceof SInstant && a.us === b.us
        if (a instanceof SDuration) return b instanceof SDuration && a.us === b.us

        const alike = calendarSame(a, b)

        if (alike !== undefined) return alike

        if (a instanceof SRange) {
            if (!(b instanceof SRange)) return false
            if (a.hasLo !== b.hasLo || a.hasHi !== b.hasHi || a.step !== b.step) return false

            const ax = a.hasLo && a.hasHi ? a.last() : (a.inclusive ? a.hi : a.hi - 1n)
            const bx = b.hasLo && b.hasHi ? b.last() : (b.inclusive ? b.hi : b.hi - 1n)

            return a.lo === b.lo && ax === bx
        }

        // **An external is compared by the value the HOST holds and never by the wrapper**, two
        // declarations of one path being two wrappers around one thing. JavaScript's own `===`
        // for an object is exactly this, and there is nothing structural to fall back on.
        if (a instanceof SExt) return b instanceof SExt && a.held === b.held

        // **One opaque type, and equal representations** -- never a bare representation, which is
        // a different kind. The interpreter's `same_plain` says the same.
        if (a instanceof SVeil) return b instanceof SVeil && a.kind === b.kind && same(a.rep, b.rep, seen)

        return a === b
    }

    // Whether a value equals a literal written in a pattern.
    //
    // **A pattern does not consult an object's `equals`**: a literal pattern is a shape test, asking
    // whether the subject IS five rather than whether something has been persuaded to say it is.
    const sameLiteral = (v, lit) => {
        if (isNum(v) && isNum(lit)) return bothInt(v, lit) ? v === lit : v == lit

        return v === lit
    }

    // Whether two values are the same OBJECT rather than the same shape -- `a.eq(b)`.
    //
    // **Only the kinds with a heap identity are compared by address.** A string, a number and a
    // boolean are immutable and nothing can observe which copy it holds, so `"a".eq("a")`
    // answering false would be a trap rather than a distinction.
    const identical = (a, b) => {
        if (a instanceof SObj || Array.isArray(a) || a instanceof SBytes ||
            typeof a === "function" || a instanceof Promise)
            return a === b

        return same(a, b, [])
    }

    // **The left side's `==` decides, and only the left side's** -- Java's rule for `a.equals(b)`.
    //
    // **`!=` is ALWAYS the negation of this and a class may not write one**, which the parser
    // refuses by name -- so there is no second hook here for `ne` to consult.
    //
    // **Everything without a hook is DEEP, a class instance included.** Identity for a nominal
    // value was built and then withdrawn; the interpreter's `same_in` carries the reasoning.
    const eq = (a, b) => {
        const said = callHook(a, "==", [b])

        if (said !== NO_HOOK) return truthy(said)

        return same(a, b, [])
    }

    // -- strings, counted in characters --------------------------------------------------------------

    // The fast path is the common one: a string of nothing but ASCII is its own character array.
    const wide = (s) => (/^[\x00-\x7f]*$/.test(s) ? null : Array.from(s))

    const strLen = (s) => {
        const cs = wide(s)

        return cs === null ? s.length : cs.length
    }

    const strAt = (s, i) => {
        const cs = wide(s)
        const n = cs === null ? s.length : cs.length
        const k = Number(i)

        if (k < 0 || k >= n) fault("the index " + k + " is outside a string of " + n + " characters")

        return cs === null ? s[k] : cs[k]
    }

    const strSlice = (s, lo, hi) => {
        const cs = wide(s)

        return cs === null ? s.slice(lo, hi) : cs.slice(lo, hi).join("")
    }

    // -- indexing ---------------------------------------------------------------------------------------

    // The bounds a range covers over a container of `n` things, with the ends it did not name taken
    // from that length.
    // The positions a stepped range picks out, in the order it covers them: `xs[0..<6 by 2]` is
    // every other one going up and `xs[5..0 by -1]` is the whole of it backwards. Both ends have
    // to be written, there being no length to take a stepped end from.
    const steppedPositions = (r, n) => {
        if (!r.hasLo || !r.hasHi)
            fault("a slice that steps needs a range with both ends, since a stepped end cannot be taken from what it is used on")

        const count = r.count()
        const out = []

        for (let i = 0n; i < count; i++) {
            const p = Number(r.at(i))

            if (p < 0 || p >= n) fault("this slice reaches " + p + ", which is outside something " + n + " long")

            out.push(p)
        }

        return out
    }

    const span = (r, n) => {
        if (!(r instanceof SRange)) fault("a slice is taken with a range, and this is " + typeName(r))

        const lo = r.hasLo ? Number(r.lo) : 0
        let hi = r.hasHi ? (r.inclusive ? Number(r.hi) + 1 : Number(r.hi)) : n

        if (lo < 0 || hi < lo || hi > n)
            fault("this slice runs from " + lo + " to " + hi + ", which is outside something " + n + " long")

        return [lo, hi]
    }

    // A byte a program wrote as a number, or the complaint about what it wrote instead. The
    // interpreter's `byte_of_value`, word for word.
    const wantByte = (v) => {
        if (!isInt(v) || !fitsI64(v)) fault("a byte is a whole number between 0 and 255, and this is " + typeName(v))

        const b = Number(v)

        if (b < 0 || b > 255) fault("a byte is between 0 and 255, and this is " + b)

        return b
    }

    const index = (t, k) => {
        // **A computed key on an external is a property by another spelling**, so it goes out as
        // a name and what comes back comes in by the same table a `.` read uses.
        if (t instanceof SExt) return inward(t.held[outward(k)])

        // **`o[k]` is `o.k` with the name worked out**, as in JavaScript: an inherited member, a
        // property and a universal method are found exactly as `field` finds them, and a key that
        // is not a string walks the same chain by the key itself. The interpreter's `read_at`.
        if (t instanceof SObj) return isStr(k) ? field(t, k) : foundByKey(t, k)[0]

        // **A string key on a builtin kind reads what `.` reads**, so `xs["length"]` is the
        // length; a name the kind does not have falls through to the indexing sentence below.
        if (isStr(k) && t !== null && t !== undefined
            && (builtinProperty(t, k) !== undefined || builtinMethod(t, k) !== undefined))
            return field(t, k)

        if (Array.isArray(t)) {
            if (k instanceof SRange) {
                if (k.step !== 1n) return steppedPositions(k, t.length).map((p) => t[p])

                const [lo, hi] = span(k, t.length)

                return t.slice(lo, hi)
            }

            if (!isInt(k) || !fitsI64(k)) fault("an array is indexed by an integer, and this is " + typeName(k))

            const i = Number(k)

            if (i < 0 || i >= t.length)
                fault("the index " + i + " is outside an array of " + t.length)

            return t[i]
        }

        // **A byte reads as an integer and a range reads as more bytes**, which is the string's
        // arrangement rather than the array's -- there being no byte type to hand one back as. A
        // stepped range is refused, as it is in the interpreter.
        if (t instanceof SBytes) {
            if (k instanceof SRange) {
                if (k.step !== 1n)
                    fault("a slice of bytes does not step -- `b.toArray()` is the array that does")

                const [lo, hi] = span(k, t.length)

                return bytesOf(t.view().slice(lo, hi))
            }

            if (!isInt(k)) fault("bytes are indexed by an integer, and this is " + typeName(k))

            const i = Number(k)

            if (i < 0 || i >= t.length) fault("the index " + i + " is outside " + t.length + " bytes")

            return BigInt(t.at(i))
        }

        if (isStr(t)) {
            if (k instanceof SRange) {
                if (k.step !== 1n)
                    return steppedPositions(k, strLen(t)).map((p) => strSlice(t, p, p + 1)).join("")

                const [lo, hi] = span(k, strLen(t))

                return strSlice(t, lo, hi)
            }

            if (!isInt(k)) fault("a string is not indexed by " + typeName(k))

            return strAt(t, k)
        }

        fault(typeName(t) + " cannot be indexed")
    }

    // `o[k]` for a key that is not a string, and whether a `proto` answered -- the interpreter's
    // `found_by_key` in `member.sysl`, which is what decides a receiver at `o[k](a)`.
    const foundByKey = (t, k) => {
        for (let up = t, depth = 0; ; ) {
            if (up.hasKey(k)) return [up.getKey(k), depth > 0]

            const next = up.getName("proto")

            if (!(next instanceof SObj)) return [undefined, false]

            depth += 1

            if (depth >= MaxProtoDepth)
                fault("this object's `proto` chain is more than " + MaxProtoDepth +
                    " deep, which means it is a circle -- looking up a key in it would never finish")

            up = next
        }
    }

    // `k in o`: whether `o[k]` would find a member, read and run nothing. The interpreter's
    // `member_in`, case for case -- a `get` is asked whether it is there and never called.
    const memberIn = (k, t) => {
        if (t instanceof SExt) {
            const h = t.held

            return (typeof h === "object" && h !== null) || typeof h === "function" ? outward(k) in h : false
        }

        if (t instanceof SObj) {
            if (!isStr(k)) return foundByKey(t, k)[0] !== undefined

            return t.lookup(k)[0] !== undefined || t.lookup(GETMARK + k)[0] !== undefined
                || t.lookup(SETMARK + k)[0] !== undefined || builtinMethod(t, k) !== undefined
        }

        if (t === null || t === undefined || typeof t === "boolean" || typeof t === "number" || isInt(t))
            fault(typeName(t) + " has no members for `in` to ask about -- `in` asks an object, an array, a string or bytes")

        if (isStr(k)) return builtinProperty(t, k) !== undefined || builtinMethod(t, k) !== undefined

        const n = Array.isArray(t) || t instanceof SBytes ? t.length : isStr(t) ? strLen(t) : -1

        if (n < 0) fault("`in` asks " + typeName(t) + " about a name, and this is " + typeName(k))

        if (!isInt(k))
            fault("`in` asks " + typeName(t) + " about a position or a name, and this is " + typeName(k))

        return k >= 0n && k < BigInt(n)
    }

    // `o[k](a)`, which passes `o` exactly where `o.k(a)` would: a string key IS `o.k(a)`, and any
    // other key is an entry, handed the object where a `proto` answered. The interpreter's
    // `indexed_method`, and a missing entry is called as the nothing it is, as it was before.
    const methodAt = (t, k, args, names) => {
        if (isStr(k)) return method(t, k, args, names)

        if (!(t instanceof SObj)) return call(index(t, k), args, names)

        const [f, delegated] = foundByKey(t, k)

        if (f === undefined || !delegated) return call(f, args, names)

        const given = [t].concat(args)

        return call(f, names === undefined ? given : arranged(f, given, names, 1))
    }

    // `o.m?.(a)` and `o[k]?.(a)`: the member a guarded call calls, taken before an argument is
    // worked out, and how `o` is handed over -- or `null` where the member is nullish, which is
    // what the `?.` was written about. The interpreter's `taken_member`. The answer is
    // `[f, how]`: 0 calls `f` with what was written, 1 puts `o` in front, 2 is a builtin handed
    // `o` first, and 3 is a host method called on the host value.
    const memberAt = (t, k) => {
        const found = (f, how) => present(f) ? [f, how] : null

        if (!isStr(k)) {
            if (!(t instanceof SObj)) return found(index(t, k), 0)

            const [f, delegated] = foundByKey(t, k)

            return found(f, delegated ? 1 : 0)
        }

        if (t instanceof SExt) {
            const f = k === "new" ? t.held : t.held[k]

            return typeof f === "function" ? [f, 3] : found(inward(f), 0)
        }

        if (t instanceof SObj) {
            const [f, delegated] = t.lookup(k)

            if (f !== undefined) return found(f, delegated ? 1 : 0)

            // `field`'s order, so a class's own `get toString` wins over the universal one.
            const got = readProperty(t, k)

            if (got !== null) return found(got.held, 0)

            return found(builtinMethod(t, k), 2)
        }

        if (present(t) && !(t instanceof SActor) && builtinProperty(t, k) === undefined) {
            const m = builtinMethod(t, k)

            if (m !== undefined) return [m, 2]
        }

        return found(field(t, k), 0)
    }

    // The call of a member `memberAt` found under `t` and `k`, with `o` handed over as it said.
    const callMember = (t, k, m, args, names) => {
        const [f, how] = m

        if (how === 0) return call(f, args, names)

        if (how === 1) {
            const given = [t].concat(args)

            return call(f, names === undefined ? given : arranged(f, given, names, 1))
        }

        if (names !== undefined)
            fault(how === 2
                ? "this is a builtin, and a builtin's parameters have no names an argument can pick out"
                : "this is a method of the JavaScript host, and its parameters have no names an argument can pick out")

        if (how === 2) return f.apply(null, [t].concat(args))

        return k === "new" ? extCall(t, k, args) : inward(f.apply(t.held, args.map(outward)))
    }

    const setIndex = (t, k, v) => {
        if (t instanceof SExt) {
            t.held[outward(k)] = outward(v)

            return v
        }

        if (Array.isArray(t)) {
            if (!isInt(k) || !fitsI64(k)) fault("an array is indexed by an integer, and this is " + typeName(k))

            // **Asked before the bounds are**, so a frozen array answers what is actually wrong
            // rather than complaining about a position that was perfectly good.
            if (arrayShut(t)) fault(frozenArrayComplaint("xs[i] = v"))

            const i = Number(k)

            if (i < 0 || i >= t.length) fault("the index " + i + " is outside an array of " + t.length)

            t[i] = keep(v, "put in an array")

            return v
        }

        if (t instanceof SBytes) {
            if (!isInt(k)) fault("bytes are indexed by an integer, and this is " + typeName(k))

            if (t.frozen) fault(frozenBytesComplaint("b[i] = v"))

            const i = Number(k)

            if (i < 0 || i >= t.length) fault("the index " + i + " is outside " + t.length + " bytes")

            t.set(i, wantByte(v))

            return v
        }

        if (t instanceof SObj) {
            if (t.frozen) fault(writeRefusal(t, plain(k)))

            t.setKey(k, keep(v, "put in an object"))

            return v
        }

        fault(typeName(t) + " cannot be assigned to")
    }

    // -- properties --------------------------------------------------------------------------------

    // The keys a `get` and a `set` member are stored under, which are `value.sysl`'s.
    const GETMARK = "(get)"
    const SETMARK = "(set)"
    const VALMARK = "(val)"

    // The function one half of a property is, looked up exactly as a method is. `null` where there
    // is no such half.
    //
    // **A property belongs to the objects a class makes and not to the class**, so finding one as
    // this object's OWN field means it was asked of the class itself. The interpreter's
    // `accessor_of` says why, at length.
    const accessorOf = (t, mark, name) => {
        const [f, delegated] = t.lookup(mark + name)

        if (f === undefined) return null

        if (!delegated) {
            const whose = classOwnName(t)

            fault("`" + name + "` is a property of the objects `" + (whose === null ? "this class" : whose)
                + "` makes, and this is the class itself")
        }

        return f
    }

    // `c.area`, wrapped so that a getter answering `undefined` is told from there being no getter.
    // The interpreter's `read_property`, word for word.
    const readProperty = (t, name) => {
        const got = accessorOf(t, GETMARK, name)

        if (got !== null) return { held: call(got, [t]) }

        if (accessorOf(t, SETMARK, name) !== null)
            fault("`" + name + "` is write-only" + propertyOwner(t) + " -- it has a `set` and no `get`")

        return null
    }

    // `c.area = v`, answering whether a setter took it. An own field wins, which is the read rule
    // read backwards.
    const writeProperty = (t, name, v) => {
        // **A `val` MEMBER IS ASKED ABOUT BEFORE THE OWN FIELD IS**, which is the interpreter's
        // `write_property` and for its reason: the own field is what the mistake would create,
        // so a check made after it would refuse the second write and take the first. Asked of
        // the whole chain, so an instance finds its class's mark and the class finds its own.
        if (t.lookup(VALMARK + name)[0] !== undefined) {
            // Asked of the chain first and of the object second, so one sentence names the class
            // whether the write went through an instance or through the class itself.
            const found = className(t)
            const whose = found === null ? classOwnName(t) : found

            fault("`" + name + "` is a `val` of " + (whose === null ? "its class" : "`" + whose + "`")
                + ", and a `val` does not change -- write `var " + name
                + "` in the class where each object is to have its own, or hold the new value in a name of your own")
        }

        if (t.hasName(name)) return false

        const set = accessorOf(t, SETMARK, name)

        if (set !== null) {
            call(set, [t, v])

            return true
        }

        if (accessorOf(t, GETMARK, name) !== null)
            fault("`" + name + "` is read-only" + propertyOwner(t) + " -- it has a `get` and no `set`")

        return false
    }

    const hasProperty = (t, name) =>
        accessorOf(t, GETMARK, name) !== null || accessorOf(t, SETMARK, name) !== null

    // -- the JavaScript host, which `external` names -------------------------------------------------

    // **The invariant is one sentence: no foreign value ever becomes a slate value except as one
    // of these.** Everything below is that sentence read in one direction or the other.
    //
    // `held` is what the host handed over and `receiver` is the object the path found it ON, so a
    // bare call has the receiver the host itself would have given it. A browser's `fetch` called
    // on anything but the window throws `Illegal invocation`, and every method of a host object
    // has the same fault waiting in it.

    // The name the host offers for what this holds, or `""` where it offers none.
    const extName = (v) => {
        const held = v.held

        if (held === null || held === undefined) return ""

        const ctor = held.constructor

        return ctor === null || ctor === undefined || typeof ctor.name !== "string" ? "" : ctor.name
    }

    // A slate value on its way OUT to the host.
    //
    // **An array and an object are COPIED.** slate's array is the host's array and slate's object
    // is a table this runtime owns, so handing either straight out would put slate's own
    // representation where the host can write to it -- and a `fields` map is not something an API
    // can read. The copy is one pass over what was being handed over anyway.
    const outward = (v) => {
        if (v === null || typeof v === "boolean" || typeof v === "string" || typeof v === "number")
            return v

        // **A count that cannot be a JavaScript number EXACTLY is a fault rather than a rounding**,
        // which is the rule slate keeps everywhere else it converts.
        if (typeof v === "bigint") {
            const n = Number(v)

            if (!Number.isSafeInteger(n))
                fault("`" + v + "` is too large to hand to JavaScript exactly -- a JavaScript number carries whole numbers up to 2^53")

            return n
        }

        if (v instanceof SExt) return v.held
        if (Array.isArray(v)) return v.map(outward)

        if (v instanceof SObj) {
            const made = {}

            for (const [k, held] of v.entries()) {
                if (typeof k !== "string")
                    fault("an object handed to JavaScript is read by its keys, and this one has " + typeName(k) + " for a key")

                made[k] = outward(held)
            }

            return made
        }

        if (v instanceof Promise) return v.then(outward)

        // **A closure crosses as a function whose ARGUMENTS come inward**, so a callback is handed
        // exactly what the language guarantees and its answer goes back out by this same table.
        //
        // **It is given as many arguments as it declares and no more**, which is the rule slate's
        // own natives already follow: `map` hands a callback the element and the index, and a
        // one-parameter lambda takes it. JavaScript does the same thing everywhere -- its own
        // `map` calls back with three -- so a strict count here would refuse the ordinary case.
        if (typeof v === "function" && !isGen(v))
            return (...args) => outward(callback(v, args.map(inward), "the JavaScript host"))

        fault(typeName(v) + " does not cross to JavaScript -- what crosses is null, a boolean, a number, a string, an array, an object, a function, a promise and another external")
    }

    // A host value on its way IN.
    //
    // **Everything that is not a primitive stays external**, which is the invariant read backwards:
    // an array, an object and a function all come back as something read through the same
    // operations, so nothing the host owns can be mistaken for something slate owns.
    const inward = (v) => {
        // **`undefined` becomes `null`, and that is slate's rule rather than a convenience.** A
        // property that is absent and one holding `undefined` are the same read in JavaScript, so
        // nothing here can honestly say which happened -- and slate's own `undefined` may not be
        // stored anywhere, which is exactly what a value read off a host is for.
        if (v === undefined || v === null) return null
        if (typeof v === "boolean" || typeof v === "string" || typeof v === "bigint") return v

        // **A whole number is an integer**, which is the rule every other numeric surface in the
        // language already keeps rather than a new one: a length, a child count and a
        // `clientWidth` are counts a loop is about to be written over.
        if (typeof v === "number") return Number.isInteger(v) ? BigInt(v) : v

        // **A thenable becomes a promise so that `await` works on it**, which is the shape rule
        // `slate:gzip` and `fetch` already follow.
        if (typeof v.then === "function") return Promise.resolve(v).then(inward)

        return new SExt(v, undefined)
    }

    // What an `external` declaration binds. **The path is walked from the global object here**, so
    // a name that is not there is a fault at the declaration and not at the first use of it.
    const external = (path) => {
        let receiver = globalThis
        let held = globalThis

        for (const step of path.split(".")) {
            if (held === null || held === undefined)
                fault("this JavaScript host has no `" + path + "` -- there is nothing to read `" + step + "` from")

            receiver = held
            held = held[step]
        }

        if (held === undefined) fault("this JavaScript host has no `" + path + "`")

        return new SExt(held, receiver)
    }

    const extShow = (t) => {
        const named = extName(t)

        return named === "" ? "an external" : "the external " + named
    }

    const extCall = (t, name, args) => {
        // **`new` is how construction is spelled, which is the word slate uses for its own
        // classes** -- and the cost is that it is the one method name an external cannot reach.
        if (name === "new") {
            if (typeof t.held !== "function")
                fault(extShow(t) + " is not something `new` can construct with")

            return inward(new t.held(...args.map(outward)))
        }

        const f = t.held[name]

        if (typeof f !== "function")
            fault("`" + name + "` is not a method of " + extShow(t))

        // **The receiver is the object the method was found on**, which is what a host method
        // called on anything else throws about.
        return inward(f.apply(t.held, args.map(outward)))
    }

    // -- fields, methods and calls -------------------------------------------------------------------

    const field = (t, name) => {
        // **A property read answers what the host holds, crossing inward** -- a function among
        // them comes back external and UNBOUND, which is why a method is called as a method
        // rather than read out and called later.
        if (t instanceof SExt) return inward(t.held[name])

        if (t instanceof SObj) {
            const held = t.lookup(name)[0]

            // **`o.toString` on its own hands back the plain builtin**, exactly as `xs.map` does
            // -- it is the same value `o.toString()` calls, which is what makes the four methods
            // real rather than a syntax.
            if (held === undefined) {
                // **A PROPERTY IS ASKED FIRST OF THE TWO**, so a class that wrote `get toString`
                // is answered by its own -- the rule an ordinary field of that name already has.
                const got = readProperty(t, name)

                if (got !== null) return got.held

                const m = builtinMethod(t, name)

                if (m !== undefined) return m
            }

            return held
        }
        // **READING ANY NAME OFF A HANDLE ANSWERS A MESSAGE**, which is `index.sysl`'s one arm for
        // `ActorVal`: `c.total` sends nothing and asks nothing, it names an actor and one of its
        // handlers. Whether that name is a handler is the receiver's question and is answered
        // where the message arrives, so nothing is refused here.
        if (t instanceof SActor) return $actorMessage(t.id, name)

        // **The interpreter's sentence, word for word** (`method.sysl`'s `no_such_method`), and
        // it says what to write rather than what is missing: "`b` is not something null can do"
        // sends the reader to look at `b`, where what is wrong is one link earlier.
        if (t === null || t === undefined)
            fault("there is nothing here to read `" + name
                + "` from -- `?.` answers null where a value may be missing")

        // **A PROPERTY IS ASKED FIRST, AS IT IS ON AN SObj**, and it answers the value rather
        // than the function: `s.length` is the number where `xs.push` is the function `push`.
        // The interpreter's `read_field` is the same order.
        const p = builtinProperty(t, name)

        if (p !== undefined) return p(t)

        // **A builtin method is the free function of the same name**, handed back unbound exactly as
        // the interpreter hands it back: `xs.map` is `map`, and `map(xs, f)` is how it is then called.
        const m = builtinMethod(t, name)

        if (m !== undefined) return m

        // **`method`'s sentence, which is the interpreter's**: a READ of a missing name said
        // "an integer has no `nope`" here and "`nope` is not something an integer can do"
        // there, which is one fault with two spellings -- exactly what the call path was
        // aligned about in 0.0.25 and this path was not.
        fault("`" + name + "` is not something " + typeName(t) + " can do")
    }

    const setField = (t, name, v) => {
        if (t instanceof SExt) {
            t.held[name] = outward(v)

            return v
        }

        if (!(t instanceof SObj)) {
            // **A PROPERTY OF A BUILTIN KIND IS READ-ONLY AND THE COMPLAINT NAMES IT**, or the
            // reader is told a string has no fields and is left thinking `length` was never
            // there. The interpreter's `read_only_property` is this sentence, word for word.
            if (builtinProperty(t, name) !== undefined)
                fault("`" + name + "` is a read-only property of " + typeName(t))

            fault(typeName(t) + " has no field to assign to")
        }

        const kept = keep(v, "put in an object")

        if (writeProperty(t, name, kept)) return v

        if (t.frozen) fault(writeRefusal(t, "`" + name + "`"))

        t.setName(name, kept)

        return v
    }

    // **The fix is the whole of the sentence**, and it is the interpreter's word for word.
    const frozenComplaint = (what) =>
        what + " belongs to a data value, and a data value does not change -- `v with { " + what +
            ": ... }` answers a new one that differs there"

    // What a program gets for writing into a value it handed to `freeze`.
    //
    // **A SEPARATE SENTENCE FROM A DATA VALUE'S, and the reason is the fix each one names**:
    // told the data-value sentence about an object they built themselves, a reader goes looking
    // for a `data` declaration that is not there. The interpreter's `sealed_complaint`, word for
    // word.
    const sealedComplaint = (what) =>
        what + " belongs to a frozen value, and `freeze` is what closed it -- a copy made with" +
            " `with` or a spread is a new value that is free to change"

    // Which of the two a refused write gets, the object's own flag being the answer.
    const writeRefusal = (o, what) => o.dataValue ? frozenComplaint(what) : sealedComplaint(what)

    // The same for a collection, which names the OPERATION rather than a field -- `push` is not
    // a key and `clear` is not a member, so the object's shape of sentence reads as nonsense
    // about one. The interpreter's `frozen_kind_complaint` and its five callers, word for word.
    const frozenKindComplaint = (kind, name) =>
        "this " + kind + " is frozen, and `" + name + "` would change it -- `freeze` is what closed it"

    const frozenCopyComplaint = (kind, name, copy) =>
        frozenKindComplaint(kind, name) + ", and " + copy + " answers a copy that is free to change"

    const frozenArrayComplaint = (name) => frozenCopyComplaint("array", name, "`[...xs]`")
    const frozenBytesComplaint = (name) => frozenCopyComplaint("buffer", name, "`bytes(b.toArray())`")
    const frozenSetComplaint = (name) => frozenCopyComplaint("set", name, "`Set(s)`")
    const frozenMapComplaint = (name) => frozenCopyComplaint("map", name, "`Map(m)`")

    // **A weak map is the one frozen kind with no copy to point at**, a walk over one being the
    // very thing the kind refuses.
    const frozenWeakMapComplaint = (name) => frozenKindComplaint("weak map", name)

    // **AN ARRAY HAS NOWHERE TO CARRY A FLAG, so a WeakSet carries it for every array a program
    // freezes.** A slate array is a bare JavaScript array — that is what makes `map`, `slice`
    // and the rest the host's own and fast — so there is no field to set, and a property defined
    // on one would follow it through `JSON.stringify`, `Object.keys` and a spread.
    //
    // **The host's `Object.freeze` is deliberately NOT used**, and this is the whole reason the
    // registry exists: it is a silent no-op in sloppy mode and a `TypeError` in strict, so a
    // program would get one of two host sentences where slate promises its own on both hosts.
    //
    // **The COUNT is what keeps it free for every program that never freezes an array**: a
    // `WeakSet.has` on each `push` is a real cost, and an integer compare against zero is not.
    const SHUT_ARRAYS = new WeakSet()
    let shutArrays = 0

    const shutArray = (xs) => {
        if (!SHUT_ARRAYS.has(xs)) { SHUT_ARRAYS.add(xs); shutArrays += 1 }

        return xs
    }

    const arrayShut = (xs) => shutArrays !== 0 && SHUT_ARRAYS.has(xs)

    // Close an object to writing, leaving it where it stood. Only a data variant's `new` calls
    // it, which is why it sets BOTH flags: what it makes is a data value and not merely a shut
    // one.
    const seal = (o) => {
        if (o instanceof SObj) { o.frozen = true; o.dataValue = true }

        return o
    }

    // `o.m(a)`, which is where the receiver rule lives: an object's own field is called as it stands,
    // and one reached through a `proto` -- or answered by the builtin table -- takes the receiver in
    // front of the written arguments.
    // A call's arguments in the order the callee's PARAMETERS are written.
    //
    // **The names travel to the call and the parameters are read off the FUNCTION**, because
    // which parameter `b = 1` fills is a question about the callee and the callee is a value.
    // Every function this back end writes carries `$p` -- its parameter names, a rest one marked
    // with its dots -- and `$q`, how many of them a call must give.
    //
    // **A SKIPPED PARAMETER IS `undefined`, WHICH IS EXACTLY WHAT JAVASCRIPT'S OWN DEFAULT
    // TAKES.** slate's defaults are emitted as JavaScript defaults, so a hole needs no
    // machinery here at all: the callee fills it. That holds only because a slate program cannot
    // pass `undefined` itself, `keep` having refused it at the call.
    const arranged = (f, args, names, offset) => {
        const params = f.$p

        if (params === undefined)
            fault("this is a builtin, and a builtin's parameters have no names an argument can pick out")

        const rest = params.length > 0 && params[params.length - 1].startsWith("...")

        if (rest)
            fault(calleeNamed(f) + " gathers what it is given with `...`, so an argument to it cannot be named")

        const out = new Array(params.length).fill(undefined)
        const filled = new Array(params.length).fill(false)
        let next = 0

        for (let i = 0; i < args.length; i++) {
            const name = i < offset ? "" : names[i - offset]

            if (name === "") {
                // A positional argument past the last parameter is dropped, exactly as one in a
                // call with no names is.
                if (next < params.length) {
                    out[next] = args[i]
                    filled[next] = true
                    next++
                }
            } else {
                const slot = params.indexOf(name)

                if (slot < 0)
                    fault(calleeNamed(f) + " has no parameter called `" + name +
                        "` -- it takes " + paramList(params))

                if (filled[slot]) fault("this call gives `" + name + "` twice")

                out[slot] = args[i]
                filled[slot] = true
            }
        }

        for (let i = 0; i < (f.$q === undefined ? 0 : f.$q); i++)
            if (!filled[i])
                fault("this call gives nothing for `" + params[i] + "`, which has no default")

        let n = out.length

        while (n > 0 && !filled[n - 1]) n--

        out.length = n

        return out
    }

    // The parameters a function takes, as a sentence naming them.
    const paramList = (params) => {
        if (params.length === 0) return "none"

        return params.map((p, i) =>
            (i === 0 ? "" : i === params.length - 1 ? " and " : ", ") + "`" + p + "`").join("")
    }

    const method = (t, name, args, names) => {
        if (t instanceof SExt) {
            if (names !== undefined)
                fault("this is a method of the JavaScript host, and its parameters have no names an argument can pick out")

            return extCall(t, name, args)
        }

        if (t instanceof SObj) {
            const [f, delegated] = t.lookup(name)

            if (f === undefined) {
                // **The four universal methods are what an object falls back to**, after its own
                // fields and its whole proto chain have answered nothing.
                const m = builtinMethod(t, name)

                if (m !== undefined) {
                    if (names !== undefined)
                        fault("this is a builtin, and a builtin's parameters have no names an argument can pick out")

                    return m.apply(null, [t].concat(args))
                }

                // **A PROPERTY IS NOT A METHOD, AND THE SENTENCE SAYS SO RATHER THAN THAT THE
                // NAME IS MISSING.** Left to the complaint below, a reader is told `area` is not
                // a field of an object that plainly has one.
                if (hasProperty(t, name))
                    fault("`" + name + "` is a property, not a method -- it is read as `." + name
                        + "`, with no brackets after it")

                fault("`" + name + "` is not a field of this object, so there is nothing to call")
            }

            const given = delegated ? [t].concat(args) : args

            // **The receiver is parameter zero and is already in the list**, so the names cover
            // what was written and the arrangement is told how many slots are spoken for.
            return call(f, names === undefined ? given : arranged(f, given, names, delegated ? 1 : 0))
        }

        const m = builtinMethod(t, name)

        // **The interpreter's sentence, word for word** (`method.sysl`'s `no_method`). It said
        // "a string cannot `push`" here and "`push` is not something a string can do" there
        // until 0.0.25, which is one fault with two spellings -- and a program's own tests are
        // written against whichever back end its author ran.
        if (m === undefined) {
            // **A PROPERTY IS NOT A METHOD, AND THE SENTENCE SAYS SO** rather than that the kind
            // cannot do it -- the reader would otherwise go looking for a method they never
            // wanted. An object's `c.area()` is told the same above, in the same words.
            if (builtinProperty(t, name) !== undefined)
                fault("`" + name + "` is a property, not a method -- it is read as `." + name
                    + "`, with no brackets after it")

            fault("`" + name + "` is not something " + typeName(t) + " can do")
        }

        if (names !== undefined)
            fault("this is a builtin, and a builtin's parameters have no names an argument can pick out")

        return m.apply(null, [t].concat(args))
    }

    // What a function's parameters are called, and how many of them a call must give.
    //
    // **A JavaScript function does not reliably say what its parameters are named**, so every
    // function this back end writes is followed by one of these -- which is what lets a named
    // argument be placed against the callee at the call, exactly as the interpreter places one
    // against `ClosureObj.params`.
    const sig = (f, params, required, shown) => {
        f.$p = params
        f.$q = required
        f.$n = shown
    }

    // How a diagnostic refers to the function it is about, which is `callee_named` in
    // `value.sysl` and has to answer the same thing.
    //
    // **A JavaScript function's own `name` is the emitter's TEMPORARY for a lambda** -- `$t21`,
    // a name no reader wrote and none could grep for -- so the emitter says what to call it
    // instead, and says nothing for a lambda, a method or a generated `new`, exactly as the
    // interpreter has nothing to say for those three.
    const calleeNamed = (f) =>
        f.$n === undefined || f.$n === "" ? "this function" : "`" + f.$n + "`"

    // Whether the last parameter gathers what is left over.
    const gathers = (params) => params.length > 0 && params[params.length - 1].startsWith("...")

    // A NATIVE calling a function the PROGRAM supplied, which is `apply_callback` in
    // `index.sysl` and has to answer the same thing.
    //
    // **A callback that declares MORE than the native can supply is no longer refused.** Too
    // few is not an error anywhere now, so a parameter the native did not feed reads `undefined`
    // exactly as it would from a direct call. `native` is kept on the signature for every caller
    // that still names one, though nothing here reads it.
    const callback = (f, args, native) => call(f, args)

    const call = (f, args, names) => {
        // **A bare call keeps the receiver the PATH gave it**, which is what a browser's `fetch`
        // called on anything but the window throws about. One read back out of another external
        // has none, and is called on nothing, exactly as JavaScript would call it.
        if (f instanceof SExt) {
            if (typeof f.held !== "function")
                fault(extShow(f) + " is not something that can be called")

            if (names !== undefined)
                fault("this is a function of the JavaScript host, and its parameters have no names an argument can pick out")

            return inward(f.held.apply(f.receiver === undefined ? null : f.receiver, args.map(outward)))
        }

        // **An object with a `new` is callable, and the call IS that `new`** -- `Circle(3)` and
        // `Circle.new(3)` are one thing said two ways. **No receiver is passed however the field
        // was found**, where an ordinary method reached through a proto is handed one: a `new`
        // runs before there is an object to hand it, which is the interpreter's rule too.
        if (f instanceof SObj) {
            const maker = f.lookup("new")[0]

            if (typeof maker !== "function")
                fault("an object is called only where it has a `new`, and this one has none -- `class` and `data` write one, and an ordinary object is data rather than something to call")

            f = maker
        }

        if (typeof f !== "function") fault(typeName(f) + " is not something that can be called")

        // **NEITHER END IS CHECKED HERE ANY MORE, following the call rule both ways.** A
        // JavaScript function binds `undefined` for an argument it was not given, which is
        // exactly what a parameter the call left out should read as -- so too few needs no help
        // from this runtime and gets none.
        //
        // **TOO MANY IS NOT AN ERROR ON EITHER HOST: the surplus is dropped**, which is
        // JavaScript's own rule and `fit_arguments` in `index.sysl`. The slice is what keeps the
        // two hosts saying the same thing about what a call BINDS, a JavaScript function being
        // able to read the extras back out of `arguments` where a slate chunk never sees them.
        //
        // **One place, because every slate call comes through here.** A builtin carries no `$p`
        // and keeps its own argument reading; a named call is placed by `arranged`, which drops
        // its surplus its own way.
        if (f.$p !== undefined && names === undefined) {
            const takes = f.$p.length
            const variadic = gathers(f.$p)

            if (!variadic && args.length > takes) args = args.slice(0, takes)
        }

        for (const a of args) keep(a, "passed to a function")

        return f.apply(null, names === undefined ? args : arranged(f, args, names, 0))
    }

    // `f(...xs)`: the arguments arrive as an array and nothing else will do.
    //
    // **`walked` is `walked_into` in `setmap.sysl`**, and the two have to answer the same thing
    // about the same value or a spread means one thing here and another there. A STRING is
    // deliberately not on the list, on both back ends: `chars(s)` is how slate spells a string
    // as its characters, and `for` walking one is a separate question from `...` flattening it.
    const spread = (v) => walked(v, "`...`", "spreads")

    // What `await` may be given.
    //
    // **`await 5` IS 5, and it still yields a turn**, which is the interpreter's rule: its `Await`
    // pushes a resumption for a value that is not a promise rather than refusing it, so a program
    // cannot tell which of the two it was handed by watching what runs next. This back end
    // refused it outright, which made `await 0` -- the one-turn wait `slate:http` writes to let a
    // handler settle -- a fault under `slate js` and nothing under the interpreter.
    const awaited = (v) => (v instanceof Promise ? v : Promise.resolve(v))

    // -- iteration ---------------------------------------------------------------------------------

    function* rangeIter(r) {
        if (!r.hasLo || !r.hasHi) fault("`for` needs a range with both ends, since one left out would never finish")

        const count = r.count()

        for (let i = 0n; i < count; i++) yield r.at(i)
    }

    const iter = (v) => {
        if (Array.isArray(v)) return v.slice()

        // **A snapshot, as an array's is**, and every byte comes out as an integer -- which is
        // what `b[i]` answers, so a walk and an index agree.
        if (v instanceof SBytes) return Array.from(v.view(), (b) => BigInt(b))
        if (isStr(v)) return wide(v) === null ? v.split("") : Array.from(v)
        if (v instanceof SRange) return rangeIter(v)

        // **The sentence `gen_iter_next` says, word for word**: a walk that steps has nothing
        // to do with a source that answers promises, and `for await` is what reads one.
        if (isAsyncGen(v)) fault(ASYNC_GEN_WALK)
        if (isGen(v)) return v

        // **A snapshot, as an array's is**, so a walk that adds or removes does not skip an
        // entry or run forever -- and so the two back ends agree about what a `for` over one
        // yields while it is being changed.
        if (v instanceof SSet) return [...v.values()]
        if (v instanceof SMap) return [...v.entries()].map(([k, x]) => [k, x])

        // **`compose_iter_init`'s sentence, word for word**, the interpreter refusing the same
        // subject at the same place.
        fault("`for` walks an array, bytes, a string, a range, a generator, a set or a map, and this is " + typeName(v))
    }

    // What a `for await` left early calls on its subject, which is `iter_close.sysl`'s
    // `JumpIfNothingToClose` and the `return()` after it: a generator still running, or an
    // object with a `return` that is not `null`. Anything else has nothing to close. A plain
    // `for` needs none of this -- it is the host's own `for...of`, which closes what it walked.
    const closeIter = (v) => {
        if (isGen(v)) return method(v, "return", [])
        if (v instanceof SObj) {
            const r = v.lookup("return")[0]
            if (r !== undefined && r !== null) return method(v, "return", [])
        }
        return null
    }

    // Everything a value yields, as an array. **The one answer `...`, `array(x)` and `zip` all
    // read**, which is `walked_into` in `setmap.sysl` on the other side -- so the three
    // constructs cannot come to disagree about what one value gives, and neither can the two
    // back ends.
    //
    // **The VERB is the caller's**, because the sentence has to read as the construct that
    // wanted the walk: `...` *spreads* what `array` *takes*.
    const walked = (v, what, verb) => {
        if (Array.isArray(v)) return v.slice()
        if (v instanceof SBytes) return Array.from(v.view(), (b) => BigInt(b))

        if (v instanceof SRange) {
            if (!v.hasLo || !v.hasHi)
                fault(what + " needs a range with both ends, since one left out would never finish")

            return [...rangeIter(v)]
        }

        if (isAsyncGen(v)) fault(ASYNC_GEN_WALK)
        if (isGen(v)) return [...v]
        if (v instanceof SSet) return [...v.values()]
        if (v instanceof SMap) return [...v.entries()].map(([k, x]) => [k, x])

        fault(what + " " + verb +
            " an array, bytes, a range, a generator, a set or a map, and this is " + typeName(v))
    }

    // -- patterns -------------------------------------------------------------------------------------

    // A pattern is data, and this is the walk over it. It answers the values it bound, in the order
    // the names were written, or null where the pattern does not hold.
    const matchPattern = (v, pat, bound) => {
        const kind = pat[0]

        if (kind === "_") { bound.push(v); return true }
        if (kind === "*") return true
        if (kind === "t") return test(v, pat[1])
        if (kind === "v") return sameLiteral(v, pat[1])

        // An opaque type: made by that declaration, and a bare representation never is.
        if (kind === "veil") return v instanceof SVeil && v.kind === pat[1]

        // A range. `pat[4]` says the bounds were whole, which is what makes the value have to be.
        if (kind === "rng") {
            if (pat[4]) {
                if (typeof v !== "bigint") return false
                if (pat[1] !== null && v < pat[1]) return false

                // `pat[5]`/`pat[6]` are the number to count from and the step, present only where
                // a `by` was written. A step is a second test, not a narrower span.
                if (pat.length > 5 && (v - pat[5]) % pat[6] !== 0n) return false

                if (pat[2] === null) return true

                return pat[3] ? v <= pat[2] : v < pat[2]
            }

            if (typeof v !== "bigint" && typeof v !== "number") return false

            const x = Number(v)

            if (pat[1] !== null && x < pat[1]) return false
            if (pat[2] === null) return true

            return pat[3] ? x <= pat[2] : x < pat[2]
        }

        if (kind === "@") {
            bound.push(v)

            return matchPattern(v, pat[1], bound)
        }

        if (kind === "arr") {
            const items = pat[1]
            const open = pat[2]
            const rest = pat[3]

            // How many of the elements are not optional. An element with a default may be missing
            // and is left as `undefined` for the emitted code to fill in.
            const least = pat[4]

            if (!Array.isArray(v)) return false
            if (v.length < least) return false
            if (!(open || rest) && v.length > items.length) return false

            const taken = Math.min(v.length, items.length)

            for (let i = 0; i < taken; i++)
                if (!matchPattern(v[i], items[i], bound)) return false

            // A defaulted element the array did not reach still owns its slot in `bound`, or every
            // name after it would be read out of the wrong one.
            for (let i = taken; i < items.length; i++) bound.push(undefined)

            if (rest) bound.push(v.slice(taken))

            return true
        }

        if (kind === "obj") {
            const keys = pat[1]
            const values = pat[2]
            const optional = pat[3]

            if (!(v instanceof SObj)) return false

            // **Through the `proto` chain and not only the object's own fields**, which is what
            // `field_through` does for the machine: an interface written as `{ speak: function }`
            // is kept by a class whose method one link up supplies, and asking for own fields
            // would answer no to the case the type was written for.
            for (let i = 0; i < keys.length; i++) {
                // `lookup` walks `proto`, as the machine's `field_through` does, so an interface
                // kept by an inherited method is kept here too.
                const [held] = v.lookup(keys[i])

                if (held === undefined) {
                    if (!optional[i]) return false

                    // An absent field -- defaulted or marked `?` -- still owns its slot in
                    // `bound`, or every name after it would be read out of the wrong one.
                    bound.push(undefined)

                    continue
                }

                if (!matchPattern(held, values[i], bound)) return false
            }

            // `...rest`: a NEW plain object of the OWN fields `walkedKey` reports that the
            // pattern did not name -- the interpreter's `leftover_fields`, and bound last.
            if (pat[4]) bound.push(new SObj(Array.from(v.entries()).filter(([k]) => walkedKey(v, k) && !keys.includes(k))))

            return true
        }

        // **Every element, and an EMPTY container fits** -- every element of nothing fits
        // anything, which is the reading a test wants. An object's VALUES are walked; its keys
        // are the program's.
        if (kind === "every") {
            if (pat[1] === "array") {
                if (!Array.isArray(v)) return false

                for (const x of v) if (!matchPattern(x, pat[2], bound)) return false

                return true
            }

            if (!(v instanceof SObj)) return false

            for (const [, x] of v.entries()) if (!matchPattern(x, pat[2], bound)) return false

            return true
        }

        // `Set[T]` and `Map[K, V]`: every member is tested, and an empty one fits. The
        // interpreter's `HoldsPat` arm is the same walk.
        if (kind === "holds") {
            if (pat[1] === "Set") {
                if (!(v instanceof SSet)) return false

                for (const x of v.values()) if (!matchPattern(x, pat[2], bound)) return false

                return true
            }

            if (!(v instanceof SMap)) return false

            for (const [k, x] of v.entries()) {
                if (!matchPattern(k, pat[2], bound)) return false
                if (!matchPattern(x, pat[3], bound)) return false
            }

            return true
        }

        // **A function type asks two things and can ask no more**: is this callable, and is a
        // call of this size one it takes. Every function this back end writes carries `$p` and
        // `$q`; a builtin carries neither, and its parameters are nobody's business.
        //
        // **Only the FLOOR is a limit**, a call giving more than the function declares dropping
        // the surplus rather than faulting -- so a one-parameter function does take a call of
        // three. This is `FnPat` in `index.sysl` and has to answer the same thing.
        if (kind === "fn") {
            if (typeof v !== "function") return false

            const params = v.$p

            if (params === undefined) return true

            const want = pat[1]
            const required = v.$q === undefined ? params.length : v.$q

            return want >= required
        }

        if (kind === "or") {
            for (const alt of pat[1]) if (matchPattern(v, alt, bound)) return true

            return false
        }

        // Every part, left to right, each pushing what it bound onto the one flat list --
        // which is the order `pattern_names` gathered them in, and is the whole of the
        // agreement between the two.
        if (kind === "and") {
            for (const part of pat[1]) if (!matchPattern(v, part, bound)) return false

            return true
        }

        if (kind === "proto") return hasProto(v, pat[1])

        // A variant that declared no fields IS the value, so the test is identity with that one
        // object rather than a walk up a chain that would reach the data type instead.
        if (kind === "one") return v === pat[1]

        if (kind === "variant") {
            if (!hasProto(v, pat[1])) return false

            const keys = pat[2]
            const items = pat[3]

            if (items.length === 0) return true
            if (!(v instanceof SObj)) return false

            for (let i = 0; i < items.length; i += 1) {
                const [held] = v.lookup(keys[i])

                if (held === undefined) return false
                if (!matchPattern(held, items[i], bound)) return false
            }

            return true
        }

        // The nominal test and an ordinary object pattern, which is all `Point { x: a }` is.
        if (kind === "made") {
            if (!hasProto(v, pat[1])) return false

            return matchPattern(v, pat[2], bound)
        }

        return false
    }

    // The variant a data value was made by, or null where it is not one.
    //
    // **The frozen flag is asked first**, so an ordinary object a program happened to give a
    // maker as its `proto` prints as the object it is.
    const variantName = (v) => {
        if (!(v instanceof SObj) || !v.dataValue) return null

        const [tag] = v.lookup("(data)")

        return typeof tag === "string" ? tag : null
    }

    // The class an object is an INSTANCE of, if it is one.
    //
    // **The walk starts at the proto and not at the object**, which is the whole distinction
    // between a class and one of its instances: the tag is the class's own field. The
    // interpreter's `class_name` says the same.
    const className = (v) => {
        if (!(v instanceof SObj)) return null

        const up = v.getName("proto")

        if (!(up instanceof SObj)) return null

        const [tag] = up.lookup("(class)")

        return typeof tag === "string" ? tag : null
    }

    // The name of a CLASS, asked of the class object itself.
    const classOwnName = (v) => {
        if (!(v instanceof SObj)) return null

        const tag = v.getName("(class)")

        return typeof tag === "string" ? tag : null
    }

    // ` on Rect`, for a complaint about a property, or nothing where there is no class to name.
    // The interpreter's `property_owner`.
    const propertyOwner = (v) => {
        const named = className(v)

        if (named !== null) return " on " + named

        const own = classOwnName(v)

        return own === null ? "" : " on " + own
    }

    // Whether a key is a tag a declaration wrote rather than a field a program did.
    //
    // **An accessor's key is one of these**: `(get)area` is the mechanism behind `c.area` and not
    // a field anybody wrote, so a walk reporting it would be reporting the spelling.
    // **`(actor)`, `(handlers)` and `(transfer)` are three more of them**, and they are on this
    // list for the reason the first three are: an `actor` declaration carries the flag that tells
    // it from a class and the array of names another thread may reach, and neither is a field
    // anybody wrote. `(inits)` and `(target)` are how a subclass is built through its base
    // (`InitsTag` in `value.sysl`). The interpreter's `hidden_key` in `render.sysl` names the
    // same eight.
    const tagKey = (k) => k === "(data)" || k === "(class)" || k === "(shape)"
        || k === "(actor)" || k === "(handlers)" || k === "(transfer)"
        || k === "(inits)" || k === "(target)"
        || (typeof k === "string" && (k.startsWith("(get)") || k.startsWith("(set)") || k.startsWith("(val)")))

    // What `with` says about a field a data value never declared.
    //
    // **A data value's fields are the ones its declaration named, and `with` may only differ at
    // one of them.** `One(5) with { id: "3" }` answered `One(5, "3")` -- a variant carrying a
    // field its own type does not have. The interpreter's `unknown_field_complaint`, word for
    // word, because a program refused on one host and taken on the other is worse than either.
    const refuseUnknownField = (base, k) => {
        if (!base.dataValue) return
        if (!walkedKey(base, k)) return
        if (base.hasKey(k)) return

        const made = variantName(base)
        const named = made === null ? "this data value" : "`" + made + "`"

        fault(named + " has no field `" + plain(k) + "` -- a data value's fields are the ones its"
            + " declaration named, and `with` answers a copy that differs at one of them")
    }

    // Whether a walk over this object's fields reports this key.
    //
    // **`proto` is machinery on a NOMINAL value and an ordinary field on anything else**, which
    // is the line the printer already draws: `{ n: 1, proto: { m: 2 } }` is a plain object whose
    // `proto` a program wrote and prints as one, and `One(5)` reaches its maker through a `proto`
    // nobody wrote. `keys`, `values`, `entries`, `has` and `without` all read this one answer --
    // the interpreter's `walked_key`, word for word.
    const walkedKey = (o, k) => {
        if (tagKey(k)) return false
        if (k !== "proto") return true

        if (o.hasName("(class)") || o.hasName("(data)") || o.hasName("(shape)") || o.hasName("(actor)")) return false

        return variantName(o) === null && className(o) === null
    }

    // Whether the value's `proto` chain reaches this very object, which is what `p is Point` asks.
    //
    // **Identity, walked up the chain**: `==` on objects is structural, so it would answer true for
    // a different class holding the same fields.
    const hasProto = (v, cls) => {
        if (!(v instanceof SObj) || !(cls instanceof SObj)) return false

        let up = v
        let depth = 0

        for (;;) {
            const next = up.getName("proto")

            if (!(next instanceof SObj)) return false
            if (next === cls) return true

            depth += 1

            if (depth >= MaxProtoDepth) return false

            up = next
        }
    }

    const matched = (v, pat) => {
        const bound = []

        return matchPattern(v, pat, bound) ? bound : null
    }

    const matches = (v, pat) => matchPattern(v, pat, [])

    // What to say when a destructuring binding does not fit: `unpack_complaint` in `match.sysl`,
    // word for word, so a program faults with the same sentence on either back end. Each arm
    // names the shape the binding wanted and the thing that arrived.
    const unpackComplaint = (v, pat) => {
        const kind = pat[0]

        if (kind === "arr") {
            const items = pat[1]
            const needs = pat[4]

            if (!Array.isArray(v)) return "this binding takes an array apart, and this is " + typeName(v)

            if (v.length >= needs && v.length <= items.length)
                return "this array has the right number of elements, and one of them does not fit the binding"

            const least = pat[2] || pat[3] || needs !== items.length ? "at least " : ""

            return "this binding takes " + least + needs + (needs === 1 ? " element" : " elements") +
                " out of an array, and this one has " + v.length
        }

        if (kind === "obj") {
            const keys = pat[1]
            const optional = pat[3]

            if (!(v instanceof SObj)) return "this binding takes an object apart, and this is " + typeName(v)

            for (let i = 0; i < keys.length; i++) {
                if (optional[i]) continue

                if (v.lookup(keys[i])[0] === undefined)
                    return "this object has no field called `" + keys[i] + "`, which this binding takes out of it"
            }

            return "every field this binding names is there, and one of them does not fit"
        }

        return "this value does not fit the binding -- it is " + plainShow(v)
    }

    // A binding that has to hold: `val [a, b] = xs`, and a `for` over a pattern.
    const unpacked = (v, pat) => {
        const bound = matched(v, pat)

        if (bound === null) fault(unpackComplaint(v, pat))

        return bound
    }

    const noArm = (v) => fault("no arm of this match applies to " + plain(v))

    // The sentence a thrown value carries.
    //
    // **An object with a `message` is READ for that field rather than rendered**, which is what lets
    // a library put a fault back with `throw e` without turning it into
    // `{message: "...", line: 3, file: "..."}` -- a description of a fault rather than the fault.
    //
    // **Anything else is written the way `print` writes it, `toString` and all**, which is the
    // interpreter's rule in `run_frames.sysl` and is the one diagnostic in slate that runs a
    // program's own code. A hook that faults while it is being reported falls back to the
    // ordinary rendering, so the reader is told about the fault that was thrown rather than
    // about the one the `toString` raised on the way out.
    const thrownMessage = (v) => {
        if (isStr(v)) return v

        if (v instanceof SObj) {
            const said = v.getName("message")

            if (isStr(said)) return said
        }

        try {
            return text(v)
        } catch (e) {
            return plain(v)
        }
    }

    // What a `catch` binds: an ordinary object carrying the sentence, the line it was raised at and
    // the file it was in.
    //
    // **A thrown STRING becomes one too**, which is the interpreter's rule and is easy to get wrong:
    // `throw "gone wrong"` is caught as `{message: "gone wrong", line: 44, file: "p.sl"}` and not as
    // the string. A thrown value of any other kind is handed over AS ITSELF -- see `caughtAlone`.
    const faultObject = (message, line, file) =>
        new SObj([["message", message], ["line", BigInt(line)], ["file", file]])

    // **A release that faulted while this one was travelling rides along as `suppressed`.**
    // `disposeUsing` hangs the fault object it built on the signal that was already on its way
    // out, because that signal is the only thing the two have in common: the original is what
    // the program was told about and the release's own complaint is a field of it. A thrown
    // primitive carries nothing, which is why the property is read defensively.
    const withSuppressed = (e, o) => {
        if (e === null || typeof e !== "object") return o
        if (e.$suppressed === undefined) return o

        o.setName("suppressed", e.$suppressed)
        return o
    }

    // **A VALUE fault carries no `suppressed` and the interpreter draws the same line.** The field
    // belongs to the object a `catch` is handed, and for a value fault that object is the program's
    // own -- writing a field into it would change a value the program is still holding.
    const caught = (e) => {
        const held = caughtAlone(e)

        if (e instanceof Thrown && !isStr(e.value)) return held

        return withSuppressed(e, held)
    }

    // The sentence a fault SAYS, whatever kind it is -- what the interpreter's `signal_message`
    // answers. A value fault has no `message` field to read, so nothing may reach for one.
    const said = (e) => thrownMessage(caught(e))

    const caughtAlone = (e) => {
        // **A skip is not a fault and a `catch` does not get one.** `guarded` in the interpreter
        // matches `Fail` and only `Fail`; this is the same rule where the two hosts' machinery is
        // JavaScript's own `try`, and it is why `$suite` looks for a `Skipped` before asking here.
        if (e instanceof Skipped) throw e

        // **`exit` is the same rule again.** A `catch` between an `await` and the top gets offered
        // nothing, which is what keeps `exit` uncatchable across a promise exactly as it is where
        // it never crossed one.
        if (e instanceof Exited) throw e

        // **`throw v` HANDS THE VALUE OVER, and a string is the one exception.** A thrown string
        // has nothing in it a handler could sort on, so it keeps the fault object every `catch`
        // was given before faults could carry anything -- which is what leaves `e.message` meaning
        // what it always meant. Anything else travels whole, so `catch NotFound(id)` can ask what
        // went wrong rather than reading a sentence.
        if (e instanceof Thrown) return isStr(e.value) ? faultObject(e.value, e.line, e.file) : e.value
        if (e instanceof Fault) return faultObject(e.reason, e.line, e.file)

        // A JavaScript error from inside the runtime is still a fault a program can read.
        //
        // **A host `ReferenceError` for an unbound name is reworded to the interpreter's own
        // sentence.** Every JavaScript host phrases this the same way -- `NAME is not defined`,
        // with no punctuation around the name -- while the interpreter always writes the name in
        // backticks. Left alone, a `catch e -> print(e.message)` written once and run under both
        // back ends read two different sentences for the one fault; this is the one place every
        // `catch` in an emitted program passes through, so the reword covers all of them, an
        // actor's handler included.
        //
        // **And where the name is one the ENTRY file's top level binds, the sentence says where
        // the value belongs.** A worker runs every module the program imports and does not run
        // the entry file, so `LIMIT is not defined` on its own sends the reader hunting for a
        // spelling mistake in a line that is right. `ENTRY_BOUND` is filled by the emitted
        // declarations copy, and the words are `unbound_here`'s in `run_frames.sysl`.
        const spellingHint = (name) => {
            if (name === "len")
                return " -- slate has no `" + name + "` function: the length of a value is the property `x.length` (`x.size` for a Set or Map)"
            if (name === "length" || name === "size")
                return " -- `" + name + "` is a property in slate, not a function: write `x.length` (`x.size` for a Set or Map)"
            return ""
        }
        const said = String(e && e.message ? e.message : e)
        const unbound = e instanceof ReferenceError ? /^(\S+) is not defined$/.exec(said) : null

        if (unbound !== null) {
            const name = unbound[1]

            return faultObject(ENTRY_BOUND.has(name)
                ? "`" + name + "` is not defined -- the entry file's top level is not run inside an actor, and `" +
                    name + "` is bound there. Put it in a module the actor imports, or in the actor's own fields."
                : "`" + name + "` is not defined" + spellingHint(name), $line, $file)
        }

        return faultObject(said, $line, $file)
    }

    // Every name an entry file's top level binds, gathered from each declarations-only copy the
    // bundle carries. **A set rather than one list**, a suite being several programs whose copies
    // all run in the one worker.
    const ENTRY_BOUND = new Set()

    return {
        Fault, Thrown, Skipped, Exited, SObj, SSet, SMap, SRange, SShape, SSocket, SChild, SChannel, SActor, SMessage, SExt, external, host,
        SBytes, bytesOf, bytesLike,

        // **Whether `exit` is asking to stop the run `slate test --js` is driving.** `$suite`
        // turns this on for the file it is about to run; `B.exit` reads it to decide between
        // really stopping the process and raising `Exited` for `$suite` to report instead.
        enterTestMode() { $testMode = true },
        inTestMode: () => $testMode,

        // **What the entry file's top level would have bound**, written by the declarations-only
        // copy the worker runs, and read by `caught` to say where a value belongs.
        entryBound(names) { for (const n of names) ENTRY_BOUND.add(n) },
        i64, MaxShift, fitsI64, fault, truthy, present, keep, keepYielded, typeName, test, text, show, realText,
        isInt, isReal, isNum, isStr, isGen, isAsyncGen,
        arith, compare, neg, bitnot, eq, same: (a, b) => same(a, b, []), sameLiteral,
        strLen, strAt, strSlice, wide, span,
        index, setIndex, memberIn, methodAt, memberAt, callMember, field, setField, method, call, callback, spread, walked, awaited, iter, closeIter, seal,
        matched, matches, unpacked, noArm, caught, said, hasProto, variantName, plain, plainShow,
        className, classOwnName, tagKey, walkedKey, identical, callHook, NO_HOOK, sig,

        // **What `freeze` closed, and the sentences a write into it gets.** `$b` is a scope of
        // its own -- this block closes the one they are declared in -- so the builtins that
        // refuse a write reach them here, exactly as they reach `walkedKey`.
        shutArray, arrayShut,
        frozenArrayComplaint, frozenBytesComplaint, frozenSetComplaint, frozenMapComplaint,
        frozenWeakMapComplaint,

        // What a `type` declaration binds. **The pattern is walked and never read back out**, so
        // nothing downstream can grow to depend on the structure of a type.
        shape: (pat, name) => new SShape(pat, name),

        // **What a local holds before its declaration has run**, where a function written in
        // its block may read it first (`js_spell.sysl`). Such a read asks for this and falls back
        // to the outer binding, which is what the interpreter's lookup at call time finds. No
        // value a program makes can be it.
        unbound: Symbol("unbound"),

        // **The three conversions an opaque type is used through, the interpreter's `Veil`,
        // `Unveil` and `UnveilHome` word for word** (`veil.sysl`). Each leaves alone a value it
        // was not written for, which is what makes one written twice harmless.
        SVeil,
        veil: (kind, name, home, rep, v) =>
            (v instanceof SVeil && v.kind === kind) || !matchPattern(v, rep, []) ? v : new SVeil(kind, name, home, v),
        unveil: (kind, v) => (v instanceof SVeil && v.kind === kind ? v.rep : v),
        uh: (home, v) => (v instanceof SVeil && v.home === home ? v.rep : v),

        // The two makers for an actor's handle and a handler named on one, interned so that `==`
        // on either is identity. `js_rt_actor.sysl` is the only caller outside this block.
        actorHandle: $actorHandle, actorMessage: $actorMessage,


        // Where the program is, for a fault to name. The emitted code sets it a statement at a
        // time, and names the file by its index in the table below.
        //
        // **A program of several files stamps the file on every marker**, because a function
        // defined in one module and called from another has to say where it was written -- and a
        // marker in the caller has to put the caller's file back afterwards. A program of one
        // file says it once and leaves it.
        at(line, file) { $line = line; if (file !== undefined) $file = $files[file] },

        // The files, named once at the head of the program.
        files(names) { $files = names; $file = names[0] },

        // An array literal, which may hold no `undefined`.
        arr(items) {
            for (const v of items) keep(v, "put in an array")

            return items
        },

        // An object literal, in the order its keys were written.
        obj(entries) {
            for (const [, v] of entries) keep(v, "put in an object")

            return new SObj(entries)
        },

        range(lo, hi, inclusive, step) {
            if (lo !== undefined && !isInt(lo)) fault("a range runs between integers, and this is " + typeName(lo))
            if (hi !== undefined && !isInt(hi)) fault("a range runs between integers, and this is " + typeName(hi))
            if (step !== undefined && !isInt(step)) fault("the step of a range is a whole number, and this is " + typeName(step))

            // A written zero was refused where it stood; this is the one that was worked out.
            if (step === 0n)
                fault("a range steps by 0, so it would never reach its end -- `by` takes a step that moves")

            return new SRange(lo === undefined ? 0n : lo, hi === undefined ? 0n : hi,
                inclusive, lo !== undefined, hi !== undefined, step === undefined ? 1n : step)
        },

        // `x with { a: 1 }`: a new object, the base's fields first.
        withFields(base, entries) {
            if (!(base instanceof SObj)) fault("`with` takes an object, and this is " + typeName(base))

            const made = SObj.copy(base)

            for (const [k, v] of entries) refuseUnknownField(base, k)
            for (const [k, v] of entries) made.setKey(k, keep(v, "put in an object"))

            // **A copy of a data value is a data value and a copy of a FROZEN one is not**,
            // which is the interpreter's rule: `freeze` closed one value, and a `with` that
            // answered another closed one would leave a program no way back.
            made.dataValue = base.dataValue
            made.frozen = base.dataValue

            return made
        },

        // **`spread` picks the words and changes nothing else**, which is the machine's rule for the
        // same operation: `{ ...o }` and `a with b` are one thing, and a message naming the spelling
        // the reader did not write sends them looking for it.
        //
        // **`{ ...null }` is a fault and not `{}`**, where JavaScript ignores a null spread. slate's
        // rule is that a value which does not fit is a fault rather than an `undefined` that
        // travels, and the two back ends have to agree about it -- `{ ...maybeProps }` is written
        // constantly.
        withAll(base, other, spread) {
            if (!(base instanceof SObj)) fault("`with` copies an object, and this is " + typeName(base))

            if (!(other instanceof SObj))
                fault(spread
                    ? "`...` spreads the fields of an object, and this is " + typeName(other)
                    : "`with` copies the fields of an object, and this is " + typeName(other))

            const made = SObj.copy(base)

            for (const [k] of other.entries()) refuseUnknownField(base, k)
            for (const [k, v] of other.entries()) made.setKey(k, v)

            made.dataValue = base.dataValue
            made.frozen = base.dataValue

            return made
        },

        // `[v; n]`, an array of one value repeated.
        repeat(v, n) {
            if (!isInt(n)) fault("a repeat count is an integer, and this is " + typeName(n))
            if (n < 0n) fault("a repeat count is not negative, and this is " + n)

            return new Array(Number(n)).fill(keep(v, "put in an array"))
        },

        // The pieces of `s"..."`, each rendered as a program prints it.
        interp(pieces) {
            let out = ""

            for (const p of pieces) out += typeof p === "string" ? p : text(p)

            return out
        }
    }
})()

// -- the temporal values -----------------------------------------------------------------------

// A point on the timeline, and an exact length of one. `value.sysl`'s `InstantVal` and
// `DurationVal`, spelled in JavaScript.
//
// **Both carry MICROSECONDS in a `BigInt`, which is the number the interpreter carries**, so the
// two back ends hold one value and not two representations of it. A `number` would have been the
// JavaScript instinct and is wrong twice over: it stops being exact at 2^53 microseconds, which
// is the year 2255, and `epochMicros` would then answer a real where the interpreter answers an
// integer.
//
// **THE CLOCK IS MILLISECONDS AND THE VALUE IS MICROSECONDS, on both hosts.** `Date.now()` has
// nothing finer to give, so `now()` here is a whole number of milliseconds -- and the
// interpreter truncates its own reading to match, because a program that prints a timestamp
// would otherwise show six fractional digits under one back end and three under the other. What
// a program BUILDS with `epochMicros` keeps every digit on both.
class SInstant {
    constructor(us) { this.us = us }
}

class SDuration {
    constructor(us) { this.us = us }
}

const US_PER_MILLI = 1000n
const US_PER_SECOND = 1000000n
const US_PER_MINUTE = 60000000n
const US_PER_HOUR = 3600000000n
const US_PER_DAY = 86400000000n

// Division that rounds DOWN rather than toward zero, which is what a day count off a negative
// instant needs: 1969 is `-1` days from the epoch and not `0`.
const floorDiv = (a, b) => {
    const q = a / b

    return a % b !== 0n && (a < 0n) !== (b < 0n) ? q - 1n : q
}

// -- how a temporal value prints ---------------------------------------------------------------

// ISO 8601 for an instant and `1h 30m` for a duration, which is `time.sysl`'s `temporal_text`
// and `duration_text` said again here.
//
// **A second copy of a rendering is a thing that drifts, and what stops it is a test rather than
// a shared implementation**: `tests/js/p17.sl` prints instants and durations of every shape on
// both back ends and compares the output, so a change to one that is not made to the other fails
// in the suite rather than in somebody's log file.
const temporalText = (v) => v instanceof SInstant ? instantText(v.us) : durationText(v.us)

const instantText = (us) => {
    const day = floorDiv(us, US_PER_DAY)

    return civilText(day) + "T" + clockText(us - day * US_PER_DAY) + "Z"
}

// A day count as `YYYY-MM-DD` in the proleptic Gregorian calendar -- Howard Hinnant's algorithm,
// which is `sysl.time`'s `civil_from_days` line for line.
//
// **A `Date` was the other way and is not used, though it would have been shorter.** It has no
// microseconds, so the fraction below would have had to be worked out here anyway; it answers
// `NaN` for a day more than a hundred million from the epoch, which `epochSeconds` can reach;
// and its answer is the host's reading of a calendar where this one is the interpreter's. Nine
// lines of arithmetic agree with the other back end by construction, which is what this file is
// for.
const civilText = (d) => {
    const z = d + 719468n
    const era = floorDiv(z, 146097n)
    const doe = z - era * 146097n
    const yoe = (doe - doe / 1460n + doe / 36524n - doe / 146096n) / 365n
    const doy = doe - (365n * yoe + yoe / 4n - yoe / 100n)
    const mp = (5n * doy + 2n) / 153n
    const day = doy - (153n * mp + 2n) / 5n + 1n
    const month = mp < 10n ? mp + 3n : mp - 9n
    const year = yoe + era * 400n + (month <= 2n ? 1n : 0n)

    return yearText(year) + "-" + twoDigits(month) + "-" + twoDigits(day)
}

// A year as four digits, the sign counting as one of them where there is one -- `%04d`, which is
// what the other back end writes it with.
const yearText = (y) => y < 0n ? "-" + (-y).toString().padStart(3, "0") : y.toString().padStart(4, "0")

const twoDigits = (n) => n.toString().padStart(2, "0")

// A time of day, always with its seconds and with its fraction only where there is one.
const clockText = (us) => {
    const h = twoDigits(us / US_PER_HOUR)
    const m = twoDigits(us % US_PER_HOUR / US_PER_MINUTE)
    const s = twoDigits(us % US_PER_MINUTE / US_PER_SECOND)
    const fraction = us % US_PER_SECOND

    if (fraction === 0n) return h + ":" + m + ":" + s

    // Trailing zeros are dropped, so a millisecond reads as `.001` rather than `.001000`.
    let digits = ""
    let scale = US_PER_SECOND / 10n
    let left = fraction

    while (left !== 0n) {
        digits += (left / scale).toString()
        left = left % scale
        scale = scale / 10n
    }

    return h + ":" + m + ":" + s + "." + digits
}

// A length of timeline as a person states one: `1h 30m`, `-45s`, `0s`. **Not ISO 8601's
// `PT1H30M`**, which is a format for machines, and nothing reads this back.
const durationText = (us) => {
    if (us === 0n) return "0s"

    let left = us < 0n ? -us : us
    let out = us < 0n ? "-" : ""

    const h = left / US_PER_HOUR

    left = left % US_PER_HOUR

    const m = left / US_PER_MINUTE

    left = left % US_PER_MINUTE

    const s = left / US_PER_SECOND

    left = left % US_PER_SECOND

    let first = true

    const part = (text) => {
        if (!first) out += " "

        out += text
        first = false
    }

    if (h !== 0n) part(h + "h")
    if (m !== 0n) part(m + "m")
    if (s !== 0n) part(s + "s")

    // Sub-second remainders are written in milliseconds where they are whole ones, since that is
    // the unit a person reading a duration is nearly always working in.
    if (left !== 0n) part(left % US_PER_MILLI === 0n ? left / US_PER_MILLI + "ms" : left + "us")

    return out
}

// -- what an operator means over them ----------------------------------------------------------

// **`undefined` for a pair this has nothing to say about**, which is what lets the core try this
// and then try an object's own hook, in that order. The interpreter's `temporal_arith` answers
// an `Option` for the same reason and the two must not drift.
const temporalArith = (op, a, b) => {
    if (a instanceof SInstant) {
        // A duration moves an instant along the timeline; the difference of two instants is the
        // length between them.
        if (b instanceof SDuration) return op === "+" ? new SInstant($.i64(a.us + b.us))
            : op === "-" ? new SInstant($.i64(a.us - b.us)) : undefined

        if (b instanceof SInstant) return op === "-" ? new SDuration($.i64(a.us - b.us)) : undefined

        return undefined
    }

    if (a instanceof SDuration) {
        if (b instanceof SDuration) return op === "+" ? new SDuration($.i64(a.us + b.us))
            : op === "-" ? new SDuration($.i64(a.us - b.us)) : undefined

        // **Addition is the one temporal operator that commutes**, so a duration on the left of
        // an instant is the same moment. Subtraction is not: an instant taken from a length is
        // not a thing.
        if (b instanceof SInstant) return op === "+" ? new SInstant($.i64(a.us + b.us)) : undefined

        if ($.isInt(b)) {
            if (op === "*") return new SDuration($.i64(a.us * b))

            if (op === "/") {
                if (b === 0n) $.fault("this divides a duration by zero")

                return new SDuration(a.us / b)
            }
        }

        return undefined
    }

    if ($.isInt(a) && b instanceof SDuration && op === "*") return new SDuration($.i64(a * b.us))

    return undefined
}

// The four orderings, over two values of one kind. **Two kinds are never ordered against each
// other**: a length is not before or after a moment.
const temporalCompare = (op, a, b) => {
    const pair = (a instanceof SInstant && b instanceof SInstant) ||
        (a instanceof SDuration && b instanceof SDuration)

    if (!pair) return undefined
    if (op === "<") return a.us < b.us
    if (op === "<=") return a.us <= b.us
    if (op === ">") return a.us > b.us

    return a.us >= b.us
}

// -- the calendar values -------------------------------------------------------------------

// `value.sysl`'s `DateVal`, `TimeVal`, `DateTimeVal`, `ZoneVal`, `ZonedVal` and `PeriodVal`,
// spelled in JavaScript.
//
// **Every number in them is a `BigInt`, which is what a slate integer is**, so a day count, a
// month count and a microsecond reading all come back out of a field reader as the integer the
// interpreter answers rather than as something that has to be converted at the boundary. The one
// exception is a zone's fixed offset, which is minutes and never leaves this file as a number.
class SDate {
    constructor(day) { this.day = day }
}

class STime {
    constructor(us) { this.us = us }
}

class SDateTime {
    constructor(day, us) { this.day = day; this.us = us }
}

// A zone: a region's rules, or a fixed offset from UTC.
//
// **`name` is what it is CALLED and `lookup` is what `Intl` is asked about**, and they differ for
// exactly one zone. `localZone()` answers a zone whose title is `local` -- which is what the
// interpreter calls the entry it built from `/etc/localtime` -- while the rules have to be
// fetched under the host's real IANA name. Every other zone has one name for both.
class SZone {
    constructor(name, lookup, fixed, minutes) {
        this.name = name
        this.lookup = lookup
        this.fixed = fixed
        this.minutes = minutes
    }
}

class SZoned {
    constructor(us, zone) { this.us = us; this.zone = zone }
}

class SPeriod {
    constructor(months, days) { this.months = months; this.days = days }
}

// -- the zone table ------------------------------------------------------------------------

// **A zone is interned by name and never released**, which is `time.sysl`'s arrangement and is
// what makes `zone("UTC") == zone("UTC")` true. There is no slot number here -- the interpreter
// needs one because a parsed zone may not live in its collected heap, and JavaScript has no such
// rule -- so the map holds the value itself and equality compares the name.
const ZONES = new Map()

const fixedZone = (name, minutes) => {
    let z = ZONES.get(name)

    if (z === undefined) {
        z = new SZone(name, name, true, minutes)
        ZONES.set(name, z)
    }

    return z
}

// `+05:30` and `-08:00`, which is the whole of what `sysl.time`'s `parse_offset` accepts: two
// digits, a colon, two digits, after a sign. **`Z` is handled by the caller** and a form without
// the colon is refused, exactly as it is under the interpreter.
const offsetMinutes = (s) => {
    if (!/^[-+][0-9]{2}:[0-9]{2}$/.test(s)) return null

    const h = Number(s.slice(1, 3))
    const m = Number(s.slice(4, 6))

    if (h > 23 || m > 59) return null

    return (s[0] === "-" ? -1 : 1) * (h * 60 + m)
}

// The zone a name names, or the sentence saying why there is none. **Every sentence is
// `time.sysl`'s `zone_named` word for word**, so a program that names a zone it does not have
// reads the same complaint whichever back end ran it.
//
// **A name is refused before `Intl` is asked where it could not be a zone name**, which is the
// interpreter's rule and is there because `zone(name)` takes a string a program may have read out
// of a file. It matters less here -- `Intl` reaches no file system -- but a complaint that
// differed between the back ends would be a difference in the language rather than in the host.
const zoneNamed = (name) => {
    const known = ZONES.get(name)

    if (known !== undefined) return { zone: known, error: null }
    if (name === "UTC" || name === "Z" || name === "GMT") return { zone: fixedZone("UTC", 0), error: null }

    if (name.startsWith("+") || name.startsWith("-")) {
        const minutes = offsetMinutes(name)

        if (minutes === null)
            return { zone: null, error: "`" + name + "` is not an offset -- an offset is written `+05:30`" }

        return { zone: fixedZone(name, minutes), error: null }
    }

    if (name === "" || name.startsWith("/") || name.includes(".."))
        return { zone: null, error: "`" + name + "` is not the name of a zone" }

    // **`Intl` is what says whether the host has the zone**, and the way to ask is to build a
    // formatter and see whether it throws. There is no list to consult: `supportedValuesOf`
    // exists in newer engines and answers the canonical names only, so a link like
    // `US/Eastern` -- which the interpreter reads happily -- would be refused by a check against
    // it. Building the formatter is also the thing every later reading needs, so the cost is
    // paid once either way.
    let made = null

    try {
        made = zoneFormatter(name)
    } catch (e) {
        return { zone: null, error: "there is no zone called `" + name + "` on this host" }
    }

    const z = new SZone(name, name, false, 0)

    ZONES.set(name, z)

    return { zone: z, error: null }
}

// The zone this host is set to.
//
// **It is called `local` and not by its IANA name**, which is the interpreter's answer: that
// entry is built from `/etc/localtime`, a file that names no zone. A program wanting the name
// asks the host for it; a program wanting the rules has them either way.
const localZoneValue = () => {
    const known = ZONES.get("local")

    if (known !== undefined) return known

    let lookup = "UTC"

    try {
        lookup = new Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
    } catch (e) {
        lookup = "UTC"
    }

    const z = new SZone("local", lookup, false, 0)

    ZONES.set("local", z)

    return z
}

// -- what a zone's clocks read, over `Intl` ------------------------------------------------

// **One formatter per zone, kept**, because building one is far and away the expensive part of a
// reading and a program that formats a column of timestamps builds exactly one.
const ZONE_FORMATTERS = new Map()

const zoneFormatter = (name) => {
    let f = ZONE_FORMATTERS.get(name)

    if (f === undefined) {
        // **`era` is asked for and it is not decoration**: without it a year before 1 comes back
        // as a positive number and every offset in the first century is read from the wrong
        // side of the epoch. `hourCycle: "h23"` is asked for so that midnight is `0` rather than
        // the `24` an `h24` locale would give.
        f = new Intl.DateTimeFormat("en-US", { timeZone: name, hourCycle: "h23", era: "short",
            year: "numeric", month: "numeric", day: "numeric",
            hour: "numeric", minute: "numeric", second: "numeric" })

        ZONE_FORMATTERS.set(name, f)
    }

    return f
}

// A wall reading as a count of milliseconds, treating it as though it were UTC.
//
// **`setUTCFullYear` and not `Date.UTC`**, which is the trap in this corner of JavaScript:
// `Date.UTC` maps a year of 0 to 99 onto 1900 to 1999, silently, so every reading in the first
// century would be off by nineteen hundred years. The setter takes the year it is given.
const wallMsOf = (year, month, day, hour, minute, second) => {
    const d = new Date(0)

    d.setUTCFullYear(year, month - 1, day)
    d.setUTCHours(hour, minute, second, 0)

    return d.getTime()
}

// The widest instant a JavaScript `Date` holds. A reading past it is clamped rather than refused:
// no zone database has a rule that far out, so both back ends are reporting the last rule they
// know, and a fault here would be this back end refusing a value the other one answers for.
const MS_LIMIT = 8640000000000000

// How far a zone's clocks were set from UTC at that instant, in whole minutes.
//
// **The reading is taken and then undone**, which is the only route `Intl` offers: ask the zone
// what its clocks showed, rebuild that reading as though it were UTC, and the difference is the
// offset. There is no API that answers the offset directly.
const zoneOffsetAt = (z, us) => {
    if (z.fixed) return z.minutes

    const ms = Number(floorDiv(us, US_PER_MILLI))
    const clamped = ms > MS_LIMIT ? MS_LIMIT : ms < -MS_LIMIT ? -MS_LIMIT : ms
    const p = {}

    for (const part of zoneFormatter(z.lookup).formatToParts(new Date(clamped))) p[part.type] = part.value

    // `era` comes out as `AD`/`BC` in most engines and `A`/`B` in some; both are checked because
    // the difference is an ICU version rather than anything a program can control.
    let year = Number(p.year)

    if (p.era === "BC" || p.era === "B") year = 1 - year

    const wall = wallMsOf(year, Number(p.month), Number(p.day),
        Number(p.hour) % 24, Number(p.minute), Number(p.second))

    // **TRUNCATED TOWARD ZERO AND NOT ROUNDED, and a rounded one is wrong by a minute for every
    // zone before it had a railway.** `sysl.time`'s `Offset` is whole MINUTES and tzdata carries
    // local mean time in seconds, so `sysl.time.tzif` truncates -- Toronto's LMT is -5:17:32,
    // which is -317 minutes there and would be -318 rounded. The two back ends then disagree
    // about every reading before 1883 in that zone, which is exactly the class of silent
    // difference this whole file exists to avoid. Found by a negative control: dropping the era
    // handling above changed nothing in the corpus, which said the corpus had no reading old
    // enough to reach it -- and adding one turned this up.
    return Math.trunc((wall - clamped) / 60000)
}

// -- the civil calendar, which is `sysl.time`'s own arithmetic -------------------------------

const floorMod = (a, b) => a - floorDiv(a, b) * b

// Howard Hinnant's algorithm, which is `civil.sysl`'s `days_from_civil` line for line. Its
// inverse is `civilFromDays` below, and `js_rt_time.sysl`'s `civilText` is that same inverse
// written to print rather than to answer.
const daysFromCivil = (y0, m, d) => {
    const y = m <= 2n ? y0 - 1n : y0
    const era = floorDiv(y, 400n)
    const yoe = y - era * 400n
    const mp = m > 2n ? m - 3n : m + 9n
    const doy = (153n * mp + 2n) / 5n + d - 1n
    const doe = yoe * 365n + yoe / 4n - yoe / 100n + doy

    return era * 146097n + doe - 719468n
}

const civilFromDays = (day) => {
    const z = day + 719468n
    const era = floorDiv(z, 146097n)
    const doe = z - era * 146097n
    const yoe = (doe - doe / 1460n + doe / 36524n - doe / 146096n) / 365n
    const doy = doe - (365n * yoe + yoe / 4n - yoe / 100n)
    const mp = (5n * doy + 2n) / 153n
    const dayOfMonth = doy - (153n * mp + 2n) / 5n + 1n
    const month = mp < 10n ? mp + 3n : mp - 9n

    return { year: yoe + era * 400n + (month <= 2n ? 1n : 0n), month: month, day: dayOfMonth }
}

const leapYear = (y) => y % 4n === 0n && (y % 100n !== 0n || y % 400n === 0n)

const daysInMonth = (y, m) => {
    if (m === 2n) return leapYear(y) ? 29n : 28n

    return m === 4n || m === 6n || m === 9n || m === 11n ? 30n : 31n
}

const dayOfYear = (day) => {
    const c = civilFromDays(day)

    return day - daysFromCivil(c.year, 1n, 1n) + 1n
}

// 1970-01-01 was a Thursday, so shifting by four puts Sunday at zero.
const weekdayOf = (day) => floorMod(day + 4n, 7n)

const WEEKDAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

const MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December"]

const monthName = (m) => (m >= 1n && m <= 12n ? MONTH_NAMES[Number(m) - 1] : "?")

// The first date on or after this one falling on the given weekday.
const onOrAfterDay = (day, wanted) => day + floorMod(wanted - weekdayOf(day), 7n)

// A date only where the calendar has one, which is `checked_date` and is the check `date(y, m, d)`
// makes. `daysFromCivil` on its own is pure arithmetic and answers the 2nd of March for the 30th
// of February.
const checkedDate = (y, m, d) => {
    if (m < 1n || m > 12n) return null
    if (d < 1n || d > daysInMonth(y, m)) return null

    return daysFromCivil(y, m, d)
}

// Months are added by the calendar and the day is CLAMPED where the month it lands in is
// shorter, so the 31st of January plus a month is the 28th or 29th of February.
const plusMonths = (day, n) => {
    const c = civilFromDays(day)
    const total = c.year * 12n + (c.month - 1n) + n
    const y = floorDiv(total, 12n)
    const m = floorMod(total, 12n) + 1n
    const last = daysInMonth(y, m)

    return daysFromCivil(y, m, c.day < last ? c.day : last)
}

// **Months first and days after**, which is the order every calendar library settles on and which
// `time.sysl`'s `moved_date` states its reason for.
const movedDate = (day, months, days) => plusMonths(day, months) + days

// A wall reading as one number and back again, which is what lets a civil reading be moved by a
// length of timeline.
const wallUs = (day, us) => day * US_PER_DAY + us

const wallOf = (us) => {
    const day = floorDiv(us, US_PER_DAY)

    return { day: day, us: us - day * US_PER_DAY }
}

const atOffset = (us, minutes) => wallOf(us + BigInt(minutes) * US_PER_MINUTE)

const fromOffset = (day, us, minutes) => wallUs(day, us) - BigInt(minutes) * US_PER_MINUTE

// The wall reading a zoned value shows.
const zonedWall = (us, z) => atOffset(us, zoneOffsetAt(z, us))

// -- resolving a wall reading against a zone -------------------------------------------------

// `sysl.time`'s `resolve`, and its whole argument carried with it: a reading taken as though the
// offset were zero is within fourteen hours of the instant it names, so the offsets a day either
// side of that guess bracket every transition that could bear on the answer. Each candidate is
// applied and then checked against itself -- an offset still in force at the instant it produces
// is a real answer. One survivor is unique, two is ambiguous, none is a gap.
//
// **The assumption is that a zone does not change its offset twice inside forty-eight hours**, and
// no zone in the IANA database ever has. `zone.sysl` states it in the same words and neither
// implementation could detect one that did.
//
// **This is the one calendar answer `Intl` will not give directly and the reason it does not have
// to**: it is built out of offsets alone, which is exactly what was measured to agree.
const resolveWall = (day, us, z) => {
    const guess = wallUs(day, us)
    const before = zoneOffsetAt(z, guess - US_PER_DAY)
    const after = zoneOffsetAt(z, guess + US_PER_DAY)

    if (before === after) return { kind: "unique", at: fromOffset(day, us, before) }

    const a = fromOffset(day, us, before)
    const b = fromOffset(day, us, after)
    const aOk = zoneOffsetAt(z, a) === before
    const bOk = zoneOffsetAt(z, b) === after

    // Ordered by the timeline rather than by which offset was in force first, so `earlier` means
    // what it says whichever way the clocks went.
    if (aOk && bOk)
        return a < b ? { kind: "ambiguous", earlier: a, later: b }
            : { kind: "ambiguous", earlier: b, later: a }

    if (aOk) return { kind: "unique", at: a }
    if (bOk) return { kind: "unique", at: b }

    return { kind: "gap", before: before, after: after }
}

// A wall reading put back into its zone with the two awkward cases decided the way a calendar
// step means them: a repeated hour takes the earlier and a skipped one is pushed past the gap.
// `time.sysl`'s `calendar_moved` and `calendar_start` both do this.
const settledInZone = (day, us, z) => {
    const r = resolveWall(day, us, z)

    if (r.kind === "unique") return new SZoned(r.at, z)
    if (r.kind === "ambiguous") return new SZoned(r.earlier, z)

    return new SZoned(fromOffset(day, us, r.before), z)
}

// -- how a calendar value prints --------------------------------------------------------------

// An offset as a clock reading is written, `+05:30` or `-0400`, with `Z` for none of it.
const offsetWritten = (minutes, colon) => {
    if (minutes === 0) return "Z"

    const sign = minutes < 0 ? "-" : "+"
    const n = minutes < 0 ? -minutes : minutes

    return sign + twoDigits(BigInt(Math.trunc(n / 60))) + (colon ? ":" : "") + twoDigits(BigInt(n % 60))
}

// A calendar length: `1y 2mo 3d`, and `0d` for none of it.
//
// **Months and days are printed separately and never folded together**, which is the type's whole
// claim: `months(1)` and `days(30)` are different lengths.
const periodText = (months, days) => {
    if (months === 0n && days === 0n) return "0d"

    const y = months / 12n
    const mo = months % 12n
    const parts = []

    if (y !== 0n) parts.push(y + "y")
    if (mo !== 0n) parts.push(mo + "mo")
    if (days !== 0n) parts.push(days + "d")

    return parts.join(" ")
}

// ISO 8601 throughout, which is `time.sysl`'s `temporal_text` for the six kinds it holds.
//
// **A zoned reading prints its offset and then its zone in brackets**, which is Java's form and
// the only one that round-trips -- the offset alone loses which zone it was and the name alone
// loses which side of a transition the reading was on. **A zone that is a fixed offset does not
// name itself again**, `...Z[UTC]` saying one thing twice.
const calendarText = (v) => {
    if (v instanceof SDate) return civilText(v.day)
    if (v instanceof STime) return clockText(v.us)
    if (v instanceof SDateTime) return civilText(v.day) + "T" + clockText(v.us)
    if (v instanceof SZone) return v.name
    if (v instanceof SPeriod) return periodText(v.months, v.days)

    const off = zoneOffsetAt(v.zone, v.us)
    const wall = atOffset(v.us, off)
    const named = v.zone.fixed ? "" : "[" + v.zone.name + "]"

    return civilText(wall.day) + "T" + clockText(wall.us) + offsetWritten(off, true) + named
}

const isCalendar = (v) => v instanceof SDate || v instanceof STime || v instanceof SDateTime ||
    v instanceof SZone || v instanceof SZoned || v instanceof SPeriod

// -- what a calendar value IS, and what it does beside another one ---------------------------

// The wall reading any of the three calendar-shaped values carries, or `null` where the value is
// not one of them. **One question asked of three types**, which is what lets `year`, `month` and
// the rest be one implementation each.
const wallReading = (v) => {
    if (v instanceof SDate) return { day: v.day, us: 0n }
    if (v instanceof STime) return { day: 0n, us: v.us }
    if (v instanceof SDateTime) return { day: v.day, us: v.us }
    if (v instanceof SZoned) return zonedWall(v.us, v.zone)

    return null
}

const hasDate = (v) => v instanceof SDate || v instanceof SDateTime || v instanceof SZoned

const hasTime = (v) => v instanceof STime || v instanceof SDateTime || v instanceof SZoned

// `+`, `-` and `*` where either side is a calendar value, and `undefined` for a pair this has
// nothing to say about -- `js_rt_ops.sysl` tries it after `temporalArith` and falls through to
// an object's own hook, which is `arith.sysl`'s ordering.
//
// **A duration may be added to anything and a period only to a calendar reading**, which is the
// rule that earns the two types: `t + days(1)` keeps the wall clock across a daylight saving
// change and `t + hours(24)` does not.
const calendarArith = (op, a, b) => {
    const shifted = (forward, back) => op === "+" ? forward : op === "-" ? back : undefined

    if (a instanceof SInstant && b instanceof SPeriod) {
        if (op === "+" || op === "-")
            $.fault("an instant has no calendar to move by -- read it in a zone first, with `t.at(zone)`")

        return undefined
    }

    if (a instanceof SPeriod) {
        if (b instanceof SPeriod) {
            if (op === "+") return new SPeriod(a.months + b.months, a.days + b.days)
            if (op === "-") return new SPeriod(a.months - b.months, a.days - b.days)

            return undefined
        }

        if ($.isInt(b) && op === "*") return new SPeriod(a.months * b, a.days * b)

        return undefined
    }

    if (a instanceof SDate) {
        if (b instanceof SPeriod)
            return shifted(new SDate(movedDate(a.day, b.months, b.days)),
                new SDate(movedDate(a.day, -b.months, -b.days)))

        // **The difference of two dates is a period of DAYS and not of months**, because the
        // number of months between two dates depends on which end you count from.
        if (b instanceof SDate && op === "-") return new SPeriod(0n, a.day - b.day)

        return undefined
    }

    if (a instanceof SDateTime) {
        if (b instanceof SDuration) {
            const forward = wallOf(wallUs(a.day, a.us) + b.us)
            const back = wallOf(wallUs(a.day, a.us) - b.us)

            return shifted(new SDateTime(forward.day, forward.us), new SDateTime(back.day, back.us))
        }

        if (b instanceof SPeriod)
            return shifted(new SDateTime(movedDate(a.day, b.months, b.days), a.us),
                new SDateTime(movedDate(a.day, -b.months, -b.days), a.us))

        if (b instanceof SDateTime && op === "-")
            return new SDuration($.i64(wallUs(a.day, a.us) - wallUs(b.day, b.us)))

        return undefined
    }

    if (a instanceof SZoned) {
        // **A duration moves a zoned reading along the timeline and a period moves its
        // calendar.** An hour after 01:30 on a night the clocks go forward is 03:30; a day after
        // Saturday at 09:00 is Sunday at 09:00, whatever happened to the clocks in between.
        if (b instanceof SDuration)
            return shifted(new SZoned($.i64(a.us + b.us), a.zone), new SZoned($.i64(a.us - b.us), a.zone))

        if (b instanceof SPeriod) {
            const wall = zonedWall(a.us, a.zone)

            return shifted(settledInZone(movedDate(wall.day, b.months, b.days), wall.us, a.zone),
                settledInZone(movedDate(wall.day, -b.months, -b.days), wall.us, a.zone))
        }

        if (b instanceof SZoned && op === "-") return new SDuration($.i64(a.us - b.us))

        return undefined
    }

    if ($.isInt(a) && b instanceof SPeriod && op === "*") return new SPeriod(a * b.months, a * b.days)

    return undefined
}

// The four orderings over two calendar values of one kind, and `undefined` for anything else.
//
// **Two zoned readings order by the INSTANT, where equality also compares the zone**: 09:00 in
// Toronto and 09:00 in Tokyo are neither before nor after each other and are not equal either,
// so the two questions genuinely have different answers. Java draws the line in the same place.
const calendarCompare = (op, a, b) => {
    const ordered = (x, y) => op === "<" ? x < y : op === "<=" ? x <= y : op === ">" ? x > y : x >= y

    if (a instanceof SDate && b instanceof SDate) return ordered(a.day, b.day)
    if (a instanceof STime && b instanceof STime) return ordered(a.us, b.us)
    if (a instanceof SDateTime && b instanceof SDateTime)
        return ordered(wallUs(a.day, a.us), wallUs(b.day, b.us))
    if (a instanceof SZoned && b instanceof SZoned) return ordered(a.us, b.us)

    return undefined
}

// Whether two calendar values are equal, or `undefined` where neither side is one.
//
// **Each is equal to one of its own kind naming the same thing and to nothing else** -- a date
// and a dateTime at midnight are not equal, for the reason an integer and a string of digits are
// not. A period compares on its two scales and does not normalise between them, since it cannot.
const calendarSame = (a, b) => {
    if (a instanceof SDate) return b instanceof SDate && a.day === b.day
    if (a instanceof STime) return b instanceof STime && a.us === b.us
    if (a instanceof SDateTime) return b instanceof SDateTime && a.day === b.day && a.us === b.us
    if (a instanceof SZone) return b instanceof SZone && a.name === b.name
    if (a instanceof SZoned)
        return b instanceof SZoned && a.us === b.us && a.zone.name === b.zone.name
    if (a instanceof SPeriod)
        return b instanceof SPeriod && a.months === b.months && a.days === b.days

    return undefined
}

// Where a calendar value sits in a table, or `null` for something that is not one.
//
// **Each kind is salted with its own letter**, as the timeline kinds are, so a date and a period
// holding the same number never collide. `table.sysl` salts for the same reason.
const calendarKey = (v) => {
    if (v instanceof SDate) return "D" + v.day
    if (v instanceof STime) return "T" + v.us
    if (v instanceof SDateTime) return "W" + v.day + ":" + v.us
    if (v instanceof SZone) return "Z" + v.name
    if (v instanceof SZoned) return "N" + v.us + ":" + v.zone.name
    if (v instanceof SPeriod) return "P" + v.months + ":" + v.days

    return null
}

// -- reading a date, a time or a timestamp back out of text ----------------------------------

// `sysl.time`'s `parse.sysl`, whose three refusals are what the four builtins quote. **A parse
// checks the CALENDAR and not only the shape**: `2026-02-30` has the right digits in the right
// places and is not a date.
const badShape = (at) => ({ error: "not the expected shape at byte " + at })
const outOfRange = (what) => ({ error: what + " is out of range" })
const trailing = (at) => ({ error: "unexpected text at byte " + at })

// A run of exactly `n` digits, as a number. **Not a general integer reader**: one would take a
// leading sign, and `+12-31` is not a month.
const digitsAt = (s, at, n) => {
    if (at + n > s.length) return badShape(at)

    let v = 0

    for (let i = at; i < at + n; i = i + 1) {
        const c = s.charCodeAt(i)

        if (c < 48 || c > 57) return badShape(i)

        v = v * 10 + (c - 48)
    }

    return { value: v }
}

const dateFrom = (s, at) => {
    const y = digitsAt(s, at, 4)

    if (y.error !== undefined) return y
    if (s.charCodeAt(at + 4) !== 45) return badShape(at + 4)

    const m = digitsAt(s, at + 5, 2)

    if (m.error !== undefined) return m
    if (s.charCodeAt(at + 7) !== 45) return badShape(at + 7)

    const d = digitsAt(s, at + 8, 2)

    if (d.error !== undefined) return d
    if (m.value < 1 || m.value > 12) return outOfRange("month")
    if (d.value < 1 || BigInt(d.value) > daysInMonth(BigInt(y.value), BigInt(m.value)))
        return outOfRange("day")

    return { value: daysFromCivil(BigInt(y.value), BigInt(m.value), BigInt(d.value)), next: at + 10 }
}

// `HH:MM`, `HH:MM:SS` or `HH:MM:SS.ffffff`, the seconds and the fraction each optional. A
// seconds field is present only where a colon follows and a fraction only where a dot follows
// that, which is what lets a timestamp read an offset off the tail.
const timeFrom = (s, at) => {
    const h = digitsAt(s, at, 2)

    if (h.error !== undefined) return h
    if (s.charCodeAt(at + 2) !== 58) return badShape(at + 2)

    const mi = digitsAt(s, at + 3, 2)

    if (mi.error !== undefined) return mi
    if (h.value > 23) return outOfRange("hour")
    if (mi.value > 59) return outOfRange("minute")

    let us = BigInt(h.value) * US_PER_HOUR + BigInt(mi.value) * US_PER_MINUTE
    let next = at + 5

    if (next >= s.length || s.charCodeAt(next) !== 58) return { value: us, next: next }

    const sec = digitsAt(s, next + 1, 2)

    if (sec.error !== undefined) return sec
    if (sec.value > 59) return outOfRange("second")

    us = us + BigInt(sec.value) * US_PER_SECOND
    next = next + 3

    if (next >= s.length || s.charCodeAt(next) !== 46) return { value: us, next: next }

    // Up to six digits of fraction, each worth ten times less than the last. Fewer than six is
    // legal and means what it says: `.5` is half a second and not five microseconds.
    let scale = US_PER_SECOND
    let i = next + 1
    let seen = 0

    while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57 && seen < 6) {
        scale = scale / 10n
        us = us + BigInt(s.charCodeAt(i) - 48) * scale
        i = i + 1
        seen = seen + 1
    }

    if (seen === 0) return badShape(next + 1)

    return { value: us, next: i }
}

const offsetFrom = (s, at) => {
    if (at >= s.length) return badShape(at)
    if (s.charCodeAt(at) === 90) return { value: 0, next: at + 1 }
    if (s.charCodeAt(at) !== 43 && s.charCodeAt(at) !== 45) return badShape(at)

    const h = digitsAt(s, at + 1, 2)

    if (h.error !== undefined) return h
    if (s.charCodeAt(at + 3) !== 58) return badShape(at + 3)

    const m = digitsAt(s, at + 4, 2)

    if (m.error !== undefined) return m
    if (h.value > 23) return outOfRange("offset hour")
    if (m.value > 59) return outOfRange("offset minute")

    const sign = s.charCodeAt(at) === 45 ? -1 : 1

    return { value: sign * (h.value * 60 + m.value), next: at + 6 }
}

// A date and a time joined by a space or a `T`. **Both spellings are read because both are
// written**: ISO 8601 says `T` and a person writes a space.
const joinedAt = (s, at) => s.charCodeAt(at) === 32 || s.charCodeAt(at) === 84

const parseDateText = (s) => {
    const d = dateFrom(s, 0)

    if (d.error !== undefined) return d
    if (d.next !== s.length) return trailing(d.next)

    return { value: new SDate(d.value) }
}

const parseTimeText = (s) => {
    const t = timeFrom(s, 0)

    if (t.error !== undefined) return t
    if (t.next !== s.length) return trailing(t.next)

    return { value: new STime(t.value) }
}

const parseDateTimeText = (s) => {
    const d = dateFrom(s, 0)

    if (d.error !== undefined) return d
    if (d.next >= s.length || !joinedAt(s, d.next)) return badShape(d.next)

    const t = timeFrom(s, d.next + 1)

    if (t.error !== undefined) return t
    if (t.next !== s.length) return trailing(t.next)

    return { value: new SDateTime(d.value, t.value) }
}

const parseTimestampText = (s) => {
    const d = dateFrom(s, 0)

    if (d.error !== undefined) return d
    if (d.next >= s.length || !joinedAt(s, d.next)) return badShape(d.next)

    const t = timeFrom(s, d.next + 1)

    if (t.error !== undefined) return t

    const o = offsetFrom(s, t.next)

    if (o.error !== undefined) return o
    if (o.next !== s.length) return trailing(o.next)

    return { value: new SInstant($.i64(fromOffset(d.value, t.value, o.value))) }
}

// -- the byte plumbing every digest shares ---------------------------------------------------

// **A digest works on a `Uint8Array` and answers one**, and the conversion to and from slate's
// array of integers happens once at the builtin. Doing it per block would put a `BigInt` in the
// inner loop of every one of these.
const rotr32 = (x, n) => (x >>> n) | (x << (32 - n))

// The padding every one of the five uses: a `0x80` byte, then zeros, then the length in bits as
// a big-endian number of `tail` bytes. SHA-512 counts its length in 128 bits where the others
// count in 64, and nothing else about the padding differs.
const padded = (bytes, blockSize, tail, littleEndian) => {
    const l = bytes.length
    const size = (Math.floor((l + tail + 1 + blockSize - 1) / blockSize)) * blockSize
    const out = new Uint8Array(size)

    out.set(bytes)
    out[l] = 0x80

    // The length is written as a count of BITS, which is why it is multiplied here and why it
    // is done in two halves: a length in bits passes 2^32 at 512 MiB, and a `>>> 0` of that
    // would silently wrap.
    const hi = Math.floor(l / 536870912)
    const lo = (l * 8) >>> 0
    const dv = new DataView(out.buffer)

    if (littleEndian) {
        dv.setUint32(size - 8, lo, true)
        dv.setUint32(size - 4, hi, true)
    } else {
        dv.setUint32(size - 8, hi)
        dv.setUint32(size - 4, lo)
    }

    return out
}

const wordsOut = (words, be) => {
    const out = new Uint8Array(words.length * 4)
    const dv = new DataView(out.buffer)

    for (let i = 0; i < words.length; i = i + 1) dv.setUint32(i * 4, words[i] >>> 0, !be)

    return out
}

// -- MD5 --------------------------------------------------------------------------------------

// **Broken, and here for the same reason the interpreter exports it**: a program speaking
// PostgreSQL's `md5` login, HTTP Digest or an S3 `ETag` has no say in the matter. Nothing new is
// to be signed with it and `pbkdf2` refuses it.
//
// **It is the one digest that is LITTLE-endian**, in its length field and in its output, which
// is the detail every reimplementation gets wrong once.
const MD5_S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]

const MD5_K = new Int32Array(64)

for (let i = 0; i < 64; i = i + 1) MD5_K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296)

const md5Of = (bytes) => {
    const block = padded(bytes, 64, 8, true)
    const dv = new DataView(block.buffer)
    const h = new Int32Array([0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476])
    const m = new Int32Array(16)

    for (let off = 0; off < block.length; off = off + 64) {
        for (let j = 0; j < 16; j = j + 1) m[j] = dv.getUint32(off + j * 4, true)

        let a = h[0], b = h[1], c = h[2], d = h[3]

        for (let i = 0; i < 64; i = i + 1) {
            let f = 0
            let g = 0

            if (i < 16) { f = (b & c) | (~b & d); g = i }
            else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16 }
            else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16 }
            else { f = c ^ (b | ~d); g = (7 * i) % 16 }

            const tmp = d

            d = c
            c = b

            const sum = (a + f + MD5_K[i] + m[g]) | 0
            const s = MD5_S[i]

            b = (b + ((sum << s) | (sum >>> (32 - s)))) | 0
            a = tmp
        }

        h[0] = (h[0] + a) | 0
        h[1] = (h[1] + b) | 0
        h[2] = (h[2] + c) | 0
        h[3] = (h[3] + d) | 0
    }

    return wordsOut(h, false)
}

// -- SHA-1 -------------------------------------------------------------------------------------

// Broken for signatures and required by a WebSocket handshake, a Git object and an old server's
// SASL, which is exactly why the interpreter exports it too.
const sha1Of = (bytes) => {
    const block = padded(bytes, 64, 8, false)
    const dv = new DataView(block.buffer)
    const h = new Int32Array([0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0])
    const w = new Int32Array(80)

    for (let off = 0; off < block.length; off = off + 64) {
        for (let j = 0; j < 16; j = j + 1) w[j] = dv.getUint32(off + j * 4)

        for (let j = 16; j < 80; j = j + 1) {
            const x = w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16]

            w[j] = (x << 1) | (x >>> 31)
        }

        let a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]

        for (let i = 0; i < 80; i = i + 1) {
            let f = 0
            let k = 0

            if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999 }
            else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1 }
            else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc }
            else { f = b ^ c ^ d; k = 0xca62c1d6 }

            const t = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) | 0

            e = d
            d = c
            c = (b << 30) | (b >>> 2)
            b = a
            a = t
        }

        h[0] = (h[0] + a) | 0
        h[1] = (h[1] + b) | 0
        h[2] = (h[2] + c) | 0
        h[3] = (h[3] + d) | 0
        h[4] = (h[4] + e) | 0
    }

    return wordsOut(h, true)
}

// -- SHA-256 -----------------------------------------------------------------------------------

const SHA256_K = new Int32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2])

const sha256Of = (bytes) => {
    const block = padded(bytes, 64, 8, false)
    const dv = new DataView(block.buffer)
    const h = new Int32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19])
    const w = new Int32Array(64)

    for (let off = 0; off < block.length; off = off + 64) {
        for (let j = 0; j < 16; j = j + 1) w[j] = dv.getUint32(off + j * 4)

        for (let j = 16; j < 64; j = j + 1) {
            const a = w[j - 15]
            const b = w[j - 2]
            const s0 = rotr32(a, 7) ^ rotr32(a, 18) ^ (a >>> 3)
            const s1 = rotr32(b, 17) ^ rotr32(b, 19) ^ (b >>> 10)

            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) | 0
        }

        let a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]

        for (let i = 0; i < 64; i = i + 1) {
            const S1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)
            const ch = (e & f) ^ (~e & g)
            const t1 = (hh + S1 + ch + SHA256_K[i] + w[i]) | 0
            const S0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)
            const maj = (a & b) ^ (a & c) ^ (b & c)
            const t2 = (S0 + maj) | 0

            hh = g
            g = f
            f = e
            e = (d + t1) | 0
            d = c
            c = b
            b = a
            a = (t1 + t2) | 0
        }

        h[0] = (h[0] + a) | 0
        h[1] = (h[1] + b) | 0
        h[2] = (h[2] + c) | 0
        h[3] = (h[3] + d) | 0
        h[4] = (h[4] + e) | 0
        h[5] = (h[5] + f) | 0
        h[6] = (h[6] + g) | 0
        h[7] = (h[7] + hh) | 0
    }

    return wordsOut(h, true)
}

// -- SHA-384 and SHA-512, in hi/lo pairs --------------------------------------------------------

// **One implementation and two sets of starting words**, which is the whole difference between
// the two: SHA-384 is SHA-512 begun elsewhere and cut to 48 bytes. The constants below are
// written as interleaved hi and lo halves of the published 64-bit values.
const SHA512_K = new Int32Array([
    0x428a2f98, 0xd728ae22, 0x71374491, 0x23ef65cd, 0xb5c0fbcf, 0xec4d3b2f,
    0xe9b5dba5, 0x8189dbbc, 0x3956c25b, 0xf348b538, 0x59f111f1, 0xb605d019,
    0x923f82a4, 0xaf194f9b, 0xab1c5ed5, 0xda6d8118, 0xd807aa98, 0xa3030242,
    0x12835b01, 0x45706fbe, 0x243185be, 0x4ee4b28c, 0x550c7dc3, 0xd5ffb4e2,
    0x72be5d74, 0xf27b896f, 0x80deb1fe, 0x3b1696b1, 0x9bdc06a7, 0x25c71235,
    0xc19bf174, 0xcf692694, 0xe49b69c1, 0x9ef14ad2, 0xefbe4786, 0x384f25e3,
    0x0fc19dc6, 0x8b8cd5b5, 0x240ca1cc, 0x77ac9c65, 0x2de92c6f, 0x592b0275,
    0x4a7484aa, 0x6ea6e483, 0x5cb0a9dc, 0xbd41fbd4, 0x76f988da, 0x831153b5,
    0x983e5152, 0xee66dfab, 0xa831c66d, 0x2db43210, 0xb00327c8, 0x98fb213f,
    0xbf597fc7, 0xbeef0ee4, 0xc6e00bf3, 0x3da88fc2, 0xd5a79147, 0x930aa725,
    0x06ca6351, 0xe003826f, 0x14292967, 0x0a0e6e70, 0x27b70a85, 0x46d22ffc,
    0x2e1b2138, 0x5c26c926, 0x4d2c6dfc, 0x5ac42aed, 0x53380d13, 0x9d95b3df,
    0x650a7354, 0x8baf63de, 0x766a0abb, 0x3c77b2a8, 0x81c2c92e, 0x47edaee6,
    0x92722c85, 0x1482353b, 0xa2bfe8a1, 0x4cf10364, 0xa81a664b, 0xbc423001,
    0xc24b8b70, 0xd0f89791, 0xc76c51a3, 0x0654be30, 0xd192e819, 0xd6ef5218,
    0xd6990624, 0x5565a910, 0xf40e3585, 0x5771202a, 0x106aa070, 0x32bbd1b8,
    0x19a4c116, 0xb8d2d0c8, 0x1e376c08, 0x5141ab53, 0x2748774c, 0xdf8eeb99,
    0x34b0bcb5, 0xe19b48a8, 0x391c0cb3, 0xc5c95a63, 0x4ed8aa4a, 0xe3418acb,
    0x5b9cca4f, 0x7763e373, 0x682e6ff3, 0xd6b2b8a3, 0x748f82ee, 0x5defb2fc,
    0x78a5636f, 0x43172f60, 0x84c87814, 0xa1f0ab72, 0x8cc70208, 0x1a6439ec,
    0x90befffa, 0x23631e28, 0xa4506ceb, 0xde82bde9, 0xbef9a3f7, 0xb2c67915,
    0xc67178f2, 0xe372532b, 0xca273ece, 0xea26619c, 0xd186b8c7, 0x21c0c207,
    0xeada7dd6, 0xcde0eb1e, 0xf57d4f7f, 0xee6ed178, 0x06f067aa, 0x72176fba,
    0x0a637dc5, 0xa2c898a6, 0x113f9804, 0xbef90dae, 0x1b710b35, 0x131c471b,
    0x28db77f5, 0x23047d84, 0x32caab7b, 0x40c72493, 0x3c9ebe0a, 0x15c9bebc,
    0x431d67c4, 0x9c100d4c, 0x4cc5d4be, 0xcb3e42b6, 0x597f299c, 0xfc657e2a,
    0x5fcb6fab, 0x3ad6faec, 0x6c44198c, 0x4a475817])

const SHA512_H = new Int32Array([
    0x6a09e667, 0xf3bcc908, 0xbb67ae85, 0x84caa73b, 0x3c6ef372, 0xfe94f82b, 0xa54ff53a, 0x5f1d36f1,
    0x510e527f, 0xade682d1, 0x9b05688c, 0x2b3e6c1f, 0x1f83d9ab, 0xfb41bd6b, 0x5be0cd19, 0x137e2179])

const SHA384_H = new Int32Array([
    0xcbbb9d5d, 0xc1059ed8, 0x629a292a, 0x367cd507, 0x9159015a, 0x3070dd17, 0x152fecd8, 0xf70e5939,
    0x67332667, 0xffc00b31, 0x8eb44a87, 0x68581511, 0xdb0c2e0d, 0x64f98fa7, 0x47b5481d, 0xbefa4fa4])

// **Every 64-bit operation is a pair of 32-bit ones and the CARRY is what has to be right.** An
// unsigned compare of the low halves after adding says whether one happened, which is the trick
// that keeps this to integer arithmetic rather than dropping to `BigInt`.
const sha512Of = (bytes, start, outWords) => {
    const block = padded(bytes, 128, 16, false)
    const dv = new DataView(block.buffer)
    const h = new Int32Array(start)
    const w = new Int32Array(160)

    for (let off = 0; off < block.length; off = off + 128) {
        for (let j = 0; j < 32; j = j + 1) w[j] = dv.getUint32(off + j * 4)

        for (let j = 16; j < 80; j = j + 1) {
            const i15h = w[(j - 15) * 2], i15l = w[(j - 15) * 2 + 1]
            const i2h = w[(j - 2) * 2], i2l = w[(j - 2) * 2 + 1]

            // s0 = rotr(x,1) ^ rotr(x,8) ^ shr(x,7)
            const s0h = ((i15h >>> 1) | (i15l << 31)) ^ ((i15h >>> 8) | (i15l << 24)) ^ (i15h >>> 7)
            const s0l = ((i15l >>> 1) | (i15h << 31)) ^ ((i15l >>> 8) | (i15h << 24)) ^ ((i15l >>> 7) | (i15h << 25))

            // s1 = rotr(x,19) ^ rotr(x,61) ^ shr(x,6); 61 is past 32, so the halves swap.
            const s1h = ((i2h >>> 19) | (i2l << 13)) ^ ((i2l >>> 29) | (i2h << 3)) ^ (i2h >>> 6)
            const s1l = ((i2l >>> 19) | (i2h << 13)) ^ ((i2h >>> 29) | (i2l << 3)) ^ ((i2l >>> 6) | (i2h << 26))

            let lo = (w[(j - 16) * 2 + 1] >>> 0) + (s0l >>> 0)
            let hi = (w[(j - 16) * 2] + s0h + Math.floor(lo / 4294967296)) | 0

            lo = (lo >>> 0) + (w[(j - 7) * 2 + 1] >>> 0)
            hi = (hi + w[(j - 7) * 2] + Math.floor(lo / 4294967296)) | 0

            lo = (lo >>> 0) + (s1l >>> 0)
            hi = (hi + s1h + Math.floor(lo / 4294967296)) | 0

            w[j * 2] = hi
            w[j * 2 + 1] = lo | 0
        }

        let ah = h[0], al = h[1], bh = h[2], bl = h[3], ch = h[4], cl = h[5], dh = h[6], dl = h[7]
        let eh = h[8], el = h[9], fh = h[10], fl = h[11], gh = h[12], gl = h[13], hh = h[14], hl = h[15]

        for (let i = 0; i < 80; i = i + 1) {
            // S1 = rotr(e,14) ^ rotr(e,18) ^ rotr(e,41); 41 is past 32.
            const S1h = ((eh >>> 14) | (el << 18)) ^ ((eh >>> 18) | (el << 14)) ^ ((el >>> 9) | (eh << 23))
            const S1l = ((el >>> 14) | (eh << 18)) ^ ((el >>> 18) | (eh << 14)) ^ ((eh >>> 9) | (el << 23))
            const chh = (eh & fh) ^ (~eh & gh)
            const chl = (el & fl) ^ (~el & gl)

            let lo = (hl >>> 0) + (S1l >>> 0)
            let hi = (hh + S1h + Math.floor(lo / 4294967296)) | 0

            lo = (lo >>> 0) + (chl >>> 0)
            hi = (hi + chh + Math.floor(lo / 4294967296)) | 0

            lo = (lo >>> 0) + (SHA512_K[i * 2 + 1] >>> 0)
            hi = (hi + SHA512_K[i * 2] + Math.floor(lo / 4294967296)) | 0

            lo = (lo >>> 0) + (w[i * 2 + 1] >>> 0)
            hi = (hi + w[i * 2] + Math.floor(lo / 4294967296)) | 0

            const t1h = hi
            const t1l = lo | 0

            // S0 = rotr(a,28) ^ rotr(a,34) ^ rotr(a,39); the last two are past 32.
            const S0h = ((ah >>> 28) | (al << 4)) ^ ((al >>> 2) | (ah << 30)) ^ ((al >>> 7) | (ah << 25))
            const S0l = ((al >>> 28) | (ah << 4)) ^ ((ah >>> 2) | (al << 30)) ^ ((ah >>> 7) | (al << 25))
            const majh = (ah & bh) ^ (ah & ch) ^ (bh & ch)
            const majl = (al & bl) ^ (al & cl) ^ (bl & cl)

            let t2l = (S0l >>> 0) + (majl >>> 0)
            const t2h = (S0h + majh + Math.floor(t2l / 4294967296)) | 0

            t2l = t2l | 0

            hh = gh; hl = gl
            gh = fh; gl = fl
            fh = eh; fl = el

            let nl = (dl >>> 0) + (t1l >>> 0)

            eh = (dh + t1h + Math.floor(nl / 4294967296)) | 0
            el = nl | 0

            dh = ch; dl = cl
            ch = bh; cl = bl
            bh = ah; bl = al

            nl = (t1l >>> 0) + (t2l >>> 0)
            ah = (t1h + t2h + Math.floor(nl / 4294967296)) | 0
            al = nl | 0
        }

        const add = (i, xh, xl) => {
            const lo = (h[i + 1] >>> 0) + (xl >>> 0)

            h[i] = (h[i] + xh + Math.floor(lo / 4294967296)) | 0
            h[i + 1] = lo | 0
        }

        add(0, ah, al); add(2, bh, bl); add(4, ch, cl); add(6, dh, dl)
        add(8, eh, el); add(10, fh, fl); add(12, gh, gl); add(14, hh, hl)
    }

    return wordsOut(h.subarray(0, outWords), true)
}

// -- the five, by name -------------------------------------------------------------------------

// **`crypto.sysl`'s `digest_of` under another name**, and the spelling of each algorithm is that
// file's: a program writes `hmac("SHA-256", ...)` and the two back ends must agree about which
// strings are words.
const digestOf = (alg, bytes) => {
    if (alg === "MD5") return md5Of(bytes)
    if (alg === "SHA-1") return sha1Of(bytes)
    if (alg === "SHA-256") return sha256Of(bytes)
    if (alg === "SHA-384") return sha512Of(bytes, SHA384_H, 12)
    if (alg === "SHA-512") return sha512Of(bytes, SHA512_H, 16)

    return null
}

// How many bytes a digest is, and how wide its block is -- HMAC needs both.
const DIGEST_BLOCK = { "MD5": 64, "SHA-1": 64, "SHA-256": 64, "SHA-384": 128, "SHA-512": 128 }

// -- HMAC ---------------------------------------------------------------------------------------

// RFC 2104, and the two things it is easy to get wrong are both here: a key LONGER than the block
// is hashed first, and a shorter one is padded with zeros rather than repeated.
const hmacOf = (alg, key, message) => {
    const blockSize = DIGEST_BLOCK[alg]

    if (blockSize === undefined) return null

    const shortened = key.length > blockSize ? digestOf(alg, key) : key
    const k = new Uint8Array(blockSize)

    k.set(shortened)

    const inner = new Uint8Array(blockSize + message.length)
    const outerKey = new Uint8Array(blockSize)

    for (let i = 0; i < blockSize; i = i + 1) {
        inner[i] = k[i] ^ 0x36
        outerKey[i] = k[i] ^ 0x5c
    }

    inner.set(message, blockSize)

    const first = digestOf(alg, inner)
    const outer = new Uint8Array(blockSize + first.length)

    outer.set(outerKey)
    outer.set(first, blockSize)

    return digestOf(alg, outer)
}

// -- PBKDF2 ---------------------------------------------------------------------------------------

// RFC 2898, and **the iteration count is the caller's because the protocol says it**: SCRAM
// carries the server's count on the wire, and a client using its own would derive a different key
// and be told its password was wrong.
//
// **This is the one call here whose cost a program can feel**, being the one designed to be slow.
// 100,000 iterations of SHA-256 is about 176 ms in this runtime and 7 ms in a native library, so
// a browser pays roughly 25x. `javascript.md` says so beside the number.
const pbkdf2Of = (alg, password, salt, iterations, length) => {
    const hl = digestOf(alg, new Uint8Array(0)).length
    const out = new Uint8Array(length)
    let off = 0
    let block = 1

    while (off < length) {
        const seeded = new Uint8Array(salt.length + 4)

        seeded.set(salt)
        new DataView(seeded.buffer).setUint32(salt.length, block)

        let u = hmacOf(alg, password, seeded)

        const t = u.slice()

        for (let i = 1; i < iterations; i = i + 1) {
            u = hmacOf(alg, password, u)

            for (let j = 0; j < hl; j = j + 1) t[j] = t[j] ^ u[j]
        }

        const n = Math.min(hl, length - off)

        out.set(t.subarray(0, n), off)
        off = off + n
        block = block + 1
    }

    return out
}

// -- comparing two tags without saying how much of one was right --------------------------------

// **A comparison that stops at the first differing byte is how a tag is forged a byte at a time.**
// The lengths are compared first and openly, a length not being a secret; the bytes are then
// folded together with no branch in the loop.
const sameTag = (a, b) => {
    if (a.length !== b.length) return false

    let diff = 0

    for (let i = 0; i < a.length; i = i + 1) diff = diff | (a[i] ^ b[i])

    return diff === 0
}

// -- the value ---------------------------------------------------------------------------------

// A compiled pattern. **A SLOT and not the `RegExp` itself**, which is `value.sysl`'s
// `RegexVal` and is what makes two identically written patterns equal: the table is keyed by
// the source and the flags, so `regex("a") == regex("a")` without comparing any text.
class SRegex {
    constructor(id) { this.id = id }
}

// What a slot holds: what the program wrote, and the two `RegExp`s built from it.
const REGEX_TABLE = []
const REGEX_IDS = new Map()

// -- the table -----------------------------------------------------------------------------------

// The flags a program may write. **`regex.sysl`'s words, so a refusal reads the same on both
// back ends** -- `g` and `y` because a pattern here carries no position, and `x` because it was
// slate's own under PCRE2 and is nobody's under ECMAScript.
const regexOptions = (flags) => {
    for (const c of flags) {
        if (c === "g")
            $.fault("there is no `g` flag -- `replace` already replaces every match and " +
                "`findAll` already finds every one")

        if (c === "y")
            $.fault("there is no `y` flag -- a regular expression here carries no position for " +
                "a sticky match to start from")

        if (c === "x")
            $.fault("there is no `x` flag -- ECMAScript has no extended mode, so a space " +
                "written in a pattern is part of it")

        if ("imsu".indexOf(c) < 0)
            $.fault("`" + c + "` is not a regular expression flag -- the flags are `i`, `m`, `s` and `u`")
    }
}

// The slot for this pattern, compiling it the first time it is asked for.
//
// **Keyed by the pattern and its flags, so an identical pattern compiles once** -- which is
// `regex.sysl`'s table and its reason: nothing is ever released, so a slot always names the
// pattern it named and one number is the whole value.
// **The VALUE is interned and not only the slot**, which is what makes `regex("a") ==
// regex("a")` true here as it is there. The interpreter's `RegexVal` is one number, so two of
// them naming one slot are the same value by construction; a `new SRegex` each time would be
// two objects and equality would fall through to comparing addresses.
const regexSlot = (source, flags) => {
    const key = flags + ":" + source
    const found = REGEX_IDS.get(key)

    if (found !== undefined) return found

    regexOptions(flags)

    // The letters are built rather than passed through: `u` whether or not it was written, and
    // `m` and `s` exactly as they were. **The pattern text itself is untouched.**
    let letters = "u"

    if (flags.indexOf("i") >= 0) letters += "i"
    if (flags.indexOf("m") >= 0) letters += "m"
    if (flags.indexOf("s") >= 0) letters += "s"

    let re = null
    let first = null

    try {
        re = new RegExp(source, letters + "g")
        first = new RegExp(source, letters)
    } catch (e) {
        $.fault("this is not a regular expression: " + e.message)
    }

    const made = new SRegex(REGEX_TABLE.length)

    REGEX_TABLE.push({ source: source, flags: flags, re: re, first: first })
    REGEX_IDS.set(key, made)

    return made
}

// **Shown as it was written, between slashes**, which is `render.sysl`'s rendering: what a
// reader is shown is what they wrote, not what node was given.
const regexText = (v) => "/" + REGEX_TABLE[v.id].source + "/" + REGEX_TABLE[v.id].flags

// Its own letter as a table key, for the reason every other kind has one: two values holding
// the same number must not collide.
const regexKey = (v) => (v instanceof SRegex ? "R" + v.id : null)

// The functions a program has without writing them.
//
// **A builtin METHOD is the free function of the same name with the receiver in front**, which is
// the interpreter's rule and is why there is one implementation of each: `xs.map(f)` is `map(xs, f)`
// and `s.upper()` is `upper(s)`. Dispatch is on the KIND of the receiver, so `xs.upper()` says an
// array cannot do that rather than reaching `upper` and complaining about its argument.
//
// **An object is not in the table at all.** Its names belong to the program, and `proto` is already
// how one gets methods; a builtin answering there would give every object a `keys` and a `has`
// that nothing put on it.
const $b = (() => {
    const fault = $.fault
    const text = $.text
    const show = $.show
    const typeName = $.typeName

    // **A count is a FLOOR, not a target**, which is `wants` in `text.sysl` and has to stay word
    // for word with it: extra arguments are dropped wherever a call is made, following the
    // language's own call rule, so `high` is no longer a limit and is kept only because every
    // caller names one.
    const wantArgs = (given, low, high, name, takes) => {
        if (given < low)
            fault("`" + name + "` takes " + takes + ", and was given " + given +
                (given === 1 ? " argument" : " arguments"))
    }

    const wantString = (v, name) => {
        if (!$.isStr(v)) fault("`" + name + "` takes a string, and this is " + typeName(v))

        return v
    }

    const wantArray = (v, name) => {
        if (!Array.isArray(v)) fault("`" + name + "` takes an array, and this is " + typeName(v))

        return v
    }

    // `wantArray` for a builtin that is going to WRITE, which a frozen array refuses.
    //
    // **Every mutator asks this and no other site does**, which is `changing_array`'s rule in
    // the interpreter: `sorted` and `reversed` answer new arrays and take a frozen one happily,
    // where `sort` and `reverse` change the array they were given and do not.
    const changingArray = (v, name) => {
        const xs = wantArray(v, name)

        if ($.arrayShut(xs)) fault($.frozenArrayComplaint(name))

        return xs
    }

    // **THE ONE PLACE A BUILTIN TURNS AN INTEGER INTO A MACHINE NUMBER, so the width is tested
    // here and nowhere else.** An integer has no width in slate; a builtin that needs one --
    // a count, a length, a port, a number of milliseconds -- is asking for something a big
    // integer is not, and `typeName` of one says so. Without the test `Number(v)` would round
    // a thirty-digit count into a double and act on it.
    const wantInt = (v, name) => {
        if (!$.isInt(v) || !$.fitsI64(v)) fault("`" + name + "` takes an integer, and this is " + typeName(v))

        return Number(v)
    }

    const wantNum = (v, name) => {
        if (!$.isNum(v)) fault("`" + name + "` takes a number, and this is " + typeName(v))

        return v
    }

    const asReal = (v) => ($.isInt(v) ? Number(v) : v)

    // A number back in the kind it was given, which is what keeps `abs(-2)` an integer.
    // **An integer is already whole, so the four that round hand it straight back** rather than
    // passing it through a double -- which for a value past `2^53` would come back a different
    // number, and past `2^1024` an infinity that `BigInt()` refuses outright.
    const likeIt = (v, x) => ($.isInt(v) ? v : x)

    // **THE ELEMENT, ITS POSITION AND THE ARRAY**, which is what JavaScript's own array
    // methods hand a callback. All three are supplied and `$.callback` drops what the function
    // cannot bind, so `x -> x * 2` reads as it always did and `(x, i) -> x + i` reads the index.
    // The position is a `BigInt`, slate's integer being one.
    //
    // **A BUILTIN HANDED OVER BY NAME GETS THE PLAIN ARGUMENTS AND NO MORE.** A compiled slate
    // function carries its parameter list on `$p` and a builtin does not, which is the same line
    // `apply_walk_callback` draws in the interpreter: `map(strs, number)` must keep working, and
    // JavaScript's `map(parseInt)` is what happens to a language that offers the extras to
    // everything.
    const plainly = (f) => typeof f === "function" && f.$p === undefined

    const of = (v, i, xs, f, native) =>
        $.callback(f, plainly(f) ? [v] : [v, BigInt(i), xs], native)

    const onward = (acc, v, i, xs, f) =>
        $.callback(f, plainly(f) ? [acc, v] : [acc, v, BigInt(i), xs], "reduce")

    const B = {}

    // -- the ones every program has ----------------------------------------------------------------

    B.print = (...args) => {
        $.host.write(args.map(text).join(" "))

        return null
    }

    B.assert = (...args) => {
        wantArgs(args.length, 1, 2, "assert", "a condition and an optional message")

        if ($.truthy(args[0])) return null
        if (args.length === 2) fault(text(args[1]))

        fault("this assertion does not hold")
    }

    // `skip(reason)` -- this test is not going to run here, and why. **It raises**, so nothing
    // after it happens, and the runner reads the verdict off the class rather than off a message.
    B.skip = (...args) => {
        wantArgs(args.length, 1, 1, "skip", "the reason this test is being left out")

        if (typeof args[0] !== "string")
            fault("`skip` takes a reason as text, and this is " + typeName(args[0]))

        throw new $.Skipped(args[0])
    }

    B.assertEq = (...args) => {
        wantArgs(args.length, 2, 3, "assertEq", "what was got, what was wanted, and an optional message")

        if ($.eq(args[0], args[1])) return null

        const said = args.length === 3 ? $.plain(args[2]) + ": " : ""

        fault(said + "got " + $.plainShow(args[0]) + ", wanted " + $.plainShow(args[1]))
    }

    // `assertFaults(fn)` and `assertFaults(fn, message)` -- the call is supposed to raise.
    //
    // **The only assertion that cannot be written as a condition**, a fault leaving the test
    // rather than answering false. `do_assert_faults` in `builtin.sysl` is the other half and
    // every sentence below is that one's, word for word.
    //
    // **An `async` function's fault arrives a turn later, so this answers a PROMISE where it was
    // given one** and the test awaits it. A `skip` travels straight through either way: it is the
    // test's whole verdict and is not the fault the call was asked for.
    B.assertFaults = (...args) => {
        wantArgs(args.length, 1, 2, "assertFaults", "a function of no arguments and an optional part of the message")

        if (args.length === 2 && !$.isStr(args[1]))
            fault("`assertFaults` takes the part of the message it is looking for as text, and this is " + typeName(args[1]))

        const wanted = args.length === 2 ? $.plain(args[1]) : ""

        const judged = (message) => {
            if (wanted !== "" && !message.includes(wanted))
                fault("the fault said \"" + message + "\", wanted it to contain \"" + wanted + "\"")

            return null
        }

        const gotOne = (v) => fault("expected a fault, got a value: " + $.plainShow(v))

        let answered = null

        try {
            answered = $.callback(args[0], [], "assertFaults")
        } catch (e) {
            if (e instanceof $.Skipped) throw e
            if (e instanceof $.Exited) throw e

            return judged($.said(e))
        }

        if (answered instanceof Promise)
            return answered.then(gotOne, (e) => {
                if (e instanceof $.Skipped) throw e
                if (e instanceof $.Exited) throw e

                return judged($.said(e))
            })

        return gotOne(answered)
    }

    // -- length, which three kinds answer -- the free function under `.length` -----------------------

    B.$len = (v) => {
        if (Array.isArray(v)) return BigInt(v.length)

        // **Bytes, because that is what a buffer holds** -- the number a `Content-Length` is.
        if (v instanceof $.SBytes) return BigInt(v.length)
        if ($.isStr(v)) return BigInt($.strLen(v))

        if (v instanceof $.SRange) {
            if (!v.hasLo || !v.hasHi) fault("a range with an end left out has no length until it is used on something")

            return v.count()
        }

        fault("`.length` needs an array, bytes, a string or a range, and this is " + typeName(v))
    }

    // -- text ---------------------------------------------------------------------------------------

    B.chars = (s) => Array.from(wantString(s, "chars"))

    B.split = (s, sep) => {
        wantString(s, "split")
        wantString(sep, "split")

        return sep === "" ? Array.from(s) : s.split(sep)
    }

    B.join = (xs, sep = "") => wantArray(xs, "join").map(text).join(wantString(sep, "join"))

    B.contains = (haystack, needle) => {
        if ($.isStr(haystack)) return haystack.indexOf(wantString(needle, "contains")) >= 0
        if (Array.isArray(haystack)) return haystack.some((x) => $.eq(x, needle))
        if (haystack instanceof $.SBytes) return B.indexOf(haystack, needle) !== null

        fault("`contains` takes a string, an array or bytes, and this is " + typeName(haystack))
    }

    // **`includes` IS `contains`**, under the name JavaScript gave it -- one question about a
    // string and about an array, one implementation, and the sentences say `contains` from
    // either spelling because there is only the one.
    B.includes = B.contains

    // **A miss answers `null`, not `-1`.** slate has no out-of-band integer -- a position is a
    // position and its absence is the absence value -- so `xs.indexOf(v) != null` is how a
    // program asks whether something is there. JavaScript's own `-1` leaking through here made
    // every such test true.
    // **A POSITION MAY BE GIVEN, AND THE RULE IS THE INTERPRETER'S RATHER THAN JAVASCRIPT'S.**
    // JavaScript reads the same argument two ways -- `Array.prototype.indexOf` counts a
    // negative back from the end and `String.prototype.indexOf` clamps it to zero -- and slate
    // dispatches one builtin over both kinds, so one of those readings had to go. Counting back
    // from the end is the one `slice` and `at` already use here.
    //
    // **The position is in CHARACTERS on both sides of the call**, so a string's is turned into
    // a UTF-16 offset on the way in and back into a character count on the way out. That is the
    // same tax `$.strLen` already pays everywhere else.
    const utf16At = (s, chars) => {
        let i = 0
        let seen = 0

        while (i < s.length && seen < chars) {
            i += s.codePointAt(i) > 0xffff ? 2 : 1
            seen += 1
        }

        return i
    }

    // Where a search was told to start, or `null` where that is off the front of the value.
    const searchFrom = (args, name, n, last) => {
        if (args.length !== 2 && args.length !== 3)
            fault("`" + name + "` takes " + (Array.isArray(args[0]) ? "an array" : "a string") +
                ", what to look for and an optional position, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (args.length === 2) return last ? BigInt(n) : 0n

        return fromEnd(args[2], n, name)
    }

    // Where a run of bytes first occurs inside another, or `-1`. The interpreter's `find_run`.
    const findRun = (hay, needle) => {
        if (needle.length === 0) return 0
        if (needle.length > hay.length) return -1

        const last = hay.length - needle.length

        for (let i = 0; i <= last; i++) {
            let same = true

            for (let j = 0; j < needle.length; j++)
                if (hay[i + j] !== needle[j]) { same = false; break }

            if (same) return i
        }

        return -1
    }

    B.indexOf = (...args) => {
        const haystack = args[0]
        const needle = args[1]

        // **A BYTE OR A RUN OF BYTES, and `null` for a miss** -- the interpreter's
        // `do_bytes_index_of`, and it takes no third argument, there being no position form.
        if (haystack instanceof $.SBytes) {
            if (args.length !== 2)
                fault("`indexOf` takes bytes and what to look for, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            const hay = haystack.view()

            if ($.isInt(needle)) {
                if (!$.fitsI64(needle)) fault("a byte is between 0 and 255, and this is " + needle)

                const b = Number(needle)

                if (b < 0 || b > 255) fault("a byte is between 0 and 255, and this is " + b)

                const at = hay.indexOf(b)

                return at < 0 ? null : BigInt(at)
            }

            const found = findRun(hay, $.bytesLike(needle, "indexOf"))

            return found < 0 ? null : BigInt(found)
        }

        if ($.isStr(haystack)) {
            const n = $.strLen(haystack)
            const asked = searchFrom(args, "indexOf", n, false)

            if (asked > BigInt(n)) return null

            const from = utf16At(haystack, asked < 0n ? 0 : Number(asked))
            const at = haystack.indexOf(wantString(needle, "indexOf"), from)

            return at < 0 ? null : BigInt($.strLen(haystack.slice(0, at)))
        }

        if (Array.isArray(haystack)) {
            const n = haystack.length
            const asked = searchFrom(args, "indexOf", n, false)

            if (asked >= BigInt(n)) return null

            for (let i = asked < 0n ? 0 : Number(asked); i < n; i++)
                if ($.eq(haystack[i], needle)) return BigInt(i)

            return null
        }

        fault("`indexOf` takes a string or an array, and this is " + typeName(haystack))
    }

    B.lastIndexOf = (...args) => {
        const haystack = args[0]
        const needle = args[1]

        if ($.isStr(haystack)) {
            const n = $.strLen(haystack)
            const asked = searchFrom(args, "lastIndexOf", n, true)

            if (asked < 0n) return null

            const from = utf16At(haystack, asked > BigInt(n) ? n : Number(asked))
            const at = haystack.lastIndexOf(wantString(needle, "lastIndexOf"), from)

            return at < 0 ? null : BigInt($.strLen(haystack.slice(0, at)))
        }

        if (Array.isArray(haystack)) {
            const n = haystack.length
            const asked = searchFrom(args, "lastIndexOf", n, true)

            if (asked < 0n || n === 0) return null

            for (let i = asked >= BigInt(n) ? n - 1 : Number(asked); i >= 0; i--)
                if ($.eq(haystack[i], needle)) return BigInt(i)

            return null
        }

        fault("`lastIndexOf` takes a string or an array, and this is " + typeName(haystack))
    }

    B.startsWith = (s, p) => wantString(s, "startsWith").startsWith(wantString(p, "startsWith"))
    B.endsWith = (s, p) => wantString(s, "endsWith").endsWith(wantString(p, "endsWith"))
    // **`trim` DOES NOT CALL `String.prototype.trim`, AND NEITHER BACK END CALLS ITS HOST'S.**
    // ECMAScript's whitespace is not the database's `White_Space`: it takes `U+FEFF` off, which
    // the database does not call a space at all, and leaves `U+0085` on, which it does. So the
    // class is spelled here -- the six controls the database files under `Cc`, the `Zs` spaces
    // including the non-breaking one, and the two separators -- and `sysl.unicode.is_space`
    // arrives at the same twenty-five characters from the categories on the other side.
    const $space = "[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+"
    const $front = new RegExp("^" + $space)
    const $back = new RegExp($space + "$")

    B.trim = (s) => wantString(s, "trim").replace($front, "").replace($back, "")
    B.trimStart = (s) => wantString(s, "trimStart").replace($front, "")
    B.trimEnd = (s) => wantString(s, "trimEnd").replace($back, "")

    // **CASE IS THE HOST'S HERE, AND THE INTERPRETER IS THE SIDE THAT WAS WRITTEN TO AGREE.**
    // `upper` and `lower` used to be two regular expressions over `[a-z]`, matching an
    // interpreter that had no case table; the table arrived, so what the two have to answer is
    // Unicode's mapping, and a host already has it. Every code point there is was run through
    // both and the answers compared, which is what says these are one operation and not two.
    B.upper = (s) => wantString(s, "upper").toUpperCase()
    B.lower = (s) => wantString(s, "lower").toLowerCase()

    // JavaScript's spelling of the same two, and the same implementations -- see `install_case`.
    B.toUpperCase = B.upper
    B.toLowerCase = B.lower

    // **The four forms are named rather than numbered, and an unknown one is refused naming all
    // four** -- a program that asked for `"nfc"` and silently got NFD would produce text that
    // compares equal to nothing.
    B.normalize = (s, form) => {
        wantString(s, "normalize")

        // **"a form" and not "a string"**, which is what the interpreter's own sentence says --
        // the two are one message and a corpus file compares them character for character.
        if (!$.isStr(form)) fault("`normalize` takes a form, and this is " + typeName(form))

        if (form !== "NFC" && form !== "NFD" && form !== "NFKC" && form !== "NFKD")
            fault("`normalize` takes one of \"NFC\", \"NFD\", \"NFKC\" and \"NFKD\", and this is \"" + form + "\"")

        return s.normalize(form)
    }

    // **CASE FOLDING IS THE ONE OF THE FOUR A HOST DOES NOT HAVE**, so it is written out: the
    // text is decomposed, every code point is mapped, and the result is composed again --
    // `NFC(fold(NFD(s)))`, which is the standard's own caseless match and is what
    // `sysl.unicode.fold` computes on the other side.
    //
    // **`toLowerCase` OF ONE CHARACTER IS THE MAPPING FOR ALL BUT TWO HUNDRED AND NINE OF THEM**,
    // and `$folded` is those. Folding differs from lowercasing in three ways and the table is the
    // three of them together: the characters that fold to more than one (`ß` to `ss`, `ﬁ` to
    // `fi`); the ones that fold ACROSS an alphabet rather than down it (`µ` to a Greek mu,
    // `ſ` to `s`, a final sigma back to a plain one, the combining iota to a letter); and
    // Cherokee, whose fold is to UPPER case -- the one script in the database that runs that way,
    // and eighty-six of the entries.
    //
    // **IT IS GENERATED, not transcribed.** Every code point was folded by the interpreter and
    // lowercased by node, and what disagreed is what is written here; `tests/js/p25.sl` is the
    // corpus that keeps it honest.
    //
    // **A character is looked up per code point and NOT per UTF-16 unit**, which is what the
    // `for...of` is for: a surrogate pair is one character and `s[i]` would hand half of one to
    // `toLowerCase`.
    const $folded = (() => {
        const table =
        "b5:3bc df:73,73 149:2bc,6e 17f:73 345:3b9 3c2:3c3 3d0:3b2 3d1:3b8 3d5:3c6 3d6:3c0 3f0:3ba " +
        "3f1:3c1 3f5:3b5 587:565,582 13a0:13a0 13a1:13a1 13a2:13a2 13a3:13a3 13a4:13a4 13a5:13a5 " +
        "13a6:13a6 13a7:13a7 13a8:13a8 13a9:13a9 13aa:13aa 13ab:13ab 13ac:13ac 13ad:13ad 13ae:13ae " +
        "13af:13af 13b0:13b0 13b1:13b1 13b2:13b2 13b3:13b3 13b4:13b4 13b5:13b5 13b6:13b6 13b7:13b7 " +
        "13b8:13b8 13b9:13b9 13ba:13ba 13bb:13bb 13bc:13bc 13bd:13bd 13be:13be 13bf:13bf 13c0:13c0 " +
        "13c1:13c1 13c2:13c2 13c3:13c3 13c4:13c4 13c5:13c5 13c6:13c6 13c7:13c7 13c8:13c8 13c9:13c9 " +
        "13ca:13ca 13cb:13cb 13cc:13cc 13cd:13cd 13ce:13ce 13cf:13cf 13d0:13d0 13d1:13d1 13d2:13d2 " +
        "13d3:13d3 13d4:13d4 13d5:13d5 13d6:13d6 13d7:13d7 13d8:13d8 13d9:13d9 13da:13da 13db:13db " +
        "13dc:13dc 13dd:13dd 13de:13de 13df:13df 13e0:13e0 13e1:13e1 13e2:13e2 13e3:13e3 13e4:13e4 " +
        "13e5:13e5 13e6:13e6 13e7:13e7 13e8:13e8 13e9:13e9 13ea:13ea 13eb:13eb 13ec:13ec 13ed:13ed " +
        "13ee:13ee 13ef:13ef 13f0:13f0 13f1:13f1 13f2:13f2 13f3:13f3 13f4:13f4 13f5:13f5 13f8:13f0 " +
        "13f9:13f1 13fa:13f2 13fb:13f3 13fc:13f4 13fd:13f5 1c80:432 1c81:434 1c82:43e 1c83:441 1c84:442 " +
        "1c85:442 1c86:44a 1c87:463 1c88:a64b 1e9a:61,2be 1e9e:73,73 ab70:13a0 ab71:13a1 ab72:13a2 " +
        "ab73:13a3 ab74:13a4 ab75:13a5 ab76:13a6 ab77:13a7 ab78:13a8 ab79:13a9 ab7a:13aa ab7b:13ab " +
        "ab7c:13ac ab7d:13ad ab7e:13ae ab7f:13af ab80:13b0 ab81:13b1 ab82:13b2 ab83:13b3 ab84:13b4 " +
        "ab85:13b5 ab86:13b6 ab87:13b7 ab88:13b8 ab89:13b9 ab8a:13ba ab8b:13bb ab8c:13bc ab8d:13bd " +
        "ab8e:13be ab8f:13bf ab90:13c0 ab91:13c1 ab92:13c2 ab93:13c3 ab94:13c4 ab95:13c5 ab96:13c6 " +
        "ab97:13c7 ab98:13c8 ab99:13c9 ab9a:13ca ab9b:13cb ab9c:13cc ab9d:13cd ab9e:13ce ab9f:13cf " +
        "aba0:13d0 aba1:13d1 aba2:13d2 aba3:13d3 aba4:13d4 aba5:13d5 aba6:13d6 aba7:13d7 aba8:13d8 " +
        "aba9:13d9 abaa:13da abab:13db abac:13dc abad:13dd abae:13de abaf:13df abb0:13e0 abb1:13e1 " +
        "abb2:13e2 abb3:13e3 abb4:13e4 abb5:13e5 abb6:13e6 abb7:13e7 abb8:13e8 abb9:13e9 abba:13ea " +
        "abbb:13eb abbc:13ec abbd:13ed abbe:13ee abbf:13ef fb00:66,66 fb01:66,69 fb02:66,6c fb03:66,66,69 " +
        "fb04:66,66,6c fb05:73,74 fb06:73,74 fb13:574,576 fb14:574,565 fb15:574,56b fb16:57e,576 " +
        "fb17:574,56d"
        const m = Object.create(null)

        for (const pair of table.split(" ")) {
            const cut = pair.indexOf(":")
            const to = pair.slice(cut + 1).split(",").map((h) => String.fromCodePoint(parseInt(h, 16))).join("")

            m[String.fromCodePoint(parseInt(pair.slice(0, cut), 16))] = to
        }

        return m
    })()

    B.casefold = (s) => {
        let out = ""

        for (const c of wantString(s, "casefold").normalize("NFD")) {
            const mapped = $folded[c]

            out += mapped === undefined ? c.toLowerCase() : mapped
        }

        return out.normalize("NFC")
    }

    // **EVERY occurrence, which is the interpreter's rule and is why `replaceAll` is the same
    // function.** JavaScript's `replace` changes the first and `replaceAll` changes them all,
    // which is the distinction nobody remembers the right way round; slate has one behaviour and
    // two names for it.
    //
    // **The empty needle is a FAULT and used to be answered with the string unchanged**, which
    // the interpreter has always refused: there is an empty string between every pair of
    // characters, so replacing it has no meaning that is not an argument about where the ends
    // are. The two back ends disagreed about that call until this line said the same thing.
    B.replace = (s, from, to) => {
        wantString(s, "replace")
        wantString(from, "replace")
        wantString(to, "replace")

        if (from === "")
            fault("`replace` cannot replace the empty string -- there is one of it between every pair of characters")

        return s.split(from).join(to)
    }

    B.replaceAll = B.replace

    B.repeat = (s, n) => {
        wantString(s, "repeat")

        const k = wantInt(n, "repeat")

        if (k < 0) fault("`repeat` takes a count that is not negative, and this is " + n)

        // A count the machine cannot honour is a fault with a sentence, not a `RangeError`
        // out of the engine. The bound is on the UTF-8 bytes the interpreter would make, so
        // both back ends refuse the same counts. `s.length` counts UTF-16 units and a unit is
        // never more than three UTF-8 bytes, so `3 * s.length` is a ceiling on the byte count
        // and screens cheaply -- only a candidate pays for the walk that counts them exactly.
        const limit = 2147483648

        if (s.length > 0 && k > limit / (3 * s.length)) {
            let wide = 0

            for (const c of s) {
                const p = c.codePointAt(0)

                wide += p < 0x80 ? 1 : p < 0x800 ? 2 : p < 0x10000 ? 3 : 4
            }

            if (k > limit / wide)
                fault("`repeat` was asked for " + n + " copies of a " + wide +
                    "-byte string, and the result would be past the 2147483648 bytes a string can hold")
        }

        return s.repeat(k)
    }

    // `padStart(s, n)` and `padEnd(s, n)`, with an optional filler.
    //
    // **The width is in CHARACTERS and JavaScript's own `padStart` counts UTF-16 units**, so
    // this cannot be handed to it: a name with an emoji in it would come out a column short.
    // `Array.from` is the character walk everything else here already pays for.
    const padded = (args, name, start) => {
        if (args.length !== 2 && args.length !== 3)
            fault("`" + name + "` takes a string, a width and an optional filler, and was given " +
                args.length + (args.length === 1 ? " argument" : " arguments"))

        const s = wantString(args[0], name)

        if (!$.isInt(args[1]))
            fault("`" + name + "` takes a whole number of characters, and this is " + typeName(args[1]))

        if (args[1] < 0n)
            fault("`" + name + "` takes a width that is not negative, and this is " + args[1])

        const width = Number(args[1])
        const filler = args.length === 3 ? wantString(args[2], name) : " "

        if (filler === "")
            fault("`" + name + "` cannot pad with the empty string -- no amount of it reaches a width")

        const have = Array.from(s)

        if (have.length >= width) return s

        const each = Array.from(filler)
        const short = width - have.length
        let pad = ""
        let made = 0

        while (made < short) {
            const room = short - made

            if (room >= each.length) { pad += filler; made += each.length }
            else { pad += each.slice(0, room).join(""); made += room }
        }

        return start ? pad + s : s + pad
    }

    B.padStart = (...args) => padded(args, "padStart", true)
    B.padEnd = (...args) => padded(args, "padEnd", false)

    // -- numbers ----------------------------------------------------------------------------------

    // `number` reads either kind out of a string, and answers an integer where the text held one.
    // **`number` ANSWERS `null` FOR TEXT THAT IS NOT ONE**, and that is the whole reason the
    // three of these are written out rather than handed to JavaScript's own `Number`. `Number`
    // trims both ends, reads `""` as `0`, and has no way to say "no"; the interpreter reads an
    // integer strictly and then falls back to `strtod`, which skips leading blanks, refuses
    // trailing ones, and takes `0x10`, `inf` and `nan`. So `number("12 ")` is `null` and
    // `number(" 12")` is `12` -- as a real, the integer path having refused the blank.
    B.number = (v) => {
        if ($.isNum(v)) return v

        const s = wantString(v, "number")

        if (/^[+-]?[0-9]+$/.test(s)) {
            const n = BigInt(s)

            // A `BigInt` cannot carry the sign of zero -- `-0n` and `0n` are one value -- so
            // the one text this integer path cannot answer for is the one denoting `-0`
            // itself, which is answered as the real `-0` instead, agreeing with the interpreter.
            if (n === 0n && s.startsWith("-")) return -0

            // **NO WIDTH TEST ANY MORE.** A run of digits is a whole number however many of
            // them there are, so the range check that used to send a thirty-digit text off to
            // `strtod` -- where it came back a rounded real -- is gone with the 64-bit rule
            // it enforced.
            return n
        }

        const x = strtod(s)

        return x === undefined ? null : x
    }

    // `strtod`'s grammar, and nothing outside it: leading blanks, then a decimal number, a
    // hexadecimal one, an infinity or a NaN -- and the whole of the rest of the text has to be
    // part of it. `undefined` is "not a number", which is not a value slate has.
    function strtod(s) {
        const m = /^[ \t\n\v\f\r]*([+-]?)(?:0[xX](?:([0-9a-fA-F]*)(?:\.([0-9a-fA-F]*))?)(?:[pP]([+-]?[0-9]+))?|(?:([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?)|(inf(?:inity)?)|(nan)(?:\([0-9a-zA-Z_]*\))?)$/i.exec(s)

        if (m === null) return undefined

        const sign = m[1] === "-" ? -1 : 1

        if (m[8] !== undefined) return sign * Infinity
        if (m[9] !== undefined) return NaN

        // A hexadecimal literal: at least one digit somewhere, and `p` is the exponent of two.
        if (m[2] !== undefined || m[3] !== undefined) {
            const whole = m[2] || ""
            const frac = m[3] || ""

            if (whole === "" && frac === "") return undefined

            let x = 0

            for (const c of whole) x = x * 16 + parseInt(c, 16)
            for (let i = 0; i < frac.length; i++) x += parseInt(frac[i], 16) / Math.pow(16, i + 1)

            return sign * x * Math.pow(2, m[4] === undefined ? 0 : Number(m[4]))
        }

        const whole = m[5] || ""
        const frac = m[6] || ""

        // `"."`, `"e5"` and `""` all reach here with no digits, and none of them is a number.
        if (whole === "" && frac === "") return undefined

        return sign * Number(whole + "." + (frac === "" ? "0" : frac) + (m[7] === undefined ? "" : "e" + m[7]))
    }

    // **`integer` and `real` take a NUMBER**, and the interpreter's message says so and points at
    // `number` for the other case. Reading a string here would make a program that node runs one
    // the interpreter refuses.
    B.integer = (v) => {
        if ($.isInt(v)) return v

        // **`BigInt()` of a whole double is exact at every magnitude**, which is what makes
        // `integer(1e30)` the number that double actually holds -- and it throws for an
        // infinity or a NaN, which have no integer in them at all.
        if ($.isReal(v)) {
            if (!Number.isFinite(v)) fault("`integer` takes a number with an integer in it, and this is " + $.realText(v))

            return BigInt(Math.trunc(v))
        }

        fault("`integer` takes a number, and this is " + typeName(v) + " -- `number` is what reads one out of a string")
    }

    B.real = (v) => {
        if ($.isReal(v)) return v
        if ($.isInt(v)) return Number(v)

        fault("`real` takes a number, and this is " + typeName(v))
    }

    B.boolean = (v) => $.truthy(v)

    B.abs = (v) => {
        wantNum(v, "abs")

        return $.isInt(v) ? (v < 0n ? -v : v) : Math.abs(v)
    }

    B.floor = (v) => likeIt(wantNum(v, "floor"), Math.floor(asReal(v)))
    B.ceil = (v) => likeIt(wantNum(v, "ceil"), Math.ceil(asReal(v)))
    B.trunc = (v) => likeIt(wantNum(v, "trunc"), Math.trunc(asReal(v)))
    B.round = (v) => likeIt(wantNum(v, "round"), Math.round(asReal(v)))
    B.sqrt = (v) => Math.sqrt(asReal(wantNum(v, "sqrt")))

    // **THESE ARE `Number.isNaN` AND `Number.isFinite`, NOT THE BARE GLOBALS JAVASCRIPT ALSO
    // HAS.** Nothing is converted, so a value that is not a number is simply not NaN and is not
    // finite either -- `isNaN("x")` is `false` here where JavaScript's global says `true`. An
    // integer is a `BigInt` and is always both whole and finite, which is what the second test
    // says.
    B.isNaN = (v) => $.isReal(v) && Number.isNaN(v)
    B.isFinite = (v) => ($.isReal(v) ? Number.isFinite(v) : $.isInt(v))

    // **`pow` keeps the kind it was given**, so an integer raised to an integer goes where an
    // integer goes.
    B.pow = (a, b) => {
        wantNum(a, "pow")
        wantNum(b, "pow")

        // **It grows**, so `pow(2, 100)` is the number. The size is bounded for the reason a
        // shift is: `pow(10, 10n ** 9n)` is a number with a billion digits, and the allocator
        // giving up is not a diagnostic. The bound is on the ANSWER's bits, which is what the
        // interpreter bounds, so both hosts refuse the same call.
        if ($.isInt(a) && $.isInt(b) && b >= 0n) {
            const bits = a < 0n ? (-a).toString(2).length : a === 0n ? 0 : a.toString(2).length

            if (bits > 1 && BigInt(bits) * b > $.MaxShift)
                $.fault("`pow` would build a number of about " + BigInt(bits) * b + " bits, and slate stops at " + $.MaxShift)

            return a ** b
        }

        return Math.pow(asReal(a), asReal(b))
    }

    B.min = (...args) => extremum(args, "min", -1)
    B.max = (...args) => extremum(args, "max", 1)

    // One argument in, one real out -- `Math.*` under slate's own names. **A domain error
    // answers `nan` or `-Infinity` rather than faulting**, exactly as the `Math.*` function
    // being wrapped does, so the two back ends never have to agree about a fault the host
    // itself does not raise.
    const trig1 = (name, f) => (...args) => {
        wantArgs(args.length, 1, 1, name, "one number")

        return f(asReal(wantNum(args[0], name)))
    }

    B.sin = trig1("sin", Math.sin)
    B.cos = trig1("cos", Math.cos)
    B.tan = trig1("tan", Math.tan)
    B.asin = trig1("asin", Math.asin)
    B.acos = trig1("acos", Math.acos)
    B.atan = trig1("atan", Math.atan)
    B.sinh = trig1("sinh", Math.sinh)
    B.cosh = trig1("cosh", Math.cosh)
    B.tanh = trig1("tanh", Math.tanh)
    B.log = trig1("log", Math.log)
    B.log2 = trig1("log2", Math.log2)
    B.log10 = trig1("log10", Math.log10)
    B.exp = trig1("exp", Math.exp)
    B.cbrt = trig1("cbrt", Math.cbrt)

    // `atan2(y, x)` and `hypot(a, b)` -- the two-argument cases, in `Math.atan2`'s own order.
    B.atan2 = (...args) => {
        wantArgs(args.length, 2, 2, "atan2", "two numbers")

        return Math.atan2(asReal(wantNum(args[0], "atan2")), asReal(wantNum(args[1], "atan2")))
    }

    B.hypot = (...args) => {
        wantArgs(args.length, 2, 2, "hypot", "two numbers")

        return Math.hypot(asReal(wantNum(args[0], "hypot")), asReal(wantNum(args[1], "hypot")))
    }

    // **`PI` and `E` are VALUES, not functions**, so they are simply `Math.PI` and `Math.E`
    // rather than a zero-argument entry in `trig1`'s table.
    B.PI = Math.PI
    B.E = Math.E

    // **`random()` IS `Math.random()` here**, the host's generator being the one thing this back
    // end would otherwise be reimplementing for no gain: both answer a real in `[0, 1)` from 53
    // bits, and neither is a source of secrets -- `randomBytes` in `slate:crypto` is.
    B.random = (...args) => {
        wantArgs(args.length, 0, 0, "random", "no arguments")

        return Math.random()
    }

    const extremum = (args, name, want) => {
        const xs = args.length === 1 && Array.isArray(args[0]) ? args[0] : args

        if (xs.length === 0) fault("`" + name + "` takes at least one number")

        let best = wantNum(xs[0], name)

        for (const x of xs) {
            wantNum(x, name)

            if ($.compare(want > 0 ? ">" : "<", x, best)) best = x
        }

        return best
    }

    // `toFixed(x, digits)` -- the number written to exactly that many decimal places, as text.
    //
    // **This is the one place the HOST'S OWN function is the right implementation and the
    // interpreter's is the hard half.** JavaScript's `toFixed` is defined exactly -- the integer
    // nearest to `x * 10^d`, a tie going to the larger -- and the interpreter reproduces it with
    // exact integer arithmetic, because C's `printf` rounds a tie to the even digit instead and
    // would have made the two disagree about every price ending in half a cent.
    //
    // **An integer is written out rather than measured.** `Number(9007199254740993n)` is a
    // different number, so a `BigInt` gets its own digits and a run of zeros.
    B.toFixed = (...args) => {
        wantArgs(args.length, 2, 2, "toFixed", "a number and how many places")

        if (!$.isInt(args[1]))
            fault("`toFixed` takes a whole number of places, and this is " + typeName(args[1]))

        if (args[1] < 0n || args[1] > 100n)
            fault("`toFixed` writes from 0 to 100 places, and was asked for " + args[1])

        const places = Number(args[1])
        const x = args[0]

        if ($.isInt(x)) return x.toString() + (places > 0 ? "." + "0".repeat(places) : "")

        if (!$.isReal(x)) fault("`toFixed` takes a number, and this is " + typeName(x))

        // JavaScript's own `toFixed` never faults on the number: `NaN` answers `"NaN"` and past
        // `1e21` -- infinite included -- it gives up on decimal places and answers `String(x)`,
        // which the host's own `toString` already writes byte-identical to the interpreter's
        // `real_text` for this. Letting the host answer both is exact rather than a shortcut.
        if (Number.isNaN(x)) return "NaN"
        if (x >= 1e21 || x <= -1e21) return x.toString()

        return x.toFixed(places)
    }

    // `formatNumber(x)` and `formatNumber(x, { separator: ",", decimal: "." })`.
    //
    // **No `toLocaleString`, which is what this looks like and deliberately is not.** That answers
    // differently on two machines and differently again between node builds compiled with and
    // without ICU, so a program printing a total would print a different total under test than in
    // production. Two strings say the same thing for every grouping convention there is and say it
    // where the program can see them.
    B.formatNumber = (...args) => {
        wantArgs(args.length, 1, 2, "formatNumber", "a number and an optional record")

        const v = args[0]
        let plain

        if ($.isInt(v)) plain = v.toString()
        else if ($.isReal(v))
            fault("`formatNumber` groups a whole number or the text `toFixed` answered -- a real has no one written form, `string` giving the shortest text that reads back, so say how many places you want with `toFixed(x, 2)`")
        else if ($.isStr(v)) plain = v
        else fault("`formatNumber` takes a number, and this is " + typeName(v))

        let separator = ","
        let decimal = "."

        if (args.length === 2) {
            const o = args[1]

            if (!(o instanceof $.SObj))
                fault("`formatNumber` takes its options as a record, and this is " + typeName(o))

            for (const [k] of fieldsOf(o))
                if (k !== "separator" && k !== "decimal")
                    fault("`" + k + "` is not one of `formatNumber`'s options -- there are `separator` and `decimal`")

            const said = (key, fallback) => {
                const held = o.getKey(key)

                if (held === undefined) return fallback
                if (!$.isStr(held)) fault("`" + key + "` is text, and this is " + typeName(held))

                return held
            }

            separator = said("separator", ",")
            decimal = said("decimal", ".")
        }

        const bad = () =>
            fault("`formatNumber` groups the digits of a number written in full, and \"" + plain + "\" is not one")

        let whole = ""
        let frac = ""
        let negative = false
        let after = false
        let seen = 0

        for (let i = 0; i < plain.length; i++) {
            const c = plain[i]

            if (i === 0 && c === "-") negative = true
            else if (c === "." && !after) after = true
            else if (c >= "0" && c <= "9") { if (after) frac += c; else whole += c; seen += 1 }
            else bad()
        }

        if (seen === 0) bad()

        let out = negative ? "-" : ""

        if (whole.length === 0) out += "0"
        else
            for (let i = 0; i < whole.length; i++) {
                if (i > 0 && (whole.length - i) % 3 === 0) out += separator

                out += whole[i]
            }

        return after ? out + decimal + frac : out
    }

    // -- arrays ------------------------------------------------------------------------------------

    B.push = (xs, ...vs) => {
        // **ONE BYTE OR A WHOLE BUFFER**, and the second is the reason the kind exists: appending
        // a buffer to another is a `set` into room already taken rather than a loop in slate.
        if (xs instanceof $.SBytes) {
            if (xs.frozen) fault($.frozenBytesComplaint("push"))

            for (const v of vs) {
                if (v instanceof $.SBytes) xs.pushBytes(v)
                else if ($.isInt(v)) xs.pushByte(wantByteValue(v))
                else fault("`push` onto bytes takes a byte or more bytes, and this is " + typeName(v))
            }

            return null
        }

        if (!Array.isArray(xs)) fault("`push` needs an array or bytes, and this is " + typeName(xs))

        if ($.arrayShut(xs)) fault($.frozenArrayComplaint("push"))

        for (const v of vs) xs.push($.keep(v, "put in an array"))

        return null
    }

    // A byte a program wrote as a number, or the complaint about what it wrote instead.
    const wantByteValue = (v) => {
        const b = Number(v)

        if (b < 0 || b > 255) fault("a byte is between 0 and 255, and this is " + b)

        return b
    }

    B.pop = (xs) => {
        changingArray(xs, "pop")

        if (xs.length === 0) fault("there is nothing to pop off an empty array")

        return xs.pop()
    }

    // **A negative position counts back from the END**, which is the whole reason `at` and
    // `slice` take one where `xs[i]` cannot.
    const fromEnd = (i, n, name) => {
        if (typeof i !== "bigint") fault("`" + name + "` takes a position, and this is " + typeName(i))

        return i < 0n ? BigInt(n) + i : i
    }

    const clamped = (i, n) => (i < 0n ? 0 : i > BigInt(n) ? n : Number(i))

    // A slice is a question about whatever part of the array is there, so both ends clamp and
    // crossed ends answer nothing rather than a reversed array.
    B.slice = (xs, from, to) => {
        // **A copy, for the interpreter's reason**: a view whose source is then `push`ed would
        // answer bytes the program never put in it.
        if (xs instanceof $.SBytes) {
            const n = xs.length
            const lo = clamped(fromEnd(from, n, "slice"), n)
            const hi = to === undefined ? n : clamped(fromEnd(to, n, "slice"), n)

            return $.bytesOf(hi > lo ? xs.view().slice(lo, hi) : new Uint8Array(0))
        }

        wantArray(xs, "slice")

        const n = xs.length
        const lo = clamped(fromEnd(from, n, "slice"), n)
        const hi = to === undefined ? n : clamped(fromEnd(to, n, "slice"), n)

        return hi > lo ? xs.slice(lo, hi) : []
    }

    // **Out of range is a fault and not an absent value**, which is `xs[i]`'s rule and `pop`'s.
    B.at = (xs, i) => {
        // **A string counts in CHARACTERS**, as every other name on a string does -- so
        // `"a👋".at(-1)` is the wave and not half of it.
        if ($.isStr(xs)) {
            const n = $.strLen(xs)
            const k = fromEnd(i, n, "at")

            if (k < 0n || k >= BigInt(n))
                fault("`at` was given the position " + i + ", and this string has " + n + " of them")

            return $.strAt(xs, k)
        }

        if (xs instanceof $.SBytes) {
            const n = xs.length
            const k = fromEnd(i, n, "at")

            if (k < 0n || k >= BigInt(n))
                fault("`at` was given the position " + i + ", and these bytes have " + n + " of them")

            return BigInt(xs.at(Number(k)))
        }

        wantArray(xs, "at")

        const n = xs.length
        const k = fromEnd(i, n, "at")

        if (k < 0n || k >= BigInt(n))
            fault("`at` was given the position " + i + ", and this array has " + n + " of them")

        return xs[Number(k)]
    }

    B.shift = (xs) => {
        changingArray(xs, "shift")

        if (xs.length === 0) fault("there is nothing to shift off an empty array")

        return xs.shift()
    }

    // Nothing is handed back, which is `push`'s rule rather than JavaScript's own `unshift`.
    B.unshift = (xs, v) => {
        changingArray(xs, "unshift")
        $.keep(v, "stored")
        xs.unshift(v)

        return null
    }

    B.insert = (xs, at, v) => {
        changingArray(xs, "insert")

        const i = wantInt(at, "insert")

        if (i < 0 || i > xs.length)
            fault("this array has " + xs.length + " items, and " + i + " is not a place to insert at")

        xs.splice(i, 0, $.keep(v, "put in an array"))

        return null
    }

    B.removeAt = (xs, at) => {
        changingArray(xs, "removeAt")

        const i = wantInt(at, "removeAt")

        if (i < 0 || i >= xs.length)
            fault("this array has " + xs.length + " items, and " + i + " is not one of them")

        return xs.splice(i, 1)[0]
    }

    B.clear = (xs) => {
        if (xs instanceof $.SBytes) {
            if (xs.frozen) fault($.frozenBytesComplaint("clear"))

            xs.n = 0

            return null
        }

        changingArray(xs, "clear").length = 0

        return null
    }

    B.map = (xs, f) => wantArray(xs, "map").map((x, i, a) => of(x, i, a, f, "map"))
    B.filter = (xs, f) => wantArray(xs, "filter").filter((x, i, a) => $.truthy(of(x, i, a, f, "filter")))
    B.find = (xs, f) => {
        const found = wantArray(xs, "find").find((x, i, a) => $.truthy(of(x, i, a, f, "find")))

        return found === undefined ? null : found
    }
    B.findLast = (xs, f) => {
        const found = wantArray(xs, "findLast").findLast((x, i, a) => $.truthy(of(x, i, a, f, "findLast")))

        return found === undefined ? null : found
    }
    B.findLastIndex = (xs, f) => {
        const at = wantArray(xs, "findLastIndex").findLastIndex((x, i, a) => $.truthy(of(x, i, a, f, "findLastIndex")))

        return at < 0 ? null : BigInt(at)
    }

    // `map` then `flat` in one walk, which is the case neither handles alone.
    B.flatMap = (xs, f) => {
        const out = []

        const ys = wantArray(xs, "flatMap")

        for (let i = 0; i < ys.length; i++) {
            const said = of(ys[i], i, ys, f, "flatMap")

            if (Array.isArray(said)) out.push(...said); else out.push(said)
        }

        return out
    }

    // For what it does rather than what it answers, so nothing is handed back.
    B.forEach = (xs, f) => {
        const ys = wantArray(xs, "forEach")

        for (let i = 0; i < ys.length; i++) of(ys[i], i, ys, f, "forEach")

        return null
    }
    B.findIndex = (xs, f) => {
        const at = wantArray(xs, "findIndex").findIndex((x, i, a) => $.truthy(of(x, i, a, f, "findIndex")))

        return at < 0 ? null : BigInt(at)
    }
    B.every = (xs, f) => wantArray(xs, "every").every((x, i, a) => $.truthy(of(x, i, a, f, "every")))
    B.some = (xs, f) => wantArray(xs, "some").some((x, i, a) => $.truthy(of(x, i, a, f, "some")))

    B.reduce = (xs, f, start) => {
        wantArray(xs, "reduce")

        if (start === undefined) {
            if (xs.length === 0) fault("`reduce` was given an array with nothing in it and no value to start from")

            let acc = xs[0]

            for (let i = 1; i < xs.length; i++) acc = onward(acc, xs[i], i, xs, f)

            return acc
        }

        let acc = start

        for (let i = 0; i < xs.length; i++) acc = onward(acc, xs[i], i, xs, f)

        return acc
    }

    // `sort` orders in place and `sorted` answers a new array, which is the pair every one of these
    // comes in.
    const ordered = (xs, f) => {
        const copy = xs.slice()

        copy.sort((a, b) => {
            if (f !== undefined) {
                // **A COMPARATOR ANSWERS A BOOLEAN, WHICH THIS DEMANDED A NUMBER FOR.** slate's
                // rule is `sorted(xs, (a, b) -> a.age < b.age)` -- a `-1`/`0`/`1` comparator
                // would read as "yes, yes, yes" here, zero being TRUE in slate, and sort
                // nothing. So the interpreter refuses a number and this refused a boolean, and
                // the documented idiom faulted under `slate js` and nowhere else.
                //
                // **Two calls per comparison rather than one**, because JavaScript's `sort`
                // wants a sign and a boolean carries only half of it. Asking the other way round
                // for the `1` is what keeps equal elements answering `0` -- and stability is
                // exactly what a merge sort is chosen for on the other side.
                const said = $.callback(f, [a, b], "sorted")

                if (typeof said !== "boolean")
                    fault("a comparator answers whether the first value comes before the second, and this answered " + typeName(said))

                if (said) return -1

                return $.truthy($.callback(f, [b, a], "sorted")) ? 1 : 0
            }

            if ($.compare("<", a, b)) return -1

            return $.compare(">", a, b) ? 1 : 0
        })

        return copy
    }

    B.sorted = (xs, f) => ordered(wantArray(xs, "sorted"), f)

    B.sort = (xs, f) => {
        const done = ordered(changingArray(xs, "sort"), f)

        for (let i = 0; i < done.length; i++) xs[i] = done[i]

        return null
    }

    B.reversed = (xs) => wantArray(xs, "reversed").slice().reverse()

    // JavaScript's spelling of `reversed`, and the same implementation -- see `install_array`.
    B.toReversed = B.reversed

    B.reverse = (xs) => {
        changingArray(xs, "reverse").reverse()

        return null
    }

    B.concat = (xs, ...more) => {
        // **Bytes join bytes and arrays join arrays, decided by the FIRST argument** -- the
        // receiver, `b.concat(c)` being `concat(b, c)`. An array of numbers is taken beside a
        // buffer, which is what keeps the old shape working.
        if (xs instanceof $.SBytes) {
            const parts = [xs.view()].concat(more.map((v) => $.bytesLike(v, "concat")))
            let total = 0

            for (const p of parts) total += p.length

            const made = new Uint8Array(total)
            let put = 0

            for (const p of parts) { made.set(p, put); put += p.length }

            return $.bytesOf(made)
        }

        wantArray(xs, "concat")

        let out = xs.slice()

        for (const other of more) out = out.concat(wantArray(other, "concat"))

        return out
    }

    B.flat = (xs) => {
        wantArray(xs, "flat")

        const out = []

        for (const x of xs) if (Array.isArray(x)) out.push(...x); else out.push(x)

        return out
    }

    B.sum = (xs) => {
        wantArray(xs, "sum")

        let total = 0n

        for (const x of xs) total = $.arith("+", total, x)

        return total
    }

    // -- the eight that answer a DIFFERENT SHAPE ---------------------------------------------------
    //
    // **`reshape.sysl` is the other half of every one of these and carries the reasons**: the key
    // `groupBy` renders, the shortest array deciding `zip`'s length, `chunk` refusing a size of
    // nothing, `unique` asking `==`, and `minBy` answering the ELEMENT rather than the key.

    // **A callback may change the array it is walking, and the bound was read before it ran.** The
    // interpreter refuses that rather than reading past the end -- there, the sentence would be a
    // sysl panic about a `Buf` with no line in it -- so this refuses in the same words.
    const stillWalking = (xs, n, name) => {
        if (xs.length !== n)
            fault("this array was changed while `" + name + "` was walking it -- walk a copy of it, or build a new array rather than changing this one")
    }

    B.groupBy = (...args) => {
        wantArgs(args.length, 2, 2, "groupBy", "an array and a function")

        const xs = wantArray(args[0], "groupBy")
        const n = xs.length
        const out = new $.SObj()

        for (let i = 0; i < n; i++) {
            const x = xs[i]

            // **The key is `string(f(x))`**, so the answer is an ordinary record whose `keys()`
            // are text and which `toJSON` writes.
            const key = text(of(x, i, xs, args[1], "groupBy"))

            stillWalking(xs, n, "groupBy")

            const group = out.getKey(key)

            if (group === undefined) out.setKey(key, [x]); else group.push(x)
        }

        return out
    }

    B.partition = (...args) => {
        wantArgs(args.length, 2, 2, "partition", "an array and a function")

        const xs = wantArray(args[0], "partition")
        const n = xs.length
        const yes = []
        const no = []

        for (let i = 0; i < n; i++) {
            const said = $.truthy(of(xs[i], i, xs, args[1], "partition"))

            stillWalking(xs, n, "partition")

            if (said) yes.push(xs[i]); else no.push(xs[i])
        }

        return [yes, no]
    }

    B.chunk = (...args) => {
        wantArgs(args.length, 2, 2, "chunk", "an array and a size")

        const xs = wantArray(args[0], "chunk")

        if (!$.isInt(args[1]))
            fault("`chunk` takes a whole number, and this is " + typeName(args[1]))

        if (args[1] <= 0n)
            fault("`chunk` takes a size of at least one, and this is " + args[1])

        const size = Number(args[1])
        const out = []

        for (let i = 0; i < xs.length; i += size) out.push(xs.slice(i, i + size))

        return out
    }

    // **The SHORTEST side decides the length**, which is the only rule that needs no filler
    // value -- padding would put something in the answer that was in none of the inputs.
    //
    // **EVERY SIDE IS WALKED RATHER THAN INDEXED**, so `zip(0..<3, names)` is the numbered walk
    // a program writes it for. What may be zipped is exactly what `...` spreads, `$.walked`
    // being the one answer both read; a generator forces the materialising, having nothing to
    // read at position `i` until it has been run out.
    B.zip = (...args) => {
        if (args.length === 0) fault("`zip` takes at least one thing to walk and was given none")

        const sides = args.map((a) => $.walked(a, "`zip`", "takes"))

        let shortest = 0

        for (let i = 0; i < sides.length; i++)
            if (i === 0 || sides[i].length < shortest) shortest = sides[i].length

        const out = []

        for (let i = 0; i < shortest; i++) out.push(sides.map((a) => a[i]))

        return out
    }

    // `array(x)` -- everything `x` yields, in an array.
    //
    // **THE TYPE WORD IS THE CONVERSION**, which is the rule `string`, `integer`, `real` and
    // `boolean` already follow, so there is no `Array` namespace to hang a `from` off. What it
    // takes is exactly what `...` spreads; an array given to it is COPIED, which is what a
    // conversion means everywhere else.
    B.array = (v) => $.walked(v, "`array`", "takes")

    // **Equality is `==`, the same question `contains` asks**, so a class that wrote `equals`
    // decides for its own values. That is a walk over what has been kept rather than a table,
    // which is the honest cost of letting a program's own answer have the last word.
    B.unique = (...args) => {
        wantArgs(args.length, 1, 1, "unique", "an array")

        const xs = wantArray(args[0], "unique")
        const n = xs.length
        const out = []

        for (let i = 0; i < n; i++) {
            const x = xs[i]
            let seen = false

            for (let j = 0; j < out.length; j++) if ($.eq(out[j], x)) { seen = true; break }

            stillWalking(xs, n, "unique")

            if (!seen) out.push(x)
        }

        return out
    }

    // `filter` then `.length` in one walk, which is the case it is for: the array `filter` builds
    // is thrown away by every caller that only wanted the number.
    B.count = (...args) => {
        wantArgs(args.length, 2, 2, "count", "an array and a function")

        const xs = wantArray(args[0], "count")
        const n = xs.length
        let found = 0n

        for (let i = 0; i < n; i++) {
            if ($.truthy(of(xs[i], i, xs, args[1], "count"))) found += 1n

            stillWalking(xs, n, "count")
        }

        return found
    }

    // **The ELEMENT and not the key**, which is the whole difference from `min(map(xs, f))`;
    // `null` for an empty array, that being a search that found nothing rather than a mistake
    // about a position; and the FIRST of two equal keys wins.
    const extremeBy = (args, name, smallest) => {
        wantArgs(args.length, 2, 2, name, "an array and a function")

        const xs = wantArray(args[0], name)
        const n = xs.length

        if (n === 0) return null

        let best = xs[0]
        let bestKey = of(best, 0, xs, args[1], name)

        for (let i = 1; i < n; i++) {
            const x = xs[i]
            const key = of(x, i, xs, args[1], name)

            stillWalking(xs, n, name)

            if ($.compare("<", smallest ? key : bestKey, smallest ? bestKey : key)) {
                best = x
                bestKey = key
            }
        }

        return best
    }

    B.minBy = (...args) => extremeBy(args, "minBy", true)
    B.maxBy = (...args) => extremeBy(args, "maxBy", false)

    B.string = (v) => text(v)

    // -- generators -----------------------------------------------------------------------------

    // `g.next()` and `g.next(v)` -- one step, as `{ value, done }`.
    //
    // **JavaScript's shape, which is the one slate took**: `null` is a value a generator may yield,
    // so a bare answer could not say whether the generator was finished. The value on the last step
    // is what the body returned.
    const stepped = (step) =>
        new $.SObj([["value", step.value === undefined ? null : step.value],
            ["done", step.done === true]])

    B.next = (g, sent) => {
        if (!$.isGen(g)) fault("`next` takes a generator, and this is " + typeName(g))

        const step = sent === undefined ? g.next() : g.next(sent)

        // **An `async` generator answers a PROMISE of the pair**, which is the whole of what
        // `async` changes about stepping one -- and `for await`, which awaits whatever `next`
        // hands back, was already written against both. Shaping it inside the `then` rather
        // than awaiting here keeps `next` synchronous for a plain generator, whose caller may
        // be in no position to wait.
        if ($.isAsyncGen(g)) return step.then(stepped)

        return stepped(step)
    }

    // `g.return()` and `g.return(v)` -- the host's own `return`, which leaves the body from the
    // `yield` it stands at and runs every `finally` on the way: that is what a `using` in the
    // body was emitted as, so its release runs, exactly as `do_gen_return` makes it. **A method
    // and never a global**, `return` being a word no program can call by name.
    B.$genReturn = (g, v) => {
        if (!$.isGen(g)) fault("`return` takes a generator, and this is " + typeName(g))

        const step = g.return(v === undefined ? null : v)

        if ($.isAsyncGen(g)) return step.then(stepped)

        return stepped(step)
    }

    // -- objects -----------------------------------------------------------------------------------

    // **A tag a declaration wrote is not a field**, so none of these four reports one -- the
    // interpreter's `tag_key` draws the same line and `print` has hidden them from the start.
    const fieldsOf = (o) => Array.from(o.entries()).filter(([k]) => $.walkedKey(o, k))

    // **AN ARRAY ANSWERS ALL THREE, AND ITS KEY IS THE POSITION.** `xs.entries()` is
    // `[[0, x0], [1, x1], ...]`, which is what makes `for [i, x] in xs.entries()` the indexed
    // walk -- the one loop slate had no spelling for. It is JavaScript's
    // `Array.prototype.keys`/`values`/`entries` with an array in place of the iterator, which is
    // the decision a MAP's three already took here.
    B.keys = (o) => {
        if (Array.isArray(o)) return o.map((_, i) => BigInt(i))

        if (!(o instanceof $.SObj)) fault("`keys` takes an object or an array, and this is " + typeName(o))

        return fieldsOf(o).map(([k]) => k)
    }

    B.values = (o) => {
        if (Array.isArray(o)) return o.slice()

        if (!(o instanceof $.SObj)) fault("`values` takes an object or an array, and this is " + typeName(o))

        return fieldsOf(o).map(([, v]) => v)
    }

    B.entries = (o) => {
        if (Array.isArray(o)) return o.map((x, i) => [BigInt(i), x])

        if (!(o instanceof $.SObj)) fault("`entries` takes an object or an array, and this is " + typeName(o))

        return fieldsOf(o).map(([k, v]) => [k, v])
    }

    B.has = (o, k) => {
        if (!(o instanceof $.SObj)) fault("`has` takes an object, and this is " + typeName(o))

        // A key the walks hide is a key the object does not have, which is `do_has`'s own rule.
        if (!$.walkedKey(o, k)) return false

        return o.hasKey(k)
    }

    // `without(o, key)` -- the object again, with that key gone. **A NEW object**, `with` being
    // the other half of this and answering a copy for the same reason.
    B.without = (o, k) => {
        if (!(o instanceof $.SObj)) fault("`without` takes an object, and this is " + typeName(o))

        const made = $.SObj.copy(o)

        if ($.walkedKey(o, k)) made.deleteKey(k)

        made.dataValue = o.dataValue
        made.frozen = o.dataValue

        return made
    }

    // `freeze(v)` -- close a container to writing, and answer the very value it was given.
    //
    // **IT IS SHALLOW and a value that is not a container ANSWERS ITSELF**, both JavaScript's
    // rules and both stated in the interpreter's `do_freeze`. Freezing twice is a no-op.
    //
    // **The host's `Object.freeze` is NOT called**, which is the decision this whole mechanism
    // exists for: it is a silent no-op in sloppy mode and a `TypeError` in strict, so slate
    // would answer one of two host sentences where it promises its own on both back ends.
    B.freeze = (v) => {
        if (v instanceof $.SObj) v.frozen = true
        else if (Array.isArray(v)) $.shutArray(v)
        else if (v instanceof $.SBytes) v.frozen = true
        else if (v instanceof $.SSet || v instanceof $.SMap) v.t.frozen = true

        // **A weak map is on the list although nothing about it is copyable**, and leaving it
        // off was the tempting mistake: `isFrozen` would then answer `true` for it -- the answer
        // a value with nothing to write through gets -- about a value `set` writes into happily.
        // It is the host's own `WeakMap` here rather than a table of slate's, so the flag is an
        // ordinary property on it; nothing a program can reach ever looks at one.
        else if (v instanceof WeakMap) v.frozen = true

        return v
    }

    // `isFrozen(v)` -- whether writing through this value is refused.
    //
    // **A value with nothing to write through answers TRUE**, which is `Object.isFrozen`'s
    // answer for a primitive and the honest one: the question is whether the value can change.
    // A data value answers true without anybody having called `freeze`.
    B.isFrozen = (v) => {
        if (v instanceof $.SObj) return v.frozen
        if (Array.isArray(v)) return $.arrayShut(v)
        if (v instanceof $.SBytes) return v.frozen
        if (v instanceof $.SSet || v instanceof $.SMap) return v.t.frozen
        if (v instanceof WeakMap) return v.frozen === true

        return true
    }

    // The most digits either of these writes, which is JavaScript's own range for both.
    const mostDigits = 100n

    // The name a number that is not finite writes, and null for one that is. **The digit count
    // is read only once the value is known to be finite**, which is where ECMAScript puts the
    // test for these two and not where it puts it for `toFixed`.
    const nonFiniteName = (x) => {
        if (!$.isReal(x) || Number.isFinite(x)) return null

        return Number.isNaN(x) ? "NaN" : (x > 0 ? "Infinity" : "-Infinity")
    }

    // How many digits a call asked for, or `-1` where it named none. **The sentences are the
    // interpreter's, word for word**, which is the whole of what a refusal has to agree about.
    const digitsAsked = (args, name, low, what) => {
        if (args.length < 2) return -1

        if (!$.isInt(args[1]))
            fault("`" + name + "` takes a whole number of " + what + ", and this is " +
                typeName(args[1]))

        if (args[1] < BigInt(low) || args[1] > mostDigits)
            fault("`" + name + "` writes from " + low + " to 100 " + what +
                ", and was asked for " + args[1])

        return Number(args[1])
    }

    // `d1.d2...e+n` -- one digit, a point only where something follows it, and an exponent that
    // always carries its sign.
    const expLayout = (minus, m, e) =>
        minus + m[0] + (m.length > 1 ? "." + m.slice(1) : "") + "e" + (e < 0 ? "-" : "+") +
            Math.abs(e)

    // ECMAScript's choice between the plain form and the exponential one: plain while the
    // exponent sits in `-6 <= e < p`, which is a NARROWER band than `string`'s.
    const precLayout = (minus, m, e, p) => {
        if (e < -6 || e >= p) return expLayout(minus, m, e)
        if (e === p - 1) return minus + m
        if (e >= 0) return minus + m.slice(0, e + 1) + "." + m.slice(e + 1)

        return minus + "0." + "0".repeat(-e - 1) + m
    }

    // `sig` significant digits of a whole number's magnitude, correctly rounded with a tie going
    // away from zero, and the power of ten the first of them stands on. Every step is `BigInt`
    // arithmetic, so a magnitude past `2^53` keeps every digit it has.
    const bigDigits = (mag, sig) => {
        const all = mag.toString()

        if (all.length <= sig) return [all + "0".repeat(sig - all.length), all.length - 1]

        const rest = all.slice(sig)
        let n = BigInt(all.slice(0, sig))
        let e = all.length - 1

        // `rest / 10^len >= 1/2` is the tie going away from zero, asked without a division.
        if (BigInt(rest) * 2n >= 10n ** BigInt(rest.length)) n += 1n

        let m = n.toString()

        // The carry can run past the last place -- `99` to one digit is `10` -- and the digit it
        // adds is always a trailing zero, so cutting it off is exact.
        if (m.length > sig) { m = m.slice(0, sig); e += 1 }

        return [m, e]
    }

    // A whole number's trailing zeros are not digits it needs: `100` names its value with one.
    const withoutTrailingZeros = (d) => {
        let cut = d.length

        while (cut > 1 && d[cut - 1] === "0") cut -= 1

        return d.slice(0, cut)
    }

    // `toExponential(x)` and `toExponential(x, digits)`.
    //
    // **A negative zero loses its sign, which is the host's answer and the interpreter's**:
    // the sign is taken off before anything is written and negative zero is not less than zero.
    B.toExponential = (...args) => {
        wantArgs(args.length, 1, 2, "toExponential", "a number and how many digits")

        const x = args[0]
        const itself = nonFiniteName(x)

        if (itself !== null) return itself

        const f = digitsAsked(args, "toExponential", 0, "digits")

        if ($.isInt(x)) {
            if (x === 0n) return expLayout("", "0".repeat(f < 0 ? 1 : f + 1), 0)

            const minus = x < 0n ? "-" : ""
            const mag = x < 0n ? -x : x

            if (f < 0) {
                const all = mag.toString()

                return expLayout(minus, withoutTrailingZeros(all), all.length - 1)
            }

            const [m, e] = bigDigits(mag, f + 1)

            return expLayout(minus, m, e)
        }

        if (!$.isReal(x)) fault("`toExponential` takes a number, and this is " + typeName(x))

        return f < 0 ? x.toExponential() : x.toExponential(f)
    }

    // `toPrecision(x)` and `toPrecision(x, digits)`.
    //
    // **With no count it is `string(x)` and NOT the host's `toPrecision()`**, which would spell
    // a negative zero `0` where slate spells it `-0`. `B.string` is what the interpreter answers
    // there too, so the two agree.
    B.toPrecision = (...args) => {
        wantArgs(args.length, 1, 2, "toPrecision", "a number and how many significant digits")

        const x = args[0]
        const itself = nonFiniteName(x)

        if (itself !== null) return itself

        const p = digitsAsked(args, "toPrecision", 1, "significant digits")

        if ($.isInt(x)) {
            if (p < 0) return B.string(x)
            if (x === 0n) return precLayout("", "0".repeat(p), 0, p)

            const [m, e] = bigDigits(x < 0n ? -x : x, p)

            return precLayout(x < 0n ? "-" : "", m, e, p)
        }

        if (!$.isReal(x)) fault("`toPrecision` takes a number, and this is " + typeName(x))

        if (p < 0) return B.string(x)

        return x.toPrecision(p)
    }

    // -- sets and maps -----------------------------------------------------------------------------

    const wantSet = (v, name) => {
        if (!(v instanceof $.SSet)) fault("`" + name + "` takes a set, and this is " + typeName(v))

        return v
    }

    const wantMap = (v, name) => {
        if (!(v instanceof $.SMap)) fault("`" + name + "` takes a map, and this is " + typeName(v))

        return v
    }

    // **A set and a map ARE the object's table on both back ends**, so `freeze` sets one flag on
    // that table and every write asks it here -- which is where the call's own name is still in
    // hand. Left to the table the sentence would name the MEMBER, an object's shape of
    // complaint about a value that has no fields. The interpreter's `changing_set` and
    // `changing_map` are this function twice.
    const changingSet = (v, name) => {
        if (v.t.frozen) fault($.frozenSetComplaint(name))

        return v
    }

    const changingMap = (v, name) => {
        if (v.t.frozen) fault($.frozenMapComplaint(name))

        return v
    }

    // Everything a value yields, in order -- what a constructor is given, what `...` spreads and
    // what `array(x)` answers. **`$.walked` is `walked_into` in `setmap.sysl`**, and the one
    // answer all of them read: a second walk written here came to take one value fewer than the
    // interpreter's the day a buffer was added to that list, which the corpus caught.
    const walkedValues = (v, what) => $.walked(v, what, "takes")

    B.Set = (...args) => {
        wantArgs(args.length, 0, 1, "Set", "nothing or one thing to walk")

        const made = new $.SSet()

        if (args.length === 1)
            for (const x of walkedValues(args[0], "`Set`")) made.t.setKey($.keep(x, "put in a set"), null)

        return made
    }

    // `add(s, v)` -- and the set back, so that adds chain.
    //
    // **A mutator answers the collection here, where an array's answers nothing.** `add` and
    // `set` are the names JavaScript gave them and chaining them is what those names are for.
    B.$setAdd = (s, v) => {
        changingSet(wantSet(s, "add"), "add").t.setKey($.keep(v, "put in a set"), null)

        return s
    }

    B.$setHas = (s, v) => wantSet(s, "has").t.hasKey(v)

    // `delete(s, v)` -- whether there was one, which is JavaScript's answer and the useful one.
    B.$setDelete = (s, v) => changingSet(wantSet(s, "delete"), "delete").t.deleteKey(v)

    B.$setClear = (s) => {
        changingSet(wantSet(s, "clear"), "clear").t.fields.clear()

        return null
    }

    // `size(s)` -- how many are in it.
    //
    // **A method rather than the property JavaScript has**, because slate has no properties on a
    // builtin kind: `xs.len()` is a call and so is this.
    B.$setSize = (s) => BigInt(wantSet(s, "size").size)

    B.$setValues = (s) => [...wantSet(s, "values").values()]

    B.$setForEach = (s, f) => {
        for (const x of [...wantSet(s, "forEach").values()]) $.callback(f, [x], "forEach")

        return null
    }

    B.Map = (...args) => {
        wantArgs(args.length, 0, 1, "Map", "nothing or a list of pairs")

        const made = new $.SMap()

        if (args.length === 1)
            for (const pair of walkedValues(args[0], "`Map`")) {
                // **A pair is an array of exactly two, and anything else is named rather than
                // ignored.** JavaScript reads a one-element entry as a key with `undefined`
                // beside it, which slate has nowhere to put -- and a reader who wrote `Map([1])`
                // meant a pair.
                if (!Array.isArray(pair))
                    fault("`Map` reads a list of pairs, and one of these is " + typeName(pair))

                if (pair.length !== 2)
                    fault("`Map` reads a list of pairs, and one of these has " + pair.length +
                        (pair.length === 1 ? " value" : " values") + " rather than a key and a value")

                made.t.setKey($.keep(pair[0], "a map key"), $.keep(pair[1], "put in a map"))
            }

        return made
    }

    B.$mapSet = (m, k, v) => {
        changingMap(wantMap(m, "set"), "set").t.setKey($.keep(k, "a map key"), $.keep(v, "put in a map"))

        return m
    }

    // `get(m, k)` -- what the key holds, or `null` where there is none.
    //
    // **`null` and not `undefined`**, which is slate's rule rather than a choice made here:
    // absence stops at the boundary it arose at, so nothing hands one out. A program that has to
    // tell a stored `null` from a missing key asks `has` first.
    B.$mapGet = (m, k) => {
        const held = wantMap(m, "get").t.getKey(k)

        return held === undefined ? null : held
    }

    B.$mapHas = (m, k) => wantMap(m, "has").t.hasKey(k)

    B.$mapDelete = (m, k) => changingMap(wantMap(m, "delete"), "delete").t.deleteKey(k)

    B.$mapClear = (m) => {
        changingMap(wantMap(m, "clear"), "clear").t.fields.clear()

        return null
    }

    B.$mapSize = (m) => BigInt(wantMap(m, "size").size)

    B.$mapKeys = (m) => [...wantMap(m, "keys").entries()].map(([k]) => k)

    B.$mapValues = (m) => [...wantMap(m, "values").entries()].map(([, v]) => v)

    // `entries(m)` -- the pairs, which is what walking a map gives and what `Map` reads back.
    B.$mapEntries = (m) => [...wantMap(m, "entries").entries()].map(([k, v]) => [k, v])

    B.$mapForEach = (m, f) => {
        for (const [k, v] of [...wantMap(m, "forEach").entries()]) $.callback(f, [[k, v]], "forEach")

        return null
    }

    // -- set algebra -----------------------------------------------------------------------------

    // **The operators reach these same seven through `$b`**, which `js_rt_show.sysl` already does
    // for `$childPid`: `js_rt_ops.sysl` is inside the `$` IIFE and every builtin is inside this
    // one, so a name here is reached as `$b.$setUnion` and there is still one implementation of
    // each. `setmap.sysl` is the interpreter's copy and the two must not drift -- including the
    // order an answer walks in, which is the receiver's members and then the argument's.
    //
    // **Both sides are checked before either is read, and the count first**, so the sentence a
    // reader meets is the one `setmap.sysl`'s `both_sets` gives for the same program.
    const twoSets = (args, name) => {
        wantArgs(args.length, 2, 2, name, "two sets")

        return [wantSet(args[0], name), wantSet(args[1], name)]
    }

    // The members of `from` that pass, added to `into` in the order they were added to `from`.
    const eachMember = (from, into, keep) => {
        for (const x of from.values()) if (keep(x)) into.t.setKey(x, null)
    }

    const always = () => true

    B.$setUnion = (...args) => {
        const [a, b] = twoSets(args, "union")
        const made = new $.SSet()

        eachMember(a, made, always)
        eachMember(b, made, always)

        return made
    }

    // **The RECEIVER is walked**, where JavaScript's own `intersection` walks whichever of the two
    // is smaller and lets that decide the order of the answer. What that buys is a comparison
    // count and what it costs is an order depending on a size nobody wrote down.
    B.$setIntersection = (...args) => {
        const [a, b] = twoSets(args, "intersection")
        const made = new $.SSet()

        eachMember(a, made, (x) => b.t.hasKey(x))

        return made
    }

    B.$setDifference = (...args) => {
        const [a, b] = twoSets(args, "difference")
        const made = new $.SSet()

        eachMember(a, made, (x) => !b.t.hasKey(x))

        return made
    }

    B.$setSymmetricDifference = (...args) => {
        const [a, b] = twoSets(args, "symmetricDifference")
        const made = new $.SSet()

        eachMember(a, made, (x) => !b.t.hasKey(x))
        eachMember(b, made, (x) => !a.t.hasKey(x))

        return made
    }

    // Whether every member of the first is a member of the second. **A set is contained in
    // itself**, which is what a subset means; `<` and `>` are the strict reading.
    const within = (a, b) => {
        for (const x of a.values()) if (!b.t.hasKey(x)) return false

        return true
    }

    B.$setIsSubsetOf = (...args) => {
        const [a, b] = twoSets(args, "isSubsetOf")

        return within(a, b)
    }

    B.$setIsSupersetOf = (...args) => {
        const [a, b] = twoSets(args, "isSupersetOf")

        return within(b, a)
    }

    B.$setIsDisjointFrom = (...args) => {
        const [a, b] = twoSets(args, "isDisjointFrom")

        for (const x of a.values()) if (b.t.hasKey(x)) return false

        return true
    }

    // **A strict containment is the plain one plus a smaller size**, which is exact rather than a
    // shortcut: a set holds each member once, so a subset the size of its superset is that
    // superset. `js_rt_ops.sysl`'s `compare` is what asks, and `setmap.sysl`'s `within` is the
    // interpreter's copy.
    B.$setWithin = (a, b, strict) => (strict ? a.size < b.size : true) && within(a, b)

    // -- weak maps and weak references ---------------------------------------------------------------

    // Whether a value is one a weak map may be keyed by, or a weak reference may point at.
    //
    // **The list is `weak.sysl`'s and it is a list rather than a test for "an object"**, because
    // several slate values are JavaScript objects and are not things a program holds: a shape, an
    // instant, a range and a regular expression are all values, and the interpreter has them as
    // ids with nothing to free.
    const weaklyHoldable = (v) =>
        v instanceof $.SObj || Array.isArray(v) || typeof v === "function" ||
        v instanceof $.SSet || v instanceof $.SMap || v instanceof Promise ||
        v instanceof WeakMap || v instanceof WeakRef || v instanceof $.SExt

    const wantHoldable = (v, what) => {
        if (!weaklyHoldable(v))
            fault(what + " must be something the collector can free -- an object, an array, a " +
                "class instance, a closure or an external -- and this is " + typeName(v))

        return v
    }

    // **An external is held by the HOST VALUE INSIDE IT and never by its wrapper.** A wrapper is
    // minted fresh on every read and two around one host value are one slate value -- `$.same`
    // compares `held` and `$.hash` hashes it -- so a weak map keyed by the wrapper would answer
    // nothing for the very external that was written into it, and a weak reference to one would
    // clear at the next collection with the host value still sitting there.
    const weakKey = (v) => (v instanceof $.SExt ? v.held : v)

    const wantWeakMap = (v, name) => {
        if (!(v instanceof WeakMap))
            fault("`" + name + "` takes a weak map, and this is " + typeName(v))

        return v
    }

    const wantWeakRef = (v, name) => {
        if (!(v instanceof WeakRef))
            fault("`" + name + "` takes a weak reference, and this is " + typeName(v))

        return v
    }

    // `WeakMap()` -- and nothing else, there being nothing to fill it from.
    //
    // **No constructor argument, where `Map` takes a list of pairs.** A weak map cannot be
    // walked, so `WeakMap(other)` could not copy one; and a list of pairs is an array holding
    // every key strongly, which is the leak the kind exists to prevent written into its own
    // constructor.
    B.WeakMap = (...args) => {
        wantArgs(args.length, 0, 0, "WeakMap", "nothing")

        return new WeakMap()
    }

    // `set(wm, k, v)` -- and the weak map back, so that writes chain as a map's do.
    B.$weakMapSet = (...args) => {
        wantArgs(args.length, 3, 3, "set", "a weak map, a key and a value")

        const [m, k, v] = args

        wantWeakMap(m, "set")

        if (m.frozen === true) fault($.frozenWeakMapComplaint("set"))

        wantHoldable(k, "a weak map's key")
        m.set(weakKey(k), $.keep(v, "put in a weak map"))

        return m
    }

    // `get(wm, k)` -- what the key holds, or `null` where there is none.
    //
    // **A key the collector has taken away reads exactly like a key nothing ever wrote**, which
    // is what makes a weak map usable at all: a program that has to tell the two apart is holding
    // the key, and a program holding the key has an entry.
    B.$weakMapGet = (...args) => {
        wantArgs(args.length, 2, 2, "get", "a weak map and a key")

        const [m, k] = args

        wantWeakMap(m, "get")
        wantHoldable(k, "a weak map's key")

        const held = m.get(weakKey(k))

        return held === undefined ? null : held
    }

    B.$weakMapHas = (...args) => {
        wantArgs(args.length, 2, 2, "has", "a weak map and a key")

        const [m, k] = args

        wantWeakMap(m, "has")
        wantHoldable(k, "a weak map's key")

        return m.has(weakKey(k))
    }

    // `delete(wm, k)` -- whether there was one, which is a map's answer and the useful one.
    B.$weakMapDelete = (...args) => {
        wantArgs(args.length, 2, 2, "delete", "a weak map and a key")

        const [m, k] = args

        wantWeakMap(m, "delete")

        if (m.frozen === true) fault($.frozenWeakMapComplaint("delete"))

        wantHoldable(k, "a weak map's key")

        return m.delete(weakKey(k))
    }

    // `WeakRef(target)` -- a hold on a value that does not keep it alive.
    //
    // **The receiver of an external travels beside the target**, so that a `deref` hands back an
    // external a bare call can still use: a host function read off a path is called on the thing
    // it was read from, which is what a browser's `fetch` throws about when it is not.
    B.WeakRef = (...args) => {
        wantArgs(args.length, 1, 1, "WeakRef", "one thing to point at")

        const t = wantHoldable(args[0], "a weak reference's target")
        const made = new WeakRef(weakKey(t))

        if (t instanceof $.SExt) made.$receiver = t.receiver

        return made
    }

    // `deref(r)` -- the target, or `null` once the collector has taken it.
    //
    // **`null` and not `undefined`**, which is slate's rule rather than a choice made here:
    // absence stops at the boundary it arose at, and slate has no `undefined` a program may
    // store. Nothing that may be a target is ever `null`, so a `null` from here means gone.
    B.$weakRefDeref = (...args) => {
        wantArgs(args.length, 1, 1, "deref", "a weak reference")

        const r = wantWeakRef(args[0], "deref")
        const got = r.deref()

        if (got === undefined) return null

        return "$receiver" in r ? new $.SExt(got, r.$receiver) : got
    }

    // -- JSON ----------------------------------------------------------------------------------------

    // A real as JSON spells it, which is NOT how `print` spells one.
    //
    // **The interpreter's rendering is C's `%.Ng` at the first N of 15, 16, 17 that reads back
    // equal**, then a `.0` where neither a point nor an exponent got written — because `1` is an
    // integer to a JSON reader and `1.0` is not, and slate's two numeric kinds are only worth
    // having if a round trip keeps them apart. **`String(x)` is JavaScript's own shortest form
    // and agrees with almost none of it**: `1.0` came out `1`, so `parseJSON(toJSON(1.0))` was an
    // integer under `slate js` and a real under the interpreter; `1e20` came out as twenty-one
    // digits, `1e-5` as `0.00001`, and every exponent unpadded.
    const trimmedZeros = (s) => (s.indexOf(".") < 0 ? s : s.replace(/0+$/, "").replace(/\.$/, ""))

    // `%.pg`: an exponent below -4 or at least the precision picks the exponential form, and a
    // C exponent is signed and at least two digits.
    const gFormat = (x, p) => {
        const said = x.toExponential(p - 1)
        const [head, tail] = said.split("e")
        const exp = Number(tail)

        if (exp < -4 || exp >= p)
            return trimmedZeros(head) + "e" + (exp < 0 ? "-" : "+") +
                String(Math.abs(exp)).padStart(2, "0")

        return trimmedZeros(x.toFixed(p - 1 - exp))
    }

    // **A NaN or an infinity is `null` rather than a fault**, which is `sh.sysl.json`'s decision
    // and therefore the interpreter's: JSON's grammar has no spelling for either, and it is what
    // `JSON.stringify` writes, so a reader on the other end expects it.
    const jsonReal = (x) => {
        if (!Number.isFinite(x)) return "null"
        if (x === 0) return Object.is(x, -0) ? "-0.0" : "0.0"

        for (let p = 15; p <= 17; p++) {
            const said = gFormat(x, p)

            if (Number(said) === x) return said.indexOf(".") < 0 && said.indexOf("e") < 0 ? said + ".0" : said
        }

        const last = gFormat(x, 17)

        return last.indexOf(".") < 0 && last.indexOf("e") < 0 ? last + ".0" : last
    }

    B.toJSON = (v, indent) => {
        const step = indent === undefined ? 0 : wantInt(indent, "toJSON")

        return writeJson(v, step, 0, [])
    }

    // **The keys a nominal value does not encode**, which is the printer's list and the
    // interpreter's `hidden_key`: the chain it is reached through and the tag that says what
    // made it. Without it the walk reaches the class object and complains about `new`.
    const hiddenKey = (k) => k === "proto" || $.tagKey(k)

    // **`path` IS THE WHOLE CYCLE GUARD, and this back end had none.** A value that holds itself
    // is an ordinary thing to build under a tracing collector, and `writeJson` descended it until
    // node ran out of stack -- which arrives as a `RangeError` naming a line of the runtime, not
    // as anything slate said. The interpreter has answered this with a sentence from the start.
    const writeJson = (v, step, depth, path) => {
        if (v === null) return "null"
        if (typeof v === "boolean") return v ? "true" : "false"
        // **AN INTEGER OF ANY WIDTH IS ITS DIGITS, and a `BigInt` has no `JSON.stringify`** --
        // the host throws for one -- so this is why the writer here is written out rather than
        // handed over. The interpreter writes the same digits through `sh.sysl.json`'s `Big`
        // variant, and `readNumber` below reads them back on this side, so a document crosses
        // between the two hosts with every digit intact.
        if ($.isInt(v)) return v.toString()

        if ($.isReal(v)) return jsonReal(v)
        if ($.isStr(v)) return JSON.stringify(v)

        // An opaque value encodes as what it is made of, as it does in the interpreter.
        if (v instanceof $.SVeil) return writeJson(v.rep, step, depth, path)

        const gap = step === 0 ? "" : "\n" + " ".repeat(step * (depth + 1))
        const close = step === 0 ? "" : "\n" + " ".repeat(step * depth)
        const comma = step === 0 ? "," : "," + gap

        // **A BUFFER ENCODES AS THE ARRAY OF ITS NUMBERS, which is what it encoded as before it
        // was a kind** -- so nothing that round-trips today changes. It cannot cycle, holding no
        // values, so there is no path to keep.
        if (v instanceof $.SBytes) {
            const u = v.view()

            if (u.length === 0) return "[]"

            return "[" + gap + Array.from(u, (b) => b.toString()).join(comma) + close + "]"
        }

        if (Array.isArray(v)) {
            if (path.indexOf(v) >= 0)
                fault("this array holds itself, so there is no JSON for it -- a document has no way to point back at what contains it")

            if (v.length === 0) return "[]"

            path.push(v)

            const out = "[" + gap + v.map((x) => writeJson(x, step, depth + 1, path)).join(comma) + close + "]"

            path.pop()

            return out
        }

        // **A set encodes as the array of its members and a map as the array of its pairs**,
        // which is exactly what each PRINTS as. An object keyed by anything but a string has no
        // JSON at all, so an array of pairs is the only encoding a map could have that keeps
        // its keys; JavaScript encodes both as `{}` and loses everything.
        if (v instanceof $.SSet) {
            if (path.indexOf(v) >= 0)
                fault("this set holds itself, so there is no JSON for it -- a document has no way to point back at what contains it")

            const members = [...v.values()]

            if (members.length === 0) return "[]"

            path.push(v)

            const out = "[" + gap + members.map((x) => writeJson(x, step, depth + 1, path)).join(comma) + close + "]"

            path.pop()

            return out
        }

        if (v instanceof $.SMap) {
            if (path.indexOf(v) >= 0)
                fault("this map holds itself, so there is no JSON for it -- a document has no way to point back at what contains it")

            const pairs = [...v.entries()].map(([k, x]) => [k, x])

            if (pairs.length === 0) return "[]"

            path.push(v)

            const out = "[" + gap + pairs.map((x) => writeJson(x, step, depth + 1, path)).join(comma) + close + "]"

            path.pop()

            return out
        }

        if (v instanceof $.SObj) {
            if (path.indexOf(v) >= 0)
                fault("this object holds itself, so there is no JSON for it -- a document has no way to point back at what contains it")

            // **A `toJSON` the program wrote replaces everything below, at every depth** -- the
            // rule `toString` already has, and node's own. The receiver rule applies, so a class
            // writes `toJSON(self)` like every other method.
            const said = $.callHook(v, "toJSON", [])

            if (said !== $.NO_HOOK) {
                if (said === v)
                    fault("`toJSON` says what a value encodes as, so it answers something else -- and this one gave the value back")

                path.push(v)

                const out = writeJson(said, step, depth, path)

                path.pop()

                return out
            }

            // **A class is a declaration rather than data**, so it has no more of a JSON form
            // than a function does -- and saying so names it, where the walk below reached `new`
            // and complained about a function nobody wrote.
            const own = $.classOwnName(v)

            if (own !== null) fault("there is no JSON for the class `" + own + "`")

            // **A nominal value encodes its own fields and not the chain it hangs from.**
            const nominal = $.variantName(v) !== null || $.className(v) !== null
            const parts = []

            path.push(v)

            for (const [k, x] of v.entries()) {
                if (nominal && hiddenKey(k)) continue

                // **A JSON name is a string and a slate key is any value**, so a key that is not
                // one has no encoding. `JSON.stringify` of an object key wrote `{}` and of an
                // integer key wrote a quoted number, either of which is a document the program
                // did not mean; the interpreter has refused both from the start.
                if (typeof k !== "string")
                    fault("a JSON name is a string, and this object has a key that is " + typeName(k))

                parts.push(JSON.stringify(k) + (step === 0 ? ":" : ": ") + writeJson(x, step, depth + 1, path))
            }

            path.pop()

            if (parts.length === 0) return "{}"

            return "{" + gap + parts.join(comma) + close + "}"
        }

        // **The interpreter's sentence, word for word.** The two back ends said different things
        // about the same value -- *"`toJSON` cannot write a function"* here and *"there is no
        // JSON for a function"* there -- which a suite that runs on both now notices.
        fault("there is no JSON for " + typeName(v))
    }

    // `parseJSON(text)` -- `{ ok: true, value }`, or `{ ok: false, error }`.
    //
    // **A document that will not parse is a RESULT, and a value that will not render is a fault.**
    // That is slate's two-channel rule applied to the two directions, and they genuinely differ:
    // text arriving from a file, a socket or a person is a condition every caller was always going
    // to handle, and a circle in a value the program built itself is a defect in that program.
    //
    // **Read here rather than by `JSON.parse`, and the reason is the two kinds of number**: JSON has
    // one and slate has two, and the distinction is in the TEXT -- `1` is an integer and `1.0` is a
    // real. `JSON.parse` answers a double for both and the difference cannot be recovered from it.
    B.parseJSON = (s) => {
        wantString(s, "parseJSON")

        try {
            const reader = { text: s, at: 0 }

            skipBlanks(reader)

            const value = readJson(reader)

            skipBlanks(reader)

            if (reader.at < s.length) throw new SyntaxError("unexpected text after the document")

            return new $.SObj([["ok", true], ["value", value]])
        } catch (e) {
            if (e instanceof SyntaxError) return new $.SObj([["ok", false], ["error", e.message]])

            throw e
        }
    }

    const skipBlanks = (r) => {
        while (r.at < r.text.length && " \t\n\r".indexOf(r.text[r.at]) >= 0) r.at += 1
    }

    const wanted = (r, what) => {
        throw new SyntaxError(what + " expected at character " + (r.at + 1))
    }

    const readJson = (r) => {
        if (r.at >= r.text.length) wanted(r, "a value")

        const c = r.text[r.at]

        if (c === "{") return readObject(r)
        if (c === "[") return readArray(r)
        if (c === '"') return readString(r)

        if (r.text.startsWith("true", r.at)) { r.at += 4; return true }
        if (r.text.startsWith("false", r.at)) { r.at += 5; return false }
        if (r.text.startsWith("null", r.at)) { r.at += 4; return null }

        return readNumber(r)
    }

    const readObject = (r) => {
        const entries = []

        r.at += 1
        skipBlanks(r)

        if (r.text[r.at] === "}") { r.at += 1; return new $.SObj(entries) }

        for (;;) {
            skipBlanks(r)

            if (r.text[r.at] !== '"') wanted(r, "a key")

            const key = readString(r)

            skipBlanks(r)

            if (r.text[r.at] !== ":") wanted(r, "`:`")

            r.at += 1

            skipBlanks(r)
            entries.push([key, readJson(r)])
            skipBlanks(r)

            if (r.text[r.at] === ",") { r.at += 1; continue }
            if (r.text[r.at] === "}") { r.at += 1; return new $.SObj(entries) }

            wanted(r, "`,` or `}`")
        }
    }

    const readArray = (r) => {
        const items = []

        r.at += 1
        skipBlanks(r)

        if (r.text[r.at] === "]") { r.at += 1; return items }

        for (;;) {
            skipBlanks(r)
            items.push(readJson(r))
            skipBlanks(r)

            if (r.text[r.at] === ",") { r.at += 1; continue }
            if (r.text[r.at] === "]") { r.at += 1; return items }

            wanted(r, "`,` or `]`")
        }
    }

    const readString = (r) => {
        const end = findStringEnd(r)
        const raw = r.text.slice(r.at, end)

        r.at = end

        return JSON.parse(raw)
    }

    // Where the string that starts here ends, an escaped quote not counting.
    const findStringEnd = (r) => {
        let i = r.at + 1

        for (;;) {
            if (i >= r.text.length) wanted(r, "the end of a string")

            if (r.text[i] === "\\") { i += 2; continue }
            if (r.text[i] === '"') return i + 1

            i += 1
        }
    }

    // **The text decides the kind**: a number written with no point and no exponent is an integer,
    // and any other is a real. That is `sh.sysl.json`'s own rule word for word, which is what
    // makes the two back ends agree about a document neither of them wrote.
    //
    // **`BigInt` of the digits, so WIDTH decides nothing.** `JSON.parse` answers a double for
    // every number and loses a digit past 2^53; the interpreter reads a number past a `long`
    // into `Json.Big` and grows it, and an integer here has no width either -- so `1e30` is a
    // real on both hosts and thirty-one digits is the exact integer on both.
    const readNumber = (r) => {
        const rest = r.text.slice(r.at)
        const found = /^-?(0|[1-9][0-9]*)((\.[0-9]+)?([eE][+-]?[0-9]+)?)/.exec(rest)

        if (found === null) wanted(r, "a value")

        r.at += found[0].length

        return found[2] === "" ? BigInt(found[0]) : Number(found[0])
    }

    // UTF-8, written out rather than taken from `TextEncoder`.
    //
    // **NOTHING THE PRELUDE NEEDS MAY BE A FEATURE AN ENGINE MIGHT NOT HAVE**, and these two are
    // exactly that: node and a browser have `TextEncoder`, an embedded quickjs realm does not, so
    // `toBytes(s).length` — which is how a slate program counts a body's length — died with
    // `TextEncoder is not defined` on the host slate's own test runner uses.
    //
    // **The decoder is strict, because the interpreter's is.** `from_utf8` refuses an overlong
    // form, a surrogate, anything past U+10FFFF and a sequence that stops early; `TextDecoder`
    // replaces each of them with U+FFFD and answers a string, which would have made `fromBytes`
    // succeed under node for bytes the interpreter says are not text.
    const bytesOfText = (s) => {
        const out = []

        for (const ch of s) {
            const c = ch.codePointAt(0)

            if (c < 0x80) out.push(c)
            else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f))
            else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f))
            else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f))
        }

        return out
    }

    // The text those bytes spell, or null where they spell none.
    const textOfBytes = (bytes) => {
        let out = ""
        let i = 0

        while (i < bytes.length) {
            const b = bytes[i]

            if (b < 0x80) {
                out += String.fromCharCode(b)
                i += 1

                continue
            }

            let need = 0
            let c = 0

            // 0xc0 and 0xc1 are missing on purpose: they can only begin an overlong form.
            if (b >= 0xc2 && b <= 0xdf) { need = 1; c = b & 0x1f }
            else if (b >= 0xe0 && b <= 0xef) { need = 2; c = b & 0x0f }
            else if (b >= 0xf0 && b <= 0xf4) { need = 3; c = b & 0x07 }
            else return null

            if (i + need >= bytes.length) return null

            for (let k = 1; k <= need; k++) {
                const n = bytes[i + k]

                if (n < 0x80 || n > 0xbf) return null

                c = (c << 6) | (n & 0x3f)
            }

            if (need === 2 && c < 0x800) return null
            if (need === 3 && c < 0x10000) return null
            if (c >= 0xd800 && c <= 0xdfff) return null
            if (c > 0x10ffff) return null

            out += String.fromCodePoint(c)
            i += need + 1
        }

        return out
    }

    // The latin1 bytes of a string -- each character below 256 as one byte, and a character at or
    // above it a fault naming it. `bytes.sysl`'s `latin1_bytes`.
    //
    // **NOT `TextEncoder`, and not `TextDecoder` the other way**: node's `'latin1'` decoder is
    // windows-1252, which maps eight of the bytes between 0x80 and 0x9f to characters that are not
    // at those code points -- so a byte written out and read back would not be the byte that went
    // in. One character per byte, by code, is what latin1 means here.
    const latin1Bytes = (s, name) => {
        const out = new Uint8Array(Array.from(s).length)
        let i = 0

        for (const ch of s) {
            const c = ch.codePointAt(0)

            if (c > 255)
                fault("`" + name + "` was asked for latin1 and this text holds `" + ch +
                    "`, which is character " + c + " and has no byte")

            out[i] = c
            i += 1
        }

        return out
    }

    // A run of bytes read back as latin1. **This never fails, which is the point of it**: every
    // one of the 256 byte values names a character there.
    const latin1Text = (bytes) => {
        let out = ""

        for (let i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i])

        return out
    }

    // Which of the two encodings a name asks for, or the complaint about a third.
    const encodingNamed = (v, name) => {
        if (!$.isStr(v))
            fault("`" + name + "` takes the name of an encoding as text, and this is " + typeName(v))

        if (v === "utf8" || v === "utf-8") return true
        if (v === "latin1") return false

        fault("`" + name + "` knows the encodings `utf8` and `latin1`, and this is `" + v + "`")
    }

    // **It answers a BUFFER, where it answered an array of numbers.** `bytesOfText` stays because
    // nothing the prelude needs may be a feature an engine might not have.
    B.toBytes = (s, encoding) => {
        wantString(s, "toBytes")

        if (encoding !== undefined && !encodingNamed(encoding, "toBytes"))
            return $.bytesOf(latin1Bytes(s, "toBytes"))

        return $.bytesOf(Uint8Array.from(bytesOfText(s)))
    }

    // **A RESULT, because arbitrary bytes are not text**, which is the interpreter's rule and was
    // not this back end's: it answered the string itself, so every `fromBytes(bs).value` in every
    // program was `undefined` under `slate js`. **Bytes or an array of numbers**, which is what
    // keeps every program written against the old shape working.
    B.fromBytes = (xs, encoding) => {
        const bytes = $.bytesLike(xs, "fromBytes")

        if (encoding !== undefined && !encodingNamed(encoding, "fromBytes"))
            return new $.SObj([["ok", true], ["value", latin1Text(bytes)]])

        const said = textOfBytes(bytes)

        return said === null
            ? new $.SObj([["ok", false], ["error", "these bytes are not text -- they are not valid UTF-8"]])
            : new $.SObj([["ok", true], ["value", said]])
    }

    // `bytes(n)`, `bytes([1, 2, 255])` and `bytes(b)` -- the interpreter's `do_bytes`.
    B.bytes = (v) => {
        if ($.isInt(v)) {
            const n = Number(v)

            if (n < 0) fault("`bytes` takes a count that is not negative, and this is " + n)
            if (n > 2147483647)
                fault("`bytes` was asked for " + n + " bytes, which is past the 2147483647 a buffer can hold")

            return $.bytesOf(new Uint8Array(n))
        }

        if (v instanceof $.SBytes) return $.bytesOf(v.view().slice())
        if (Array.isArray(v)) return $.bytesOf($.bytesLike(v, "bytes"))

        fault("`bytes` takes a count, an array of numbers or bytes to copy, and this is " + typeName(v))
    }

    // `toArray(b)` -- the door back to the forty names an array has.
    B.toArray = (b) => {
        if (!(b instanceof $.SBytes)) fault("`toArray` takes bytes, and this is " + typeName(b))

        return Array.from(b.view(), (x) => BigInt(x))
    }

    // -- shapes ------------------------------------------------------------------------------------

    // How a pattern is written, for the `wanted` half of a `mismatch` report. It reads the same
    // data `matchPattern` walks, and it is the interpreter's `write_shape` word for word.
    const shapeText = (pat) => {
        const kind = pat[0]

        if (kind === "_" || kind === "*") return "any"
        if (kind === "t") return pat[1]

        // A literal as a program writes it. **`$.text` and not `$.show`**, so that a string is
        // quoted here and not escaped -- which is what the interpreter's renderer does.
        if (kind === "v") return typeof pat[1] === "string" ? '"' + pat[1] + '"' : $.plain(pat[1])

        if (kind === "@") return shapeText(pat[1])

        if (kind === "rng") {
            const end = (b) => b === null ? "" : $.plain(b)

            return end(pat[1]) + (pat[3] ? ".." : "..<") + end(pat[2])
        }

        if (kind === "arr") {
            const parts = pat[1].map(shapeText)

            if (pat[2] || pat[3]) parts.push("...")

            return "[" + parts.join(", ") + "]"
        }

        if (kind === "obj") {
            const parts = []

            for (let i = 0; i < pat[1].length; i++)
                parts.push(pat[1][i] + (pat[3][i] ? "?" : "") + ": " + shapeText(pat[2][i]))

            return "{ " + parts.join(", ") + " }"
        }

        if (kind === "every") return pat[1] + " of " + shapeText(pat[2])
        if (kind === "holds")
            return pat[1] === "Set"
                ? "Set[" + shapeText(pat[2]) + "]"
                : "Map[" + shapeText(pat[2]) + ", " + shapeText(pat[3]) + "]"
        if (kind === "or") return pat[1].map(shapeText).join(" | ")
        if (kind === "and") return pat[1].map(shapeText).join(" & ")

        // **The declared name, which travels beside the class for exactly this** -- a JavaScript
        // object knows no name of its own.
        if (kind === "proto") return pat[2]
        if (kind === "veil") return pat[2]
        if (kind === "one") return pat[2]
        if (kind === "made") return pat[3] + " " + shapeText(pat[2])
        if (kind === "variant")
            return pat[3].length === 0 ? pat[4] : pat[4] + "(" + pat[3].map(shapeText).join(", ") + ")"

        return "any"
    }

    // The word a report uses for what actually arrived. **Every one of these is a word a pattern
    // could be written with**, so what a report says a value is can be pasted back into a type.
    const kindWord = (v) => {
        if (v === null) return "null"
        if (typeof v === "boolean") return "boolean"
        if ($.isInt(v)) return "integer"
        if ($.isReal(v)) return "real"
        if ($.isStr(v)) return "string"
        if (Array.isArray(v)) return "array"
        // **A data value is named by its VARIANT**, which is a word a pattern is written with
        // and is what `print` says about the same value.
        if (v instanceof $.SObj) return $.variantName(v) ?? "object"
        if (v instanceof $.SShape) return "shape"
        if (v instanceof $.SVeil) return v.name
        if (v instanceof $.SSet) return "Set"
        if (v instanceof $.SMap) return "Map"
        if (v instanceof Promise) return "promise"
        if ($.isGen(v)) return "generator"
        if (typeof v === "function") return "function"

        return $.typeName(v)
    }

    const under = (path, part) => (path === "" ? part : path + "." + part)

    // How a KEY names its entry in a mismatch path. **A string bare and anything else as it
    // prints**, which is the interpreter's `key_text` -- a map keyed by numbers reports
    // `3` where an object keyed by names reports the name.
    const keyPath = (k) => (typeof k === "string" ? k : $.show(k))

    const problem = (out, path, wanted, got) =>
        out.push($.obj([["path", path], ["wanted", wanted], ["got", got]]))

    // Everything about `v` that does not fit `pat`, as deep as the pattern goes.
    //
    // **A node that MATCHES is walked no further and reports nothing**, which is what makes a
    // false entry impossible: every problem follows a match that actually answered no.
    const collect = (pat, v, path, out) => {
        if ($.matches(v, pat)) return

        const kind = pat[0]

        if (kind === "@") return collect(pat[1], v, path, out)

        if (kind === "and") {
            for (const part of pat[1]) collect(part, v, path, out)

            return
        }

        if (kind === "obj") {
            if (!(v instanceof $.SObj)) return problem(out, path, "object", kindWord(v))

            const keys = pat[1]

            for (let i = 0; i < keys.length; i++) {
                // `lookup` walks `proto`, as `field_through` does for the machine.
                const [held] = v.lookup(keys[i])

                if (held === undefined) {
                    if (!pat[3][i]) problem(out, under(path, keys[i]), shapeText(pat[2][i]), "nothing")
                } else collect(pat[2][i], held, under(path, keys[i]), out)
            }

            return
        }

        if (kind === "arr") {
            if (!Array.isArray(v)) return problem(out, path, "array", kindWord(v))

            const items = pat[1]

            // **The length is reported OR the elements are, never both.** An array of the wrong
            // length has nothing useful to say about element three.
            if (v.length >= pat[4] && (pat[2] || pat[3] || v.length <= items.length)) {
                for (let i = 0; i < items.length && i < v.length; i++)
                    collect(items[i], v[i], under(path, String(i)), out)
            } else problem(out, path, shapeText(pat), "an array of " + v.length)

            return
        }

        if (kind === "every") {
            if (pat[1] === "array") {
                if (!Array.isArray(v)) return problem(out, path, "array", kindWord(v))

                for (let i = 0; i < v.length; i++) collect(pat[2], v[i], under(path, String(i)), out)

                return
            }

            if (!(v instanceof $.SObj)) return problem(out, path, "object", kindWord(v))

            for (const [k, x] of v.entries()) collect(pat[2], x, under(path, k), out)

            return
        }

        if (kind === "holds") {
            if (pat[1] === "Set") {
                if (!(v instanceof $.SSet)) return problem(out, path, "Set", kindWord(v))

                for (const x of v.values()) collect(pat[2], x, under(path, keyPath(x)), out)

                return
            }

            if (!(v instanceof $.SMap)) return problem(out, path, "Map", kindWord(v))

            for (const [k, x] of v.entries()) {
                collect(pat[2], k, under(path, keyPath(k)), out)
                collect(pat[3], x, under(path, keyPath(k)), out)
            }

            return
        }

        // **The nominal half is asked on its own, and the fields are walked only where it
        // held.** A value made by the wrong variant has nothing to say about field two.
        if (kind === "variant") {
            const items = pat[3]

            if (items.length === 0 || !$.hasProto(v, pat[1]) || !(v instanceof $.SObj))
                return problem(out, path, shapeText(pat), kindWord(v))

            const keys = pat[2]

            for (let i = 0; i < items.length; i++) {
                const [held] = v.lookup(keys[i])

                if (held === undefined) problem(out, under(path, keys[i]), shapeText(items[i]), "nothing")
                else collect(items[i], held, under(path, keys[i]), out)
            }

            return
        }

        if (kind === "made") {
            if ($.hasProto(v, pat[1])) return collect(pat[2], v, path, out)

            return problem(out, path, pat[3], kindWord(v))
        }

        problem(out, path, shapeText(pat), kindWord(v))
    }

    // **A CLASS OR A DATA NAME IS A SHAPE TOO**, carrying the one its declaration interned under
    // the hidden `(shape)` tag -- read as an OWN entry, which is what keeps an instance of the
    // class out of it. The interpreter's `shape_of` says the same.
    const wantShape = (v, name) => {
        if (v instanceof $.SObj) {
            const held = v.getKey("(shape)")

            if (held instanceof $.SShape) return held

            fault("`" + name + "` takes a shape, and this is an object that is not a type")
        }

        if (!(v instanceof $.SShape)) fault("`" + name + "` takes a shape, and this is " + typeName(v))

        return v
    }

    B.$shapeTest = (s, v) => $.matches(v, wantShape(s, "test").pat)

    B.$shapeMismatch = (s, v) => {
        const out = []

        collect(wantShape(s, "mismatch").pat, v, "", out)

        return out
    }

    B.$shapeName = (s) => wantShape(s, "name").name

    // -- the method tables -----------------------------------------------------------------------------

    const ARRAY = ["push", "pop", "insert", "removeAt", "clear", "map", "filter", "reduce",
        "find", "findIndex", "every", "some", "sort", "sorted", "reverse", "reversed", "concat",
        "flat", "sum", "join", "contains", "includes", "indexOf", "lastIndexOf", "string",
        "slice", "at", "shift", "unshift", "flatMap", "forEach", "findLast", "findLastIndex",
        "groupBy", "zip", "unique", "chunk", "count", "partition", "minBy", "maxBy",
        "toReversed", "keys", "values", "entries"]

    const STRING = ["chars", "split", "contains", "includes", "indexOf", "lastIndexOf",
        "startsWith",
        "endsWith", "trim", "trimStart", "trimEnd", "upper", "lower", "normalize", "casefold",
        "replace", "replaceAll", "repeat", "padStart", "padEnd", "number", "integer", "real",
        "boolean", "string", "toUpperCase", "toLowerCase", "at"]

    const NUMBER = ["abs", "floor", "ceil", "round", "trunc", "sqrt", "sin", "cos", "tan", "asin",
        "acos", "atan", "sinh", "cosh", "tanh", "log", "log2", "log10", "exp", "cbrt", "integer",
        "real", "boolean", "string", "toFixed", "formatNumber", "toExponential", "toPrecision"]

    const GENERATOR = ["next", "string"]

    // **A set's and a map's methods are `$`-prefixed entries rather than global builtins**, so
    // they are written out here as `SHAPE` is rather than built by `table`: `add`, `get`, `set`
    // and `delete` are words a program wants for its own, and the interpreter declares none of
    // them either. **`size` is not here** -- it is a property, and `PROPERTIES` below carries it.
    const SET = new Map([["add", B.$setAdd], ["has", B.$setHas], ["delete", B.$setDelete],
        ["clear", B.$setClear], ["values", B.$setValues], ["forEach", B.$setForEach],
        ["union", B.$setUnion], ["intersection", B.$setIntersection],
        ["difference", B.$setDifference], ["symmetricDifference", B.$setSymmetricDifference],
        ["isSubsetOf", B.$setIsSubsetOf], ["isSupersetOf", B.$setIsSupersetOf],
        ["isDisjointFrom", B.$setIsDisjointFrom]])

    const MAP = new Map([["set", B.$mapSet], ["get", B.$mapGet], ["has", B.$mapHas],
        ["delete", B.$mapDelete], ["clear", B.$mapClear], ["keys", B.$mapKeys],
        ["values", B.$mapValues], ["entries", B.$mapEntries], ["forEach", B.$mapForEach]])

    // **A weak map's four and a weak reference's one**, written out here as `SET` and `MAP` are.
    // **Neither carries `size`, `clear` or any walk**, and none of those is an omission: what is
    // in a weak map is the collector's to decide, so a walk would answer differently on two runs
    // of one program with nothing between them, and a count is a walk that says how long it was.
    const WEAKMAP = new Map([["set", B.$weakMapSet], ["get", B.$weakMapGet],
        ["has", B.$weakMapHas], ["delete", B.$weakMapDelete]])

    const WEAKREF = new Map([["deref", B.$weakRefDeref]])

    // A method whose entry is NOT the global builtin of the same name, keyed `kind.name`.
    //
    // **Empty now, and kept because the collision it was built for is still real.** An array's
    // `at` is a builtin here and a reading's `at` belongs to the calendar; a built-in module's
    // name is a plain global in the emitted program, so there is one `at` where the interpreter
    // has two natives. `js_rt_cal_builtins.sysl` answers it the way `calendar.sysl` does instead
    // -- one `at` that tests its first argument -- which is a better fit than six entries here,
    // one per kind that reads at something. The next collision of the kind may not have that
    // shape, so the mechanism stays.
    const OVERRIDES = new Map()

    const table = (kind, names) => {
        const t = new Map()

        for (const name of names) {
            const instead = OVERRIDES.get(kind + "." + name)

            if (instead !== undefined) t.set(name, instead)
            else if (B[name] !== undefined) t.set(name, B[name])
        }

        return t
    }

    // **A shape's three, and they are `$`-prefixed so they are not also globals** -- `test` and
    // `name` are words a program wants for its own, and the interpreter declares neither.
    const SHAPE = new Map([["test", B.$shapeTest], ["mismatch", B.$shapeMismatch],
        ["name", B.$shapeName]])

    // The names each kind answers to, and the tables built from them ON FIRST USE.
    //
    // **Lazily, because a name may be installed after this file is over.** `slate:time`'s
    // builtins are a block of their own and the stubs for what this back end still owes are the
    // very last thing the runtime does -- so a table built where it is written would be missing
    // exactly the late names, and `t.at(zone)` would say an instant cannot do that rather than
    // saying the calendar is not here yet. Nothing is looked up before the program runs, so one
    // null check is the whole cost.
    //
    // **`KINDS` is a registry rather than a literal for the same reason**: a block that arrives
    // later adds its kind to it, which is what `js_rt_time.sysl` does with `instant` and
    // `duration` and `js_rt_cal_builtins.sysl` does with the calendar's six.
    // **A buffer's table is short and every name in it is a global builtin**, so it is built by
    // `table` like the other four: `push`, `slice`, `concat`, `indexOf`, `contains`, `at` and
    // `clear` each dispatch on their first argument, exactly as the interpreter's do.
    const BYTES = ["push", "slice", "concat", "indexOf", "contains", "includes", "at", "toArray",
        "clear"]

    const KINDS = { array: ARRAY, string: STRING, number: NUMBER, generator: GENERATOR,
        bytes: BYTES }

    let TABLES = null

    const tables = () => {
        if (TABLES === null) {
            // **A child's and a channel's tables are built HERE rather than beside `SET`**,
            // which is the lazy rule doing its work: `js_rt_process.sysl` is a later block, so
            // a table written where `SET` is would hold `undefined` for every one of them.
            const CHILD = new Map([["send", B.$childSend], ["kill", B.$childKill],
                ["onMessage", B.$childOnMessage], ["onExit", B.$childOnExit]])

            const CHANNEL = new Map([["send", B.$channelSend], ["onMessage", B.$channelOnMessage]])

            // **A socket answers `dispose` and nothing else**, which is `method.sysl`'s line:
            // the rest of what a socket does is `slate:net`'s free functions, and `dispose` is
            // the one name `using` looks for. It is `close` under a second name because a
            // `close` is idempotent and takes nothing but the socket.
            const SOCKET = new Map([["dispose", B.close]])

            TABLES = { shape: SHAPE, set: SET, map: MAP, weakMap: WEAKMAP, weakRef: WEAKREF,
                child: CHILD, channel: CHANNEL, socket: SOCKET }

            for (const [kind, names] of Object.entries(KINDS)) TABLES[kind] = table(kind, names)

            // A generator's `return` is a method only, so `table` -- which reads globals --
            // cannot find it.
            TABLES.generator.set("return", B.$genReturn)
        }

        return TABLES
    }

    // The word a value's methods are looked up under, or "" for one that has none. **An object
    // answers "" and that is the decision rather than an omission**: its names belong to the program.
    const kindOf = (v) => {
        if (Array.isArray(v)) return "array"
        if (v instanceof $.SBytes) return "bytes"
        if ($.isStr(v)) return "string"
        if ($.isNum(v)) return "number"
        if ($.isGen(v)) return "generator"
        if (v instanceof $.SShape) return "shape"
        if (v instanceof $.SSet) return "set"
        if (v instanceof $.SMap) return "map"
        if (v instanceof WeakMap) return "weakMap"
        if (v instanceof WeakRef) return "weakRef"
        if (v instanceof SInstant) return "instant"
        if (v instanceof SDuration) return "duration"
        if (v instanceof SDate) return "date"
        if (v instanceof STime) return "time"
        if (v instanceof SDateTime) return "dateTime"
        if (v instanceof SZone) return "zone"
        if (v instanceof SZoned) return "zoned"
        if (v instanceof SPeriod) return "period"
        if (v instanceof SRegex) return "regex"
        if (v instanceof $.SRange) return "range"
        if (v instanceof $.SChild) return "child"
        if (v instanceof $.SChannel) return "channel"
        if (v instanceof $.SSocket) return "socket"

        return ""
    }

    // What one of the four was given past the value it is about, refusing where the count is
    // wrong. **A universal method taken off a value is the bare function** -- `val f =
    // n.toString` and then `f()` reaches the entry with no receiver at all -- so the empty call
    // is its own sentence rather than a count. `native_fn.sysl`'s `past_receiver` and the three
    // `do_*` beside it are the interpreter's copy of both sentences and the two must not drift.
    const universalArity = (name, given, takes) => {
        if (given === 0)
            fault("`" + name + "` is a method, so the value it is about is its first argument -- and this call gave nothing")

        const extra = given - 1

        if (extra !== takes)
            fault("`" + name + "` takes " + (takes === 0 ? "no arguments" : "one argument") +
                " and was given " + extra + (extra === 1 ? " argument" : " arguments"))
    }

    // The four methods EVERY value answers to, whatever its kind and whether or not it is an
    // object. **A field the program put there still wins**, this table being consulted only where
    // the lookup found nothing. `method.sysl`'s `universal_method` is the interpreter's copy and
    // the two lists must not drift.
    const UNIVERSAL = new Map([
        ["toString", (...a) => { universalArity("toString", a.length, 0); return $.text(a[0]) }],
        ["eq", (...a) => { universalArity("eq", a.length, 1); return $.identical(a[0], a[1]) }],
        ["ne", (...a) => { universalArity("ne", a.length, 1); return !$.identical(a[0], a[1]) }],
        ["equals", (...a) => { universalArity("equals", a.length, 1); return $.eq(a[0], a[1]) }]])

    // Whether this is a class or a data name -- an object carrying its own shape under the
    // hidden tag. **Own entry, never through a proto**: an instance reaches its class up the
    // chain, and `circle.test(v)` is a question nobody asked of a value that is not a type.
    const isShapeNamed = (v) => v instanceof $.SObj && v.getKey("(shape)") instanceof $.SShape

    // The properties each kind carries: a name read with a `.` that answers a value, with no
    // call. **`method.sysl`'s `properties_of` is the interpreter's copy and the two must not
    // drift**, which is what `tests/js/p33.sl` is for.
    //
    // **THE ANSWER IS `B.$len` ITSELF**, so a string counts CHARACTERS here exactly as it does
    // there: JavaScript's own `"a👋".length` is 3 and slate's is 2, and a `.length` emitted as
    // the host's would have been a silent disagreement in every astral string. **`$`-prefixed
    // because it is the property's own implementation and not itself a builtin** -- `tests_owed.sysl`
    // is what would catch a name in `$b` that no builtin claims.
    const PROPERTIES = { array: new Map([["length", (v) => B.$len(v)]]),

        // **How many bytes, and `length` rather than `size`** -- every byte is at a position,
        // which is the test a set and a map fail.
        bytes: new Map([["length", (v) => B.$len(v)]]),
        string: new Map([["length", (v) => B.$len(v)]]),
        range: new Map([["length", (v) => B.$len(v)]]),
        set: new Map([["size", (v) => B.$setSize(v)]]),
        map: new Map([["size", (v) => B.$mapSize(v)]]),

        // **What a child IS rather than what it does**, which is `method.sysl`'s line: a process
        // id is a number the child has, and `exited` is the one promise it will ever settle.
        child: new Map([["pid", (v) => B.$childPid(v)], ["exited", (v) => B.$childExited(v)]]) }

    B.$property = (v, name) => {
        const t = PROPERTIES[kindOf(v)]

        return t === undefined ? undefined : t.get(name)
    }

    B.$method = (v, name) => {
        const t = tables()[kindOf(v)]
        const own = t === undefined ? undefined : t.get(name)

        if (own !== undefined) return own

        // **A class or a data name answers the three shape methods**, reached only where the
        // object's own fields and its whole proto chain have said nothing -- so a static the
        // program declared wins. The interpreter's `shape_receiver` is the same rule.
        if (isShapeNamed(v)) {
            const m = SHAPE.get(name)

            if (m !== undefined) return m
        }

        // **The universal four come LAST, so a kind's own answer always wins.**
        return UNIVERSAL.get(name)
    }

    // -- what a `using` asks -----------------------------------------------------------------

    // Whether a value has a `dispose` to call.
    //
    // **The protocol is a method named `dispose`, the way a source is anything with a `next`.**
    // An object with the field has one, however far up its proto chain it sits; a builtin kind
    // has one where this runtime put it in the kind's table. A host value's methods are the
    // host's and slate may not say what it can do, so an external answers no -- which is the
    // interpreter's answer and has to stay the same one.
    //
    // **It lives here and not beside `caught` because the tables do**, and the two have to
    // agree about what a value can do.
    const hasDispose = (v) => {
        if (v instanceof $.SObj) return v.lookup("dispose")[0] !== undefined
        if (v instanceof $.SExt) return false

        return B.$method(v, "dispose") !== undefined
    }

    // The refusal a `using` makes at the DECLARATION, where the resource arrives.
    //
    // **Not at the release, which is the whole point of checking at all.** A block that has
    // done its work and then finds it cannot let go has already done the work. `null` passes,
    // which is TypeScript's rule and is what lets an optional resource be written without a
    // branch around the whole block.
    $.wantDisposable = (v) => {
        if (v === null || v === undefined) return
        if (hasDispose(v)) return

        $.fault("`using` needs a value with a `dispose` method to call when the block is left, and this is " + $.typeName(v))
    }

    // Release one resource on the way out of its block, `raised` being the signal already
    // travelling or `null` where the block is being left for any other reason.
    //
    // **With nothing travelling a release that faults simply propagates**, which is what a
    // `finally` does with a throw of its own. **With a fault already on its way out the
    // original wins** and the release's complaint rides on it as `suppressed`: the original is
    // what the program was told about, and a chain of them is more than the field is worth --
    // so the FIRST one is kept.
    $.disposeUsing = (v, raised) => {
        if (v === null || v === undefined) return
        if (raised === null || raised === undefined) return void $.method(v, "dispose", [])

        try {
            $.method(v, "dispose", [])
        } catch (d) {
            if (typeof raised === "object" && raised.$suppressed === undefined) raised.$suppressed = $.caught(d)
        }
    }

    // -- the clock, and the two temporal values ----------------------------------------------

    // `now()` -- this moment, as a point on the timeline.
    //
    // **It answers an instant and not a reading**, so `now().year()` does not exist and a
    // program has to say `now().at(zone).year()`. That is the design in one call: JavaScript's
    // own `new Date()` answers something that will happily tell you a year, using a zone nobody
    // named.
    B.now = (...args) => {
        wantArgs(args.length, 0, 0, "now", "no arguments")

        return new SInstant(BigInt(Date.now()) * 1000n)
    }

    // `monotonic()` -- a length read off a clock that only ever goes forward.
    //
    // **What an elapsed time is measured with, and the reason it is not `now()`.** The wall
    // clock can be set backwards -- by an operator, by NTP, by a host that keeps local time in
    // hardware -- so a difference of two `now()`s can be negative. This counts from an arbitrary
    // point and is good for nothing except subtracting from itself.
    //
    // **A host with no such clock is told so rather than given the wall clock**, which would be
    // this builtin quietly becoming the one it exists not to be.
    B.monotonic = (...args) => {
        wantArgs(args.length, 0, 0, "monotonic", "no arguments")

        if ($.host.monotonic === null)
            fault("`monotonic` needs a clock that only goes forward, and this JavaScript host has none")

        // `performance.now()` is milliseconds with a fraction, so the microseconds are rounded
        // off it rather than truncated: the fraction is real precision and dropping it would
        // make two readings a few hundred microseconds apart compare equal.
        return new SDuration(BigInt(Math.round($.host.monotonic() * 1000)))
    }

    // `instant(v)` -- the point on the timeline a zoned reading names.
    B.instant = (...args) => {
        wantArgs(args.length, 1, 1, "instant", "a zoned reading")

        if (args[0] instanceof SInstant) return args[0]
        if (args[0] instanceof SZoned) return new SInstant(args[0].us)

        fault("`instant` takes a zoned reading, and this is " + typeName(args[0]))
    }

    // `epochSeconds(n)` makes an instant; `t.epochSeconds()` reads one back. Likewise millis and
    // micros.
    //
    // **The unit is in the name because there is no default that is not a trap.** JavaScript
    // counts milliseconds, Unix counts seconds, and every program that has ever moved a
    // timestamp between the two has had this bug once.
    const epochWord = (name, factor) => (...args) => {
        wantArgs(args.length, 1, 1, name, "a whole number, or an instant to read one off")

        const v = args[0]

        if ($.isInt(v)) return new SInstant($.i64(v * factor))
        if (v instanceof SInstant) return v.us / factor

        // **A zoned reading answers these too**, and it is the reading's own instant that
        // answers: `zoned` lists all three in its method table, so leaving it out would put a
        // name in the table that the implementation refused. `do_epoch` in `calendar.sysl` has
        // the same arm.
        if (v instanceof SZoned) return v.us / factor

        fault("`" + name + "` takes a whole number or an instant, and this is " + typeName(v))
    }

    B.epochSeconds = epochWord("epochSeconds", 1000000n)
    B.epochMillis = epochWord("epochMillis", 1000n)
    B.epochMicros = epochWord("epochMicros", 1n)

    // The exact lengths: `micros`, `millis`, `seconds`, `minutes`, `hours`.
    //
    // **A whole number makes a length and a length answers how many whole ones it is**,
    // truncated toward zero. `hours(1) + minutes(30)` read back as `minutes` is 90 -- these are
    // totals rather than the parts of a written-out duration, since the parts are
    // `d.minutes() % 60` and nothing needs a second vocabulary to say that.
    //
    // **There is no `days` here and that is the point.** A day is not a fixed length of
    // timeline -- the two a year that a zone's clocks move through are 23 and 25 hours long --
    // so `days` makes a period, which is the calendar half and is still owed.
    const lengthWord = (name, factor) => (...args) => {
        wantArgs(args.length, 1, 1, name, "a whole number, or a duration to read one off")

        const v = args[0]

        if ($.isInt(v)) return new SDuration($.i64(v * factor))
        if (v instanceof SDuration) return v.us / factor

        // **`micros` alone also reads the fraction off a clock reading**, which is the only way
        // a program can reach the part of a second a `time` carries. The other four would be
        // asking how many minutes past midnight it is, which nobody spells this way.
        if (factor === 1n && hasTime(v)) return wallReading(v).us % US_PER_SECOND

        fault("`" + name + "` takes a whole number or a duration, and this is " + typeName(v))
    }

    B.micros = lengthWord("micros", 1n)
    B.millis = lengthWord("millis", 1000n)
    B.seconds = lengthWord("seconds", 1000000n)
    B.minutes = lengthWord("minutes", 60000000n)
    B.hours = lengthWord("hours", 3600000000n)

    // **`format` is in the instant's table SO THAT IT CAN BE REFUSED WELL.** An instant has no
    // calendar to format, and `format` says so and names the fix; leaving it out would answer
    // "`format` is not something an instant can do", which is true and sends the reader to look
    // at the pattern when what is wrong is one step earlier. `method.sysl`'s `instant_method`
    // keeps it for the same reason.
    KINDS.instant = ["at", "instant", "format", "epochSeconds", "epochMillis", "epochMicros",
        "string"]

    // A length of timeline, read back in whole units. **No `days`**: a day is not a fixed
    // length, so a duration cannot be asked how many of them it is.
    KINDS.duration = ["micros", "millis", "seconds", "minutes", "hours", "string"]

    // **A number makes a length of time**: `2.seconds()` is `seconds(2)`, and `method.sysl`'s
    // number table carries the same names. The calendar's four are added beside their
    // builtins.
    KINDS.number.push("micros", "millis", "seconds", "minutes", "hours", "epochSeconds",
        "epochMillis", "epochMicros")

    // -- the small shared checks -------------------------------------------------------------

    const calOk = (v) => $.obj([["ok", true], ["value", v]])
    const calErr = (message) => $.obj([["ok", false], ["error", message]])

    // **A real is refused rather than truncated.** `date(2026, 8.5, 1)` is a program that has
    // computed something wrong, and rounding it would hide which of the three was the mistake.
    const wholeOf = (v, name, which) => {
        if (!$.isInt(v))
            fault("`" + name + "` takes " + which + " as a whole number, and this is " + typeName(v))

        return v
    }

    // **Named for `time.sysl`'s `text_argument` and NOT `wantText`**, which `js_rt_host.sysl`
    // already declares in this same block with a different signature. `private` in sysl is
    // per file and a `const` here is not private at all.
    const textArgument = (v, name, which) => {
        if (!$.isStr(v)) fault("`" + name + "` takes " + which + ", and this is " + typeName(v))

        return v
    }

    // -- the six constructors, each of which also READS -------------------------------------

    // **One word per question, and the receiver says which question it is.** `date(2026, 8, 28)`
    // builds a calendar day and `date(z)` reads one off a zoned reading -- which is
    // `method.sysl`'s rule carried into a vocabulary where English already uses one word for the
    // noun and the verb.
    B.date = (...args) => {
        if (args.length === 1) {
            const v = args[0]

            if (v instanceof SDate) return v

            if (!hasDate(v))
                fault("`date` reads a date off something that has one, and this is " + typeName(v))

            return new SDate(wallReading(v).day)
        }

        wantArgs(args.length, 3, 3, "date",
            "a year, a month and a day, or one value to read a date off")

        const y = wholeOf(args[0], "date", "a year")
        const m = wholeOf(args[1], "date", "a month")
        const d = wholeOf(args[2], "date", "a day")
        const made = checkedDate(y, m, d)

        // **A date the calendar does not have is a fault and not a rounded one.** JavaScript
        // rolls the 30th of February over to the 2nd of March without a word; a date read out of
        // TEXT is a condition instead, which is why `parseDate` answers a result.
        if (made === null)
            fault("there is no such date -- the calendar has no " + d + " of month " + m + " in " + y)

        return new SDate(made)
    }

    B.time = (...args) => {
        if (args.length === 1) {
            const v = args[0]

            if (v instanceof STime) return v

            if (!hasTime(v))
                fault("`time` reads a time of day off something that has one, and this is " + typeName(v))

            return new STime(wallReading(v).us)
        }

        wantArgs(args.length, 2, 4, "time",
            "an hour and a minute, and optionally seconds and microseconds")

        const h = wholeOf(args[0], "time", "an hour")
        const m = wholeOf(args[1], "time", "a minute")
        const s = args.length > 2 ? wholeOf(args[2], "time", "a second") : 0n
        const us = args.length > 3 ? wholeOf(args[3], "time", "a number of microseconds") : 0n

        if (h < 0n || h > 23n) fault("an hour is 0 to 23, and this is " + h)
        if (m < 0n || m > 59n) fault("a minute is 0 to 59, and this is " + m)

        // **60 is refused rather than taken as a leap second.** A leap second is a fact about UTC
        // that no civil clock here can represent, and accepting it would put a value into a
        // program that every later comparison would be wrong about.
        if (s < 0n || s > 59n) fault("a second is 0 to 59, and this is " + s)

        if (us < 0n || us >= US_PER_SECOND)
            fault("a number of microseconds is 0 to 999999, and this is " + us)

        return new STime(h * US_PER_HOUR + m * US_PER_MINUTE + s * US_PER_SECOND + us)
    }

    B.dateTime = (...args) => {
        if (args.length === 1) {
            const v = args[0]

            if (v instanceof SDateTime) return v

            if (!hasDate(v) || !hasTime(v))
                fault("`dateTime` reads a date and a time off one value, and this is " + typeName(v))

            const w = wallReading(v)

            return new SDateTime(w.day, w.us)
        }

        if (args.length === 2) {
            if (!(args[0] instanceof SDate))
                fault("`dateTime` takes a date and a time, and the first is " + typeName(args[0]))

            if (!(args[1] instanceof STime))
                fault("`dateTime` takes a date and a time, and the second is " + typeName(args[1]))

            return new SDateTime(args[0].day, args[1].us)
        }

        wantArgs(args.length, 5, 7, "dateTime",
            "a date and a time, or a year through to a minute with optional seconds")

        // **The two halves are checked by the two constructors and not again here**, so a bad
        // month and a bad hour say what they say in `date` and in `time`.
        const day = B.date(args[0], args[1], args[2])
        const wall = B.time(args[3], args[4],
            args.length > 5 ? args[5] : 0n, args.length > 6 ? args[6] : 0n)

        return new SDateTime(day.day, wall.us)
    }

    // `zone(name)` -- a zone by the name the IANA database gives it, or a fixed offset.
    //
    // **A result, because the name usually comes from outside the program** and because which
    // zones a host has is the host's business. `zone(v)` on a zoned reading is the other question
    // and answers the zone itself, which cannot fail.
    B.zone = (...args) => {
        wantArgs(args.length, 1, 1, "zone", "a zone name, or a value to read the zone off")

        const v = args[0]

        if (v instanceof SZone) return v
        if (v instanceof SZoned) return v.zone

        if (!$.isStr(v))
            fault("`zone` takes a zone name or a zoned reading, and this is " + typeName(v))

        const said = zoneNamed(v)

        return said.error === null ? calOk(said.zone) : calErr(said.error)
    }

    // **Not a result, where `zone` is one.** There is always an answer, and a host that is
    // misconfigured about its own zone is not a condition a slate program can do anything about.
    B.localZone = (...args) => {
        wantArgs(args.length, 0, 0, "localZone", "no arguments")

        return localZoneValue()
    }

    // The calendar lengths: `days`, `weeks`, `months`, `years`.
    //
    // **Months and days are two scales and never convert.** `months(1).days()` is zero rather
    // than 30, because a month is 28, 29, 30 or 31 days and any number this answered would be
    // wrong somewhere. `weeks(2).days()` is 14, since a week always is one.
    const calendarLength = (name, make, read) => (...args) => {
        wantArgs(args.length, 1, 1, name, "a whole number, or a period to read one off")

        const v = args[0]

        if ($.isInt(v)) return make(v)
        if (v instanceof SPeriod) return read(v)

        fault("`" + name + "` takes a whole number or a period, and this is " + typeName(v))
    }

    B.days = calendarLength("days", (n) => new SPeriod(0n, n), (p) => p.days)
    B.weeks = calendarLength("weeks", (n) => new SPeriod(0n, n * 7n), (p) => p.days / 7n)
    B.months = calendarLength("months", (n) => new SPeriod(n, 0n), (p) => p.months)
    B.years = calendarLength("years", (n) => new SPeriod(n * 12n, 0n), (p) => p.months / 12n)

    // -- the parts a reading is made of ------------------------------------------------------

    // **`weekday` answers a NAME and not a number**, because every library that answers a number
    // has then to say which day the week starts on, and no two of them agree. JavaScript's
    // `getDay()` is 0 for Sunday and its `getDate()` is the day of the month -- two names three
    // characters apart meaning entirely different things.
    const part = (name, needsTime, read) => (...args) => {
        wantArgs(args.length, 1, 1, name, "a date, a dateTime or a zoned reading")

        const v = args[0]

        if (needsTime && !hasTime(v))
            fault("`" + name + "` reads a time of day, and " + typeName(v) + " has none")

        if (!needsTime && !hasDate(v))
            fault("`" + name + "` reads a date, and " + typeName(v) + " has none")

        return read(wallReading(v))
    }

    B.year = part("year", false, (w) => civilFromDays(w.day).year)
    B.month = part("month", false, (w) => civilFromDays(w.day).month)
    B.day = part("day", false, (w) => civilFromDays(w.day).day)
    B.hour = part("hour", true, (w) => w.us / US_PER_HOUR)
    B.minute = part("minute", true, (w) => w.us % US_PER_HOUR / US_PER_MINUTE)
    B.second = part("second", true, (w) => w.us % US_PER_MINUTE / US_PER_SECOND)
    B.weekday = part("weekday", false, (w) => WEEKDAY_NAMES[Number(weekdayOf(w.day))])
    B.monthName = part("monthName", false, (w) => monthName(civilFromDays(w.day).month))
    B.dayOfYear = part("dayOfYear", false, (w) => dayOfYear(w.day))
    B.daysInMonth = part("daysInMonth", false, (w) => {
        const c = civilFromDays(w.day)

        return daysInMonth(c.year, c.month)
    })
    B.isLeapYear = part("isLeapYear", false, (w) => leapYear(civilFromDays(w.day).year))

    // -- `at`, and the two awkward cases said out loud ---------------------------------------

    // **AN ARRAY ANSWERS `at` TOO, AND THE FIRST ARGUMENT IS WHAT KEEPS THEM APART.** `xs.at(-1)`
    // is the last element and `t.at(zone)` is a reading of an instant; the interpreter looks a
    // name up by the KIND of its receiver and so has two natives, where a built-in module's name
    // is a plain global here and there can only be one. `do_at` in `calendar.sysl` makes the same
    // test in the same place, so the two dispatch alike.
    const arrayAt = B.at

    B.at = (...args) => {
        // Bytes and a string answer `at` for an array's reason, and are told apart by the same
        // test -- a name is looked up by the KIND of its receiver.
        if (args.length > 0 &&
            (Array.isArray(args[0]) || args[0] instanceof $.SBytes || $.isStr(args[0])))
            return arrayAt(args[0], args[1])

        wantArgs(args.length, 1, 3, "at", "a value and what to read it at")

        if (args.length === 1)
            fault("`at` takes something to read the value at -- a zone, or a time of day for a date")

        const v = args[0]
        const what = args[1]

        if (v instanceof SInstant) {
            if (!(what instanceof SZone))
                fault("an instant is read at a zone, and this is " + typeName(what))

            return new SZoned(v.us, what)
        }

        if (v instanceof SZoned) {
            if (!(what instanceof SZone))
                fault("a zoned reading is read at another zone, and this is " + typeName(what))

            return new SZoned(v.us, what)
        }

        if (v instanceof SDate) {
            if (!(what instanceof STime))
                fault("a date is read at a time of day, and this is " + typeName(what))

            return new SDateTime(v.day, what.us)
        }

        if (v instanceof SDateTime) {
            if (!(what instanceof SZone))
                fault("a dateTime is read at a zone, and this is " + typeName(what))

            return resolvedAt(v.day, v.us, what, args)
        }

        fault("`at` reads an instant, a zoned reading, a date or a dateTime, and this is " + typeName(v))
    }

    // **A result, because the answer genuinely may not exist.** The hour a zone skips going into
    // daylight saving is a wall reading no clock there ever showed, and the hour it repeats
    // coming out names two instants. Every library that answers anyway picks one silently; this
    // hands the choice back.
    const resolvedAt = (day, us, z, args) => {
        const choice = args.length === 3 ? textArgument(args[2], "at", "which reading to take") : ""

        if (choice !== "" && choice !== "earlier" && choice !== "later" && choice !== "after")
            fault("`at` takes `\"earlier\"`, `\"later\"` or `\"after\"`, and this is `" + choice + "`")

        const r = resolveWall(day, us, z)

        if (r.kind === "unique") return calOk(new SZoned(r.at, z))

        const written = calendarText(new SDateTime(day, us))

        if (r.kind === "ambiguous") {
            if (choice === "earlier") return calOk(new SZoned(r.earlier, z))
            if (choice === "later") return calOk(new SZoned(r.later, z))

            return calErr(written + " happens twice in " + z.name +
                ", when the clocks go back -- say `.at(zone, \"earlier\")` or `\"later\"`")
        }

        if (choice === "after") return calOk(new SZoned(fromOffset(day, us, r.before), z))

        return calErr(written + " never happens in " + z.name + " -- the clocks go from " +
            offsetWritten(r.before, true) + " to " + offsetWritten(r.after, true) +
            " -- say `.at(zone, \"after\")` to take the reading past the gap")
    }

    // -- what a zone answers -----------------------------------------------------------------

    // The zone and the moment `offset` is asked of, however it was written. **Two spellings and
    // one implementation**: a zoned reading carries both, and a bare zone needs the instant
    // handed to it because a zone's answer changes through the year.
    const zoneQuestion = (args, name) => {
        if (args.length === 1) {
            if (args[0] instanceof SZoned) return { zone: args[0].zone, us: args[0].us }

            fault("`" + name + "` takes a zoned reading, or a zone and an instant, and this is " +
                typeName(args[0]))
        }

        if (args.length !== 2)
            fault("`" + name + "` takes a zoned reading, or a zone and an instant, and was given " +
                args.length + (args.length === 1 ? " argument" : " arguments"))

        if (!(args[0] instanceof SZone))
            fault("`" + name + "` takes a zone and an instant, and the first is " + typeName(args[0]))

        if (args[1] instanceof SInstant) return { zone: args[0], us: args[1].us }
        if (args[1] instanceof SZoned) return { zone: args[0], us: args[1].us }

        fault("`" + name + "` asks a zone about an instant, and this is " + typeName(args[1]))
    }

    // **An offset is a length of time and slate already has that type**, so there is no ninth
    // one: offset arithmetic is ordinary duration arithmetic and `.offset().hours()` is how a
    // program asks the question it usually wants.
    B.offset = (...args) => {
        const asked = zoneQuestion(args, "offset")

        return new SDuration(BigInt(zoneOffsetAt(asked.zone, asked.us)) * US_PER_MINUTE)
    }

    // -- `startOf` and `onOrAfter` -----------------------------------------------------------

    // **What a report is written with**: everything grouped by month starts by putting each
    // reading at the start of its month, and a program doing it by hand would rebuild the value
    // part by part and get the week wrong.
    B.startOf = (...args) => {
        wantArgs(args.length, 2, 2, "startOf", "a reading and a unit")

        const v = args[0]
        const unit = textArgument(args[1], "startOf", "a unit")

        if (!hasDate(v) && !hasTime(v))
            fault("`startOf` takes a date, a dateTime or a zoned reading, and this is " + typeName(v))

        const w = truncateWall(wallReading(v), unit)

        if (v instanceof SDate) {
            if (unit === "day" || unit === "hour" || unit === "minute" || unit === "second")
                fault("a date has no " + unit + " to start at")

            return new SDate(w.day)
        }

        if (v instanceof SDateTime) return new SDateTime(w.day, w.us)
        if (v instanceof SZoned) return settledInZone(w.day, w.us, v.zone)

        fault("`startOf` takes a date, a dateTime or a zoned reading, and this is " + typeName(v))
    }

    const truncateWall = (w, unit) => {
        const c = civilFromDays(w.day)

        if (unit === "year") return { day: daysFromCivil(c.year, 1n, 1n), us: 0n }
        if (unit === "month") return { day: daysFromCivil(c.year, c.month, 1n), us: 0n }

        // **A week starts on Monday**, which is ISO 8601's answer and the one the rest of the
        // world uses. `weekday` is the way to ask which day it is; nothing here makes the reader
        // guess.
        if (unit === "week") return { day: w.day - (weekdayOf(w.day) + 6n) % 7n, us: 0n }

        if (unit === "day") return { day: w.day, us: 0n }
        if (unit === "hour") return { day: w.day, us: w.us / US_PER_HOUR * US_PER_HOUR }
        if (unit === "minute") return { day: w.day, us: w.us / US_PER_MINUTE * US_PER_MINUTE }
        if (unit === "second") return { day: w.day, us: w.us / US_PER_SECOND * US_PER_SECOND }

        fault("`startOf` takes `\"year\"`, `\"month\"`, `\"week\"`, `\"day\"`, `\"hour\"`, " +
            "`\"minute\"` or `\"second\"`, and this is `" + unit + "`")
    }

    // `onOrAfter(d, "monday")` -- the first such day from this one on, which is what "every
    // Monday" means once it has been given a starting point.
    B.onOrAfter = (...args) => {
        wantArgs(args.length, 2, 2, "onOrAfter", "a date and a weekday")

        const name = textArgument(args[1], "onOrAfter", "a weekday")

        // Case is ignored: a weekday arrives from a configuration file as often as from a
        // literal.
        const wanted = WEEKDAY_NAMES.findIndex((w) => w.toLowerCase() === name.toLowerCase())

        if (wanted < 0) fault("`onOrAfter` takes a weekday, and `" + name + "` is not one")

        if (!(args[0] instanceof SDate))
            fault("`onOrAfter` takes a date, and this is " + typeName(args[0]))

        return new SDate(onOrAfterDay(args[0].day, BigInt(wanted)))
    }

    // -- reading text back -------------------------------------------------------------------

    // **Text is the boundary every date library gets wrong.** `new Date("not a date")` is an
    // `Invalid Date`, an ordinary value that spreads `NaN` through every calculation it touches
    // and complains nowhere. A result is the same channel `parseJSON` uses and for the same
    // reason: text from a file, a socket or a person is a condition the caller was always going
    // to handle.
    //
    // **The text being read is quoted back in the complaint**, because the reason on its own --
    // "day is out of range" -- says nothing a reader can act on when the string came out of a
    // file with a thousand lines in it.
    const reader = (name, which, read) => (...args) => {
        wantArgs(args.length, 1, 1, name, "one string")

        const s = textArgument(args[0], name, "a string")
        const said = read(s)

        return said.error === undefined ? calOk(said.value)
            : calErr("cannot read \"" + s + "\" as " + which + ": " + said.error)
    }

    B.parseDate = reader("parseDate", "a date", parseDateText)
    B.parseTime = reader("parseTime", "a time of day", parseTimeText)
    B.parseDateTime = reader("parseDateTime", "a dateTime", parseDateTimeText)
    B.parseTimestamp = reader("parseTimestamp", "a timestamp", parseTimestampText)

    // -- `format`, which is the user's own pattern language ----------------------------------

    // **From `io.github.edadma.datetime`**, moment.js-flavoured, with literal text fenced by `|`
    // bars rather than moment's brackets. `format.sysl` is the other back end's copy and carries
    // the table; the three corrections it lists -- `h12` at midnight, `a` meaning `am`, and `z`
    // being lower case -- are in the arms below.
    //
    // **AN ELEMENT THE VALUE DOES NOT HAVE IS REFUSED, NOT FILLED IN WITH ZEROS.** A date
    // rendered as `00:00` is a midnight the program never meant, and it is exactly the kind of
    // value that then gets compared, stored and reported on.
    B.format = (...args) => {
        wantArgs(args.length, 2, 2, "format", "a reading and a pattern")

        const v = args[0]
        const pattern = textArgument(args[1], "format", "a pattern")
        const w = wallReading(v)

        if (w === null) {
            // **An instant is the one temporal value with nothing to format**, and the message
            // says the fix rather than only the refusal.
            if (v instanceof SInstant)
                fault("an instant has no calendar to format -- read it in a zone first, with `t.at(zone)`")

            fault("`format` takes a date, a time, a dateTime or a zoned reading, and this is " +
                typeName(v))
        }

        const zoned = v instanceof SZoned

        return rendered({ dated: zoned || hasDate(v), timed: zoned || hasTime(v), zoned: zoned,
            day: w.day, us: w.us, zone: zoned ? v.zone : null, at: zoned ? v.us : 0n }, pattern)
    }

    // Which letters begin an element, every other character standing for itself.
    const ELEMENTS = "YMDWhmsfaAz"

    // The scan itself: a run of one letter is an element, a `|` opens literal text, and anything
    // else stands for itself.
    const rendered = (r, pattern) => {
        let out = ""
        let i = 0

        while (i < pattern.length) {
            const c = pattern[i]

            if (c === "|") {
                const shut = pattern.indexOf("|", i + 1)

                if (shut < 0) fault("this pattern opens literal text with `|` and never closes it")

                out = out + pattern.slice(i + 1, shut)
                i = shut + 1
            } else if (ELEMENTS.includes(c)) {
                let n = 1

                while (i + n < pattern.length && pattern[i + n] === c) n = n + 1

                // `h12` and `hh12` are the two elements whose spelling is not a run of one
                // letter, and they are read here rather than by the scan above so that a bare
                // `h` keeps working.
                const twelve = c === "h" && pattern.slice(i + n, i + n + 2) === "12"

                out = out + element(r, c, n, twelve)
                i = i + n + (twelve ? 2 : 0)
            } else {
                out = out + c
                i = i + 1
            }
        }

        return out
    }

    // The two refusals, which name the part of the pattern rather than the pattern.
    const needsDate = (r, what) => {
        if (!r.dated) fault("this pattern asks for " + what + " and the value has no date")
    }

    const needsTime = (r, what) => {
        if (!r.timed) fault("this pattern asks for " + what + " and the value has no time of day")
    }

    const padTo = (n, width) => {
        const digits = n.toString()

        return digits.length >= width ? digits : "0".repeat(width - digits.length) + digits
    }

    // The first three letters of a name, which is what `MMM` and `WWW` are. **Cut from the long
    // name rather than held in a second table**, so the two can never disagree.
    const shortened = (name) => name.slice(0, 3)

    const runOf = (c, n) => c.repeat(n)

    const element = (r, c, n, twelve) => {
        const civil = () => civilFromDays(r.day)

        if (c === "Y") {
            needsDate(r, "the year")

            const y = civil().year

            if (n === 1) return "" + y
            if (n === 2) return padTo(y % 100n, 2)
            if (n === 4) return padTo(y, 4)

            fault("a year is `Y`, `YY` or `YYYY`, and this is " + runOf("Y", n))
        }

        if (c === "M") {
            needsDate(r, "the month")

            const m = civil().month

            if (n === 1) return "" + m
            if (n === 2) return padTo(m, 2)
            if (n === 3) return shortened(monthName(m))
            if (n === 4) return monthName(m)

            fault("a month is `M`, `MM`, `MMM` or `MMMM`, and this is " + runOf("M", n))
        }

        if (c === "D") {
            needsDate(r, "the day")

            if (n === 1) return "" + civil().day
            if (n === 2) return padTo(civil().day, 2)
            if (n === 3) return padTo(dayOfYear(r.day), 3)

            fault("a day is `D` or `DD`, and the day of the year is `DDD`, and this is " + runOf("D", n))
        }

        if (c === "W") {
            needsDate(r, "the weekday")

            const name = WEEKDAY_NAMES[Number(weekdayOf(r.day))]

            if (n === 3) return shortened(name)
            if (n === 4) return name

            fault("a weekday is `WWW` or `WWWW`, and this is " + runOf("W", n))
        }

        if (c === "h") {
            needsTime(r, "the hour")

            const h = r.us / US_PER_HOUR
            const shown = twelve ? (h % 12n === 0n ? 12n : h % 12n) : h

            if (n === 1) return "" + shown
            if (n === 2) return padTo(shown, 2)

            fault("an hour is `h`, `hh`, `h12` or `hh12`, and this is " + runOf("h", n))
        }

        if (c === "m") {
            needsTime(r, "the minute")

            const m = r.us % US_PER_HOUR / US_PER_MINUTE

            if (n === 1) return "" + m
            if (n === 2) return padTo(m, 2)

            fault("a minute is `m` or `mm`, and this is " + runOf("m", n))
        }

        if (c === "s") {
            needsTime(r, "the second")

            const s = r.us % US_PER_MINUTE / US_PER_SECOND

            if (n === 1) return "" + s
            if (n === 2) return padTo(s, 2)

            fault("a second is `s` or `ss`, and this is " + runOf("s", n))
        }

        if (c === "f") {
            needsTime(r, "the fraction of a second")

            // **Six digits and no more, because a slate reading is microseconds.** A pattern
            // asking for nanoseconds would be asking for three digits that are always zero,
            // which is a lie about the precision of the value it is rendering.
            if (n > 6)
                fault("a fraction of a second is up to six digits here, since a reading is microseconds, and this is " +
                    runOf("f", n))

            let scaled = r.us % US_PER_SECOND

            for (let i = 0; i < 6 - n; i = i + 1) scaled = scaled / 10n

            return padTo(scaled, n)
        }

        if (c === "a" || c === "A") {
            needsTime(r, "morning or afternoon")

            if (n !== 1)
                fault("morning or afternoon is `a` or `A`, and this is " + runOf(c, n))

            const pm = r.us / US_PER_HOUR >= 12n

            return c === "a" ? (pm ? "pm" : "am") : (pm ? "PM" : "AM")
        }

        // The zone, which only a zoned reading has -- and the message says so rather than
        // writing `Z` for an offset nobody stated.
        if (!r.zoned)
            fault("only a zoned reading knows its zone -- read this one at a zone first, with `.at(zone)`")

        if (n === 1) return offsetWritten(zoneOffsetAt(r.zone, r.at), true)
        if (n === 2) return offsetWritten(zoneOffsetAt(r.zone, r.at), false)

        // **`zzz` is the zone's ABBREVIATION and this back end has none**, for the reason
        // `js_rt_cal.sysl`'s header measures: `Intl` carries CLDR display names rather than IANA
        // abbreviations, and 67 of 84 readings disagree. The refusal names the element rather
        // than the pattern, so a reader knows which three characters to take out.
        if (n === 3) fault(OWED_ABBREV)

        if (n === 4) return r.zone.name

        fault("a zone is `z`, `zz`, `zzz` or `zzzz`, and this is " + runOf("z", n))
    }

    // -- the two names a browser has no answer for -------------------------------------------

    // **The sentence says WHY rather than only that**, because a reader who believes "not in the
    // JavaScript back end yet" will wait for a release that is never coming. These two are not
    // owed work; they are things the host does not have.
    const OWED_ABBREV = "`abbrev` needs the IANA abbreviation for a zone, and a JavaScript host has none -- " +
        "`Intl` carries display names (`GMT+1` for `BST`) rather than the database's own"

    B.abbrev = () => fault(OWED_ABBREV)

    B.isDST = () => fault("`isDST` needs the zone database's daylight-saving flag, and a JavaScript host has none -- " +
        "`Intl` gives offsets only, and an offset cannot tell a zone that is permanently on daylight time from one that is not")

    // -- the method tables --------------------------------------------------------------------

    // **`method.sysl`'s six tables, name for name.** A name in a table that this back end refuses
    // -- `abbrev` and `isDST` -- is there ON PURPOSE, so that the refusal says what is missing
    // rather than "`abbrev` is not something a zone can do", which is true and sends the reader
    // to look at a name they wrote correctly.
    KINDS.date = ["year", "month", "day", "weekday", "monthName", "dayOfYear", "daysInMonth",
        "isLeapYear", "at", "startOf", "onOrAfter", "format", "string"]

    KINDS.time = ["hour", "minute", "second", "micros", "format", "string"]

    KINDS.dateTime = ["date", "time", "year", "month", "day", "hour", "minute", "second", "micros",
        "weekday", "monthName", "dayOfYear", "daysInMonth", "isLeapYear", "at", "startOf",
        "format", "string"]

    KINDS.zone = ["offset", "isDST", "abbrev", "string"]

    KINDS.zoned = ["instant", "zone", "date", "time", "dateTime", "year", "month", "day", "hour",
        "minute", "second", "micros", "weekday", "monthName", "dayOfYear", "daysInMonth",
        "isLeapYear", "offset", "isDST", "abbrev", "at", "startOf", "format", "epochSeconds",
        "epochMillis", "epochMicros", "string"]

    // **`weeks` and `days` convert and `months` and `years` convert, and the two pairs never
    // meet.** `weeks(2).days()` is 14; `months(1).days()` is 0.
    KINDS.period = ["days", "weeks", "months", "years", "string"]

    // **A number makes a period** the same way: `3.days()` is `days(3)`.
    KINDS.number.push("days", "weeks", "months", "years")

    // -- slate's bytes, and the runtime's ----------------------------------------------------

    // **A slate byte string is an array of INTEGERS, which are `BigInt`s here**, so the boundary
    // costs a conversion each way. It is paid once per call rather than per block, which is why
    // every digest next door takes and answers a `Uint8Array`.
    //
    // **Text is taken as its UTF-8 bytes**, which is what `bytes_arg` in `crypto.sysl` does and
    // is the only reading that makes `sha256("abc")` mean the same thing on both back ends.
    const cryptoBytes = (v, name, what) => {
        if ($.isStr(v)) return new TextEncoder().encode(v)

        // A buffer is handed over as it stands, which is what `bytes_arg` does next door.
        if (v instanceof $.SBytes) return v.view()

        if (!Array.isArray(v))
            fault("`" + name + "` takes " + what + " as text or bytes, and this is " + typeName(v))

        const out = new Uint8Array(v.length)

        for (let i = 0; i < v.length; i = i + 1) {
            const b = v[i]

            if (!$.isInt(b))
                fault("`" + name + "` takes an array of numbers, and one of these is " + typeName(b))

            if (b < 0n || b > 255n) fault("a byte is between 0 and 255, and this is " + b)

            out[i] = Number(b)
        }

        return out
    }

    // **A digest, a tag, a derived key and the kernel's randomness are all BUFFERS**, which is
    // what the interpreter answers and what a program writes to a socket. It was
    // `Array.from(bytes, BigInt)` -- a whole tagged value per byte, on the one surface in the
    // language whose answers are never read as numbers.
    const cryptoArray = (bytes) => $.bytesOf(bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes))

    const cryptoText = (v, name, what) => {
        if (!$.isStr(v)) fault("`" + name + "` takes " + what + " as text, and this is " + typeName(v))

        return v
    }

    const cryptoWhole = (v, name, what) => {
        if (!$.isInt(v)) fault("`" + name + "` takes " + what + " as a number, and this is " + typeName(v))

        return v
    }

    const cryptoCount = (v, name, what) => {
        if (!$.isInt(v))
            fault("`" + name + "` takes " + what + " as a number, and this is " + typeName(v))

        if (v < 0n)
            fault("`" + name + "` takes " + what + " as a count that is not negative, and this is " + v)

        return Number(v)
    }

    // The two lists a refusal quotes, which are `crypto.sysl`'s `digests` and `derivations`.
    const DIGEST_NAMES = "MD5, SHA-1, SHA-256, SHA-384 and SHA-512"
    const DERIVE_NAMES = "SHA-1, SHA-256, SHA-384 and SHA-512"

    const counted = (n) => n + (n === 1 ? " argument" : " arguments")

    // -- the five digests --------------------------------------------------------------------

    // **MD5 and SHA-1 are here and neither is an endorsement.** Each is what an existing protocol
    // asks for -- a WebSocket handshake, a Git object, PostgreSQL's `md5` login -- and a program
    // speaking one has no say in the matter.
    const digestWord = (name, alg) => (...args) => {
        if (args.length !== 1)
            fault("`" + name + "` takes the data to hash, and was given " + counted(args.length))

        return cryptoArray(digestOf(alg, cryptoBytes(args[0], name, "the data")))
    }

    B.md5 = digestWord("md5", "MD5")
    B.sha1 = digestWord("sha1", "SHA-1")
    B.sha256 = digestWord("sha256", "SHA-256")
    B.sha384 = digestWord("sha384", "SHA-384")
    B.sha512 = digestWord("sha512", "SHA-512")

    // `hmac(alg, key, message)`. **The algorithm is an argument** because what a program is
    // speaking decides it, and a default would be a decision taken by whoever wrote the runtime.
    B.hmac = (...args) => {
        if (args.length !== 3)
            fault("`hmac` takes an algorithm, a key and a message, and was given " + counted(args.length))

        const alg = cryptoText(args[0], "hmac", "the algorithm")
        const key = cryptoBytes(args[1], "hmac", "the key")
        const message = cryptoBytes(args[2], "hmac", "the message")
        const tag = hmacOf(alg, key, message)

        if (tag === null)
            fault("`" + alg + "` is not a digest this understands -- there are " + DIGEST_NAMES)

        return cryptoArray(tag)
    }

    // `pbkdf2(alg, password, salt, iterations, length)`.
    //
    // **MD5 is refused here where the digests take it**, which is `crypto.sysl`'s line and its
    // reason: deriving a key is the one thing in this module that is a program's own choice, so
    // there is no protocol to be bound by.
    B.pbkdf2 = (...args) => {
        if (args.length !== 5)
            fault("`pbkdf2` takes an algorithm, a password, a salt, an iteration count and a length, and was given " +
                counted(args.length))

        const alg = cryptoText(args[0], "pbkdf2", "the algorithm")
        const password = cryptoBytes(args[1], "pbkdf2", "the password")
        const salt = cryptoBytes(args[2], "pbkdf2", "the salt")
        const iterations = cryptoWhole(args[3], "pbkdf2", "the iteration count")
        const length = cryptoCount(args[4], "pbkdf2", "the length")

        if (iterations < 1n) fault("`pbkdf2` takes at least one iteration, and was asked for " + iterations)
        if (length === 0) fault("`pbkdf2` was asked for a key of no length")

        // **A count that does not fit is refused rather than wrapped**, a wrapped count deriving
        // a perfectly good-looking key that agrees with nobody.
        if (iterations > 4294967295n)
            fault("`pbkdf2` takes an iteration count of at most 4294967295, and was asked for " + iterations)

        if (alg === "MD5" || DIGEST_BLOCK[alg] === undefined)
            fault("`" + alg + "` is not a digest this derives a key with -- there are " + DERIVE_NAMES)

        return cryptoArray(pbkdf2Of(alg, password, salt, Number(iterations), length))
    }

    // -- JWS, whose two halves land on different sides of the line ---------------------------

    // `jwsSign(alg, key, message)` and `jwsVerify(alg, key, message, signature)`.
    //
    // **THE SYMMETRIC HALF IS HMAC AND IS HERE; THE ASYMMETRIC HALF IS NOT, AND THAT REFUSAL IS
    // THE ONE PLACE IN THIS RUNTIME WHERE A BROWSER HAS THE THING AND STILL CANNOT ANSWER.**
    // `HS256`, `HS384` and `HS512` are HMAC under a JOSE name, so `slate:jwt` -- which is what
    // nearly every program reaching these is really using -- works here in full. `RS*`, `PS*`
    // and `ES*` are RSA and ECDSA, and the web platform's only RSA and ECDSA are
    // `crypto.subtle`'s, which is Promise-only. So the call could be built and could not keep
    // its SHAPE: `jwsSign` answers a buffer under the interpreter and would answer a promise
    // here.
    //
    // **Refusing is the smaller wrong of the two**, a program that gets a promise where it
    // expected bytes failing somewhere else entirely. The sentence says which half is missing and
    // why, so a reader knows the fix is an algorithm rather than a wait.
    //
    // **Before this the two names were on no list at all and died as `jwsSign is not defined`**,
    // which is exactly the failure `js_rt_host.sysl`'s `OWED` exists to prevent -- so it was a
    // hole in that mechanism rather than a decision anybody took.
    const JWS_NAMES = "HS256, HS384, HS512, RS256, RS384, RS512, PS256, PS384, PS512, ES256, ES384 and ES512"

    const JWS_ASYMMETRIC = ["RS256", "RS384", "RS512", "PS256", "PS384", "PS512",
        "ES256", "ES384", "ES512"]

    // Which digest a JOSE name means, or `null` where it is not a symmetric one.
    const jwsDigest = (alg) => alg === "HS256" ? "SHA-256"
        : alg === "HS384" ? "SHA-384" : alg === "HS512" ? "SHA-512" : null

    const jwsRefusal = (alg, name) => {
        if (JWS_ASYMMETRIC.includes(alg))
            fault("`" + name + "` cannot use `" + alg + "` on a JavaScript host: RSA and ECDSA are " +
                "`crypto.subtle`'s alone there and every one of its calls answers a promise, where this one " +
                "answers bytes -- the `HS` algorithms are HMAC and do work here")

        fault("`" + alg + "` is not an algorithm this understands -- there are " + JWS_NAMES)
    }

    B.jwsSign = (...args) => {
        if (args.length !== 3)
            fault("`jwsSign` takes an algorithm, a key and a message, and was given " + counted(args.length))

        const alg = cryptoText(args[0], "jwsSign", "the algorithm")
        const key = cryptoBytes(args[1], "jwsSign", "the key")
        const message = cryptoBytes(args[2], "jwsSign", "the message")
        const digest = jwsDigest(alg)

        if (digest === null) jwsRefusal(alg, "jwsSign")

        return cryptoArray(hmacOf(digest, key, message))
    }

    // **A signature that does not check out is `false`, and a question that could not be asked is
    // a fault.** A key of the wrong kind and a signature of the wrong length are not an attacker,
    // and collapsing them into `false` would make a misconfiguration look like one.
    B.jwsVerify = (...args) => {
        if (args.length !== 4)
            fault("`jwsVerify` takes an algorithm, a key, a message and a signature, and was given " +
                counted(args.length))

        const alg = cryptoText(args[0], "jwsVerify", "the algorithm")
        const key = cryptoBytes(args[1], "jwsVerify", "the key")
        const message = cryptoBytes(args[2], "jwsVerify", "the message")
        const signature = cryptoBytes(args[3], "jwsVerify", "the signature")
        const digest = jwsDigest(alg)

        if (digest === null) jwsRefusal(alg, "jwsVerify")

        return sameTag(hmacOf(digest, key, message), signature)
    }

    // `randomBytes(n)` -- n bytes from the host's own source.
    //
    // **This is the half of the module that cannot be written out at any price, and it is also
    // the half a browser genuinely has.** `crypto.getRandomValues` is synchronous everywhere,
    // which is the whole reason `slate:crypto` needs no promise here: a program has no source of
    // unpredictability of its own, and a nonce computed from the clock is not one.
    B.randomBytes = (...args) => {
        if (args.length !== 1)
            fault("`randomBytes` takes a count, and was given " + counted(args.length))

        const n = cryptoCount(args[0], "randomBytes", "the count")

        if (n === 0) fault("`randomBytes` was asked for no bytes")

        const source = typeof crypto !== "undefined" && crypto !== null ? crypto : null

        if (source === null || typeof source.getRandomValues !== "function")
            fault("`randomBytes` could not get randomness from the kernel, and bytes this program made up would not be worth having")

        // **`getRandomValues` refuses more than 65536 bytes at a time**, which is the
        // specification's limit and not a browser's whim -- so a larger ask is filled in
        // chunks rather than refused. The interpreter has no such limit and a program that
        // asked for a megabyte would otherwise work under one back end and not the other.
        const out = new Uint8Array(n)

        for (let off = 0; off < n; off = off + 65536)
            source.getRandomValues(out.subarray(off, Math.min(off + 65536, n)))

        return cryptoArray(out)
    }

    // `timingSafeEqual(a, b)`.
    //
    // **A comparison that stops at the first differing byte is how a tag is forged a byte at a
    // time**, and `==` over two arrays is exactly that comparison.
    B.timingSafeEqual = (...args) => {
        if (args.length !== 2)
            fault("`timingSafeEqual` takes two byte strings, and was given " + counted(args.length))

        return sameTag(cryptoBytes(args[0], "timingSafeEqual", "the first"),
            cryptoBytes(args[1], "timingSafeEqual", "the second"))
    }

    // -- Argon2id ----------------------------------------------------------------------------

    // node's core `crypto`, or nothing where there is none.
    const argon2Host = (() => {
        const load = $.host.require

        if (typeof process === "undefined" || typeof load !== "function") return null

        try {
            const c = load("node:crypto")

            return typeof c.argon2 === "function" ? c : null
        } catch (e) {
            return null
        }
    })()

    const noArgon2 = (name) =>
        fault("`" + name + "` is Argon2id, which this JavaScript host has not got -- node has it " +
            "in `crypto` and the web platform has no Argon2 at all, `crypto.subtle` deriving keys " +
            "with PBKDF2 and HKDF and nothing memory-hard")

    // OWASP's first recommendation for a login, which is what a call with no parameters gets.
    const ARGON2_BLOCKS = 19456
    const ARGON2_PASSES = 2
    const ARGON2_LANES = 1
    const ARGON2_TAG = 32
    const ARGON2_SALT = 16

    // The ceiling, in the unit `memoryCost` is written in: a gibibyte of working memory.
    const ARGON2_MAX_BLOCKS = 1048576
    const ARGON2_MAX_SALT = 32
    const ARGON2_MAX_TAG = 64
    const ARGON2_MAX_PASSWORD = 256

    const ARGON2_OPTIONS = "`memoryCost`, `timeCost`, `parallelism`, `hashLength` and `salt`"

    const ARGON2_KNOWN = ["memoryCost", "timeCost", "parallelism", "hashLength", "salt"]

    // -- the PHC string, which is monocypher's `encode` and `parse` --------------------------

    // **The standard alphabet WITHOUT PADDING**, which is the format's one idiosyncrasy and the
    // thing most likely to make two implementations disagree about a record they both wrote.
    const ARGON2_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    const argon2B64 = (bytes) => {
        let out = ""

        for (let i = 0; i < bytes.length; i = i + 3) {
            const left = bytes.length - i
            const n = (bytes[i] << 16) | ((left > 1 ? bytes[i + 1] : 0) << 8) | (left > 2 ? bytes[i + 2] : 0)

            out = out + ARGON2_B64[(n >> 18) & 63] + ARGON2_B64[(n >> 12) & 63]

            if (left > 1) out = out + ARGON2_B64[(n >> 6) & 63]
            if (left > 2) out = out + ARGON2_B64[n & 63]
        }

        return out
    }

    // The bytes of an unpadded base64 field, or `null` where it is not one.
    //
    // **A field of one character decodes to nothing and is refused**, four characters carrying
    // three bytes and one left over carrying none -- which is what makes `AgIC` and `AgICA`
    // different lengths and `AgICAgI` a record nobody wrote.
    const argon2Unb64 = (text) => {
        if (text.length === 0 || text.length % 4 === 1) return null

        const out = new Uint8Array(Math.floor(text.length * 3 / 4))
        let held = 0
        let bits = 0
        let at = 0

        for (const ch of text) {
            const v = ARGON2_B64.indexOf(ch)

            if (v < 0) return null

            held = (held << 6) | v
            bits = bits + 6

            if (bits >= 8) {
                bits = bits - 8
                out[at] = (held >> bits) & 255
                at = at + 1
            }
        }

        return out.subarray(0, at)
    }

    // `m=19456,t=2,p=1` -- one of the three by its letter, read the way monocypher reads it.
    const argon2Setting = (text, letter) => {
        let at = 0

        for (;;) {
            if (at + 1 >= text.length) return null
            if (text[at + 1] !== "=") return null

            let end = at + 2

            while (end < text.length && text[end] !== ",") end = end + 1

            if (text[at] === letter) {
                const digits = text.slice(at + 2, end)

                if (digits.length === 0 || digits.length > 10 || !/^[0-9]+$/.test(digits)) return null

                return Number(digits)
            }

            if (end >= text.length) return null

            at = end + 1
        }
    }

    // A record, read. **Five separators and six fields, the first empty**, because the string
    // begins with one.
    const argon2Parse = (text) => {
        const parts = text.split("$")

        if (parts.length !== 6 || parts[0] !== "") return null

        const algorithm = parts[1]

        if (algorithm !== "argon2id" && algorithm !== "argon2i" && algorithm !== "argon2d") return null
        if (parts[2] !== "v=19") return null

        const blocks = argon2Setting(parts[3], "m")
        const passes = argon2Setting(parts[3], "t")
        const lanes = argon2Setting(parts[3], "p")

        if (blocks === null || passes === null || lanes === null) return null

        const salt = argon2Unb64(parts[4])
        const hash = argon2Unb64(parts[5])

        if (salt === null || hash === null) return null
        if (salt.length < 8 || salt.length > ARGON2_MAX_SALT) return null
        if (hash.length < 4 || hash.length > ARGON2_MAX_TAG) return null

        return { algorithm: algorithm, blocks: blocks, passes: passes, lanes: lanes, salt: salt, hash: hash }
    }

    const argon2Encode = (algorithm, blocks, passes, lanes, salt, hash) =>
        "$" + algorithm + "$v=19$m=" + blocks + ",t=" + passes + ",p=" + lanes + "$" +
            argon2B64(salt) + "$" + argon2B64(hash)

    const argon2Unreadable = (name) =>
        fault("`" + name + "` was given text that is not an Argon2 record -- what `argon2` " +
            "answers begins `$argon2id$` and carries its own parameters, and this does not")

    // -- what a call may ask for -------------------------------------------------------------

    const argon2Password = (v, name) => {
        if (!$.isStr(v))
            fault("`" + name + "` takes the password as text, and this is " + typeName(v))

        return new TextEncoder().encode(v)
    }

    const argon2Record = (v, name, what) => {
        if (!$.isStr(v))
            fault("`" + name + "` takes " + what + " as text, and this is " + typeName(v))

        return v
    }

    // One numeric parameter, bounded, with the default where it was left out.
    const argon2Number = (opts, key, low, high, fallback) => {
        if (opts === null) return fallback

        const v = opts.lookup(key)[0]

        if (v === undefined) return fallback

        if (!$.isInt(v)) fault("`" + key + "` is a whole number, and this is " + typeName(v))

        const n = Number(v)

        if (n < low || n > high)
            fault("`" + key + "` runs from " + low + " to " + high + " and this is " + v)

        return n
    }

    // The `salt` parameter, as bytes. **Text or an array**, since a vector is published either way.
    const argon2Salt = (opts) => {
        if (opts === null) return null

        const v = opts.lookup("salt")[0]

        if (v === undefined) return null

        let bytes = null

        if ($.isStr(v)) bytes = new TextEncoder().encode(v)
        else if (v instanceof $.SBytes) bytes = v.view()
        else if (Array.isArray(v)) {
            bytes = new Uint8Array(v.length)

            for (let i = 0; i < v.length; i = i + 1) {
                const b = v[i]

                if (!$.isInt(b))
                    fault("`salt` takes an array of numbers, and one of these is " + typeName(b))

                if (b < 0n || b > 255n) fault("a byte is between 0 and 255, and this is " + b)

                bytes[i] = Number(b)
            }
        } else fault("`salt` is text or bytes, and this is " + typeName(v))

        if (bytes.length < 8 || bytes.length > ARGON2_MAX_SALT)
            fault("an Argon2 salt is between 8 and " + ARGON2_MAX_SALT + " bytes, and this is " + bytes.length)

        return bytes
    }

    // The second argument of any of the three, read into what the call will run with.
    //
    // **An unknown key is refused rather than ignored**, and the reason is the worst shape the
    // mistake has: `{ memoryCosts: 65536 }` is a login that was thought to have been
    // strengthened and was not.
    const argon2Wanted = (args, at, name) => {
        let opts = null

        if (args.length > at) {
            const v = args[at]

            if (!(v instanceof $.SObj))
                fault("`" + name + "` takes its parameters as a record, and this is " + typeName(v))

            for (const [k, held] of v.entries()) {
                if (typeof k !== "string")
                    fault("an option is named, and this is " + typeName(k))

                if (ARGON2_KNOWN.indexOf(k) < 0)
                    fault("`" + k + "` is not one of `" + name + "`'s parameters -- there are " +
                        ARGON2_OPTIONS)
            }

            opts = v
        }

        const lanes = argon2Number(opts, "parallelism", 1, 16777215, ARGON2_LANES)
        const blocks = argon2Number(opts, "memoryCost", 8 * lanes, ARGON2_MAX_BLOCKS, ARGON2_BLOCKS)
        const passes = argon2Number(opts, "timeCost", 1, 4294967295, ARGON2_PASSES)
        const tag = argon2Number(opts, "hashLength", 4, ARGON2_MAX_TAG, ARGON2_TAG)

        return { blocks: blocks, passes: passes, lanes: lanes, tag: tag, salt: argon2Salt(opts) }
    }

    // The host's derivation, as a promise of the tag.
    //
    // **The async form rather than `argon2Sync`, and it is the same decision the interpreter
    // made**: this is the one call in the language that is supposed to take a tenth of a second,
    // and done on the loop that is a tenth of a second in which a server answers nobody.
    const argon2Derive = (algorithm, message, nonce, want) =>
        new Promise((resolve, reject) => {
            argon2Host.argon2(algorithm, {
                message: message,
                nonce: nonce,
                parallelism: want.lanes,
                tagLength: want.tag,
                memory: want.blocks,
                passes: want.passes
            }, (err, tag) => err ? reject(err) : resolve(new Uint8Array(tag)))
        })

    // `argon2(password)` and `argon2(password, parameters)` -- a promise of the record to store.
    B.argon2 = (...args) => {
        if (args.length < 1 || args.length > 2)
            fault("`argon2` takes a password and, if it is not to use the defaults, its parameters -- and was given " +
                counted(args.length))

        const message = argon2Password(args[0], "argon2")
        const want = argon2Wanted(args, 1, "argon2")

        if (message.length > ARGON2_MAX_PASSWORD)
            fault("`argon2` was given a password of " + message.length + " bytes, and " +
                ARGON2_MAX_PASSWORD + " is the longest it will derive from")

        if (argon2Host === null) noArgon2("argon2")

        let nonce = want.salt

        // **The kernel rather than anything in this program**, and the same call `randomBytes`
        // makes: a salt a program worked out is a salt that is not there.
        if (nonce === null) {
            const source = typeof crypto !== "undefined" && crypto !== null ? crypto : null

            if (source === null || typeof source.getRandomValues !== "function")
                fault("`argon2` could not get randomness from the kernel, and a password hashed with a salt this program made up would not be worth storing")

            nonce = new Uint8Array(ARGON2_SALT)
            source.getRandomValues(nonce)
        }

        return argon2Derive("argon2id", message, nonce, want).then((tag) =>
            argon2Encode("argon2id", want.blocks, want.passes, want.lanes, nonce, tag))
    }

    // `argon2Verify(record, password)` -- a promise of whether that password made that record.
    //
    // **A wrong password is `false` and a record that will not parse is a FAULT**, which is the
    // one confusion a login path must not have: a corrupted column is a defect in whatever wrote
    // it, and reading it as an intruder answers 401 to somebody whose password was right.
    B.argon2Verify = (...args) => {
        if (args.length !== 2)
            fault("`argon2Verify` takes a stored record and a password, and was given " + counted(args.length))

        const stored = argon2Record(args[0], "argon2Verify", "the stored record")
        const password = argon2Record(args[1], "argon2Verify", "the password")
        const record = argon2Parse(stored)

        // **Both arguments are text, so a swap would answer `false` forever and never say why.**
        // A second argument that IS a record while the first is not can only be the pair the
        // other way round.
        if (record === null) {
            if (argon2Parse(password) !== null)
                fault("`argon2Verify` takes the stored record first and the password second, and these are the other way round")

            argon2Unreadable("argon2Verify")
        }

        if (record.blocks > ARGON2_MAX_BLOCKS)
            fault("this record asks for " + Math.floor(record.blocks / 1024) +
                " MiB of working memory, which is more than any real Argon2 parameter reaches -- " +
                "it is not a record this program wrote")

        const message = new TextEncoder().encode(password)

        if (message.length > ARGON2_MAX_PASSWORD)
            fault("`argon2Verify` was given a password of " + message.length + " bytes, and " +
                ARGON2_MAX_PASSWORD + " is the longest it will derive from")

        if (argon2Host === null) noArgon2("argon2Verify")

        const want = { blocks: record.blocks, passes: record.passes, lanes: record.lanes,
            tag: record.hash.length }

        // **The comparison is constant time**, for the reason a MAC's is: how long it took is a
        // measurement, and one made a byte at a time over many attempts is a password.
        return argon2Derive(record.algorithm, message, record.salt, want)
            .then((tag) => sameTag(tag, record.hash))
    }

    // `argon2NeedsRehash(record)` and `argon2NeedsRehash(record, parameters)`.
    //
    // **This one derives nothing and so it works in a page too.** It reads the parameters out of
    // the record and compares them, which is microseconds and a string parse; a promise here
    // would be ceremony, and a refusal here would be a refusal to read.
    B.argon2NeedsRehash = (...args) => {
        if (args.length < 1 || args.length > 2)
            fault("`argon2NeedsRehash` takes a stored record and, if they are not the defaults, the parameters to measure it against -- and was given " +
                counted(args.length))

        const stored = argon2Record(args[0], "argon2NeedsRehash", "the stored record")
        const want = argon2Wanted(args, 1, "argon2NeedsRehash")
        const record = argon2Parse(stored)

        if (record === null) argon2Unreadable("argon2NeedsRehash")

        return record.algorithm !== "argon2id" || record.blocks < want.blocks ||
            record.passes < want.passes || record.lanes !== want.lanes
    }

    // -- reading the arguments -------------------------------------------------------------------

    // A lead surrogate says a string holds a character `RegExp` counts as two.
    const RE_ASTRAL = /[\uD800-\uDBFF]/

    const wantRegex = (v, name) => {
        if (!(v instanceof SRegex))
            fault("`" + name + "` takes a regular expression, and this is " + typeName(v))

        return REGEX_TABLE[v.id]
    }

    const wantSubject = (v, name, which) => {
        if (!$.isStr(v)) fault("`" + name + "` takes " + which + ", and this is " + typeName(v))

        return v
    }

    // **UTF-16 offsets into CHARACTER positions, in ONE walk of the subject.** `RegExp` under
    // `u` matches by code point and still reports in code units, so an astral character before
    // a match makes every offset after it one too many. `regex.sysl`'s `char_positions` is the
    // interpreter's copy of this and costs the same: one walk per match.
    //
    // **A subject with no lead surrogate in it needs no walk at all**, a unit and a character
    // being the same thing there, which is every subject most programs ever hand this.
    const rePositions = (subject, offsets) => {
        if (!RE_ASTRAL.test(subject)) return offsets

        const out = offsets.slice()
        let n = 0
        let i = 0

        while (i < subject.length) {
            for (let k = 0; k < offsets.length; k++) if (offsets[k] === i) out[k] = n

            i += subject.codePointAt(i) > 0xFFFF ? 2 : 1
            n++
        }

        // An offset at the very end of the subject falls on no character, so the walk never
        // reaches it.
        for (let k = 0; k < offsets.length; k++) if (offsets[k] === subject.length) out[k] = n

        return out
    }

    // -- finding ---------------------------------------------------------------------------------

    // Every match, left to right and non-overlapping, or the leftmost one where `first`.
    //
    // **The advance after an EMPTY match is by one CHARACTER and this is the whole of the rule.**
    // Advancing by the match's length would find the same empty match forever; advancing by a
    // code UNIT would stop in the middle of an astral character and match nothing there.
    const reMatches = (entry, subject, first) => {
        const re = entry.re
        const found = []
        let at = 0

        while (at <= subject.length) {
            re.lastIndex = at

            const m = re.exec(subject)

            if (m === null) break

            found.push(m)

            if (first) break

            at = m.index + m[0].length

            if (m[0].length === 0) at += subject.codePointAt(m.index) > 0xFFFF ? 2 : 1
        }

        return found
    }

    // What a program is handed for a match: the text, where it landed, its groups and its named
    // groups.
    //
    // **`groups` holds the whole match at 0** and **`named` is always here, empty where the
    // pattern names nothing** -- both `regex.sysl`'s rules, and the second one is what stops the
    // shape of a match depending on the pattern that made it.
    //
    // **A group that took no part is `null` and not `undefined`**, slate's absence being a thing
    // that may not be stored in a container at all.
    const reMatchValue = (m, subject) => {
        const where = rePositions(subject, [m.index, m.index + m[0].length])
        const groups = []

        for (let i = 0; i < m.length; i++) groups.push(m[i] === undefined ? null : m[i])

        const named = []

        if (m.groups !== undefined)
            for (const name of Object.keys(m.groups))
                named.push([name, m.groups[name] === undefined ? null : m.groups[name]])

        return $.obj([["text", m[0]], ["start", BigInt(where[0])], ["end", BigInt(where[1])],
            ["groups", groups], ["named", $.obj(named)]])
    }

    // -- replacing -------------------------------------------------------------------------------

    // **ECMAScript's `GetSubstitution`, which is the host's and not written out here.** `$$` is
    // a dollar, `$&` the match, `` $` `` and `$'` what is before and after it, `$1` a numbered
    // group and `$<name>` a named one -- and **anything else after a `$` is literal text**,
    // including a `$9` in a pattern with fewer than nine groups. `sh.sysl.libregexp`'s `expand`
    // is the same specification on the other back end.
    //
    // **The `g` pattern replaces every match and the one without it replaces the leftmost**,
    // which is `String.prototype.replace`'s own rule and is exactly the distinction slate draws
    // between `replace` and `replaceFirst`. `Symbol.replace` puts `lastIndex` back to zero on a
    // global pattern before it starts, so the walk above and this share a `RegExp` safely.
    const reSubstitute = (args, name, every) => {
        wantArgs(args.length, 3, 3, name, "a regular expression, a subject and a replacement")

        const entry = wantRegex(args[0], name)
        const subject = wantSubject(args[1], name, "a subject")
        const spec = wantSubject(args[2], name, "a replacement")

        return subject.replace(every ? entry.re : entry.first, spec)
    }

    // -- what a program calls ----------------------------------------------------------------------

    // `regex(pattern)` and `regex(pattern, flags)`.
    B.regex = (...args) => {
        wantArgs(args.length, 1, 2, "regex", "a pattern and optionally its flags")

        const source = wantSubject(args[0], "regex", "a pattern")
        const flags = args.length > 1 ? wantSubject(args[1], "regex", "its flags") : ""

        return regexSlot(source, flags)
    }

    // `re.test(s)` -- whether the subject matches anywhere.
    B.$reTest = (...args) => {
        wantArgs(args.length, 2, 2, "test", "a regular expression and a subject")

        const entry = wantRegex(args[0], "test")
        const subject = wantSubject(args[1], "test", "a subject")

        // **`lastIndex` is set on every use and never read**, which is how a pattern here
        // carries no position: `RegExp`'s `g` is what the walk needs and its mutable cursor is
        // the surprise `regex.sysl` exists not to have.
        entry.re.lastIndex = 0

        return entry.re.test(subject)
    }

    // `re.find(s)` -- the leftmost match, or null.
    B.$reFind = (...args) => {
        wantArgs(args.length, 2, 2, "find", "a regular expression and a subject")

        const entry = wantRegex(args[0], "find")
        const subject = wantSubject(args[1], "find", "a subject")
        const found = reMatches(entry, subject, true)

        return found.length === 0 ? null : reMatchValue(found[0], subject)
    }

    // `re.findAll(s)` -- every match, left to right and non-overlapping.
    B.$reFindAll = (...args) => {
        wantArgs(args.length, 2, 2, "findAll", "a regular expression and a subject")

        const entry = wantRegex(args[0], "findAll")
        const subject = wantSubject(args[1], "findAll", "a subject")

        return reMatches(entry, subject, false).map((m) => reMatchValue(m, subject))
    }

    // `re.replace(s, with)` -- **every** match replaced -- and `re.replaceFirst(s, with)`, which
    // stops at the leftmost.
    B.$reReplace = (...args) => reSubstitute(args, "replace", true)
    B.$reReplaceFirst = (...args) => reSubstitute(args, "replaceFirst", false)

    // `re.split(s)` -- the pieces between the matches. **The captured groups are not among
    // them**, which is where JavaScript's `String.split` differs and `regex.sysl` does not.
    B.$reSplit = (...args) => {
        wantArgs(args.length, 2, 2, "split", "a regular expression and a subject")

        const entry = wantRegex(args[0], "split")
        const subject = wantSubject(args[1], "split", "a subject")
        const pieces = []
        let last = 0

        for (const m of reMatches(entry, subject, false)) {
            pieces.push(subject.slice(last, m.index))
            last = m.index + m[0].length
        }

        pieces.push(subject.slice(last))

        return pieces
    }

    // `re.pattern()` and `re.flags()` -- what it was written as, and what it was made with.
    B.$rePattern = (...args) => {
        wantArgs(args.length, 1, 1, "pattern", "a regular expression")

        return wantRegex(args[0], "pattern").source
    }

    B.$reFlags = (...args) => {
        wantArgs(args.length, 1, 1, "flags", "a regular expression")

        return wantRegex(args[0], "flags").flags
    }

    // **Every one of the eight goes through `OVERRIDES` and not through its own name in `B`.**
    // Three of them collide with a builtin an array or a string already answers to, and the
    // other five would become globals a program cannot then use for its own -- `pattern` and
    // `flags` being exactly the words somebody names a variable.
    OVERRIDES.set("regex.test", B.$reTest)
    OVERRIDES.set("regex.find", B.$reFind)
    OVERRIDES.set("regex.findAll", B.$reFindAll)
    OVERRIDES.set("regex.replace", B.$reReplace)
    OVERRIDES.set("regex.replaceFirst", B.$reReplaceFirst)
    OVERRIDES.set("regex.split", B.$reSplit)
    OVERRIDES.set("regex.pattern", B.$rePattern)
    OVERRIDES.set("regex.flags", B.$reFlags)

    // `method.sysl`'s `regex_method`, name for name.
    KINDS.regex = ["test", "find", "findAll", "replace", "replaceFirst", "split", "pattern",
        "flags"]

    // -- what this host provides -------------------------------------------------------------------

    // The names a host is asked for. **A fixed set, and an unknown one is a fault** -- a
    // misspelling that answered false for ever would send a module down the path it was asking
    // how to avoid. `host.sysl` carries the same list for the interpreter and a test pins that
    // the two agree.
    const HOST_THINGS = ["websocket", "compression", "fetch"]

    B.hostHas = (...args) => {
        wantArgs(args.length, 1, 1, "hostHas", "the name of a thing a host may provide")

        const name = wantString(args[0], "hostHas")

        if (name === "websocket") return $.host.webSocket !== null
        if (name === "compression")
            return $.host.compression !== null && $.host.decompression !== null
        if (name === "fetch") return $.host.fetch !== null

        fault("`" + name + "` is not something a host is asked for -- the names are " +
            HOST_THINGS.map((s) => "`" + s + "`").join(", ").replace(/, ([^,]*)$/, " and $1"))
    }

    // `host()` -- which of the three hosts this program is running on, for a PROGRAM to ask
    // rather than a built-in module. `host.sysl` answers `"interpreter"` on the other back end;
    // here there is no third case to tell apart from `document`, node being what runs an
    // emitted program anywhere a browser's `document` is not there to be found.
    B.host = (...args) => {
        wantArgs(args.length, 0, 0, "host", "no arguments")

        return $.host.document !== null ? "browser" : "node"
    }

    // -- the host's own WebSocket ------------------------------------------------------------------

    const WS_HELD = new Map()
    let wsCounter = 0n

    const wsOk = (v) => $.obj([["ok", true], ["value", v]])
    const wsBad = (message) => $.obj([["ok", false], ["error", message]])

    const wsWanted = (id, name) => {
        const held = WS_HELD.get(id)

        if (held === undefined)
            fault("`" + name + "` was given a connection that is not open")

        return held
    }

    // A message as slate sees it: text stays text, and binary is the buffer every other byte
    // surface in the language uses.
    //
    // **`binaryType` is set to `arraybuffer` on the way in**, because a browser's default is a
    // `Blob` and a Blob is read asynchronously -- which would make `onBinary` answer at some
    // later turn on one host and at once on the other.
    const wsPayload = (data) =>
        typeof data === "string" ? data : $.bytesOf(new Uint8Array(data))

    // **A buffer or an array of numbers, which is `bytesLike` everywhere else.** The second
    // reading is what keeps a program written before the buffer existed working.
    const wsBytesOut = (v, name) => $.bytesLike(v, name)

    // `wsOpen(url)` -- a promise of a result carrying the connection.
    //
    // **The same shape `connect` has in `slate:net`**, and for its reason: a connection that is
    // refused is the ordinary thing a client deals with, so it comes back as `{ ok: false,
    // error }` rather than as a fault. That is what lets `slate:ws`'s two clients answer one
    // thing.
    //
    // **The promise settles on the FIRST of open and error and never twice.** A browser fires
    // `error` and then `close` for a connection that never opened, and a `close` after a
    // successful open is an ordinary end rather than a failure of the open.
    B.wsOpen = (...args) => {
        wantArgs(args.length, 1, 1, "wsOpen", "a url")

        const url = wantString(args[0], "wsOpen")

        if ($.host.webSocket === null)
            fault("`wsOpen` needs the host's own WebSocket, and this JavaScript host has none")

        return new Promise((answer) => {
            let sock = null

            // **A bad url is refused by the constructor**, which is the one failure that is not
            // an event and would otherwise leave the promise pending for ever.
            try {
                sock = new $.host.webSocket(url)
            } catch (e) {
                answer(wsBad(String(e !== null && e !== undefined && e.message !== undefined ? e.message : e)))

                return
            }

            sock.binaryType = "arraybuffer"

            wsCounter = wsCounter + 1n

            const id = wsCounter
            const held = { sock: sock, heard: null, gone: null, settled: false }

            WS_HELD.set(id, held)

            sock.onopen = () => {
                if (held.settled) return

                held.settled = true
                answer(wsOk(id))
            }

            sock.onerror = () => {
                if (held.settled) return

                held.settled = true
                WS_HELD.delete(id)
                answer(wsBad("the connection to " + url + " could not be opened"))
            }

            sock.onmessage = (e) => {
                if (held.heard !== null) $.callback(held.heard, [wsPayload(e.data)], "onMessage")
            }

            sock.onclose = (e) => {
                WS_HELD.delete(id)

                if (held.gone !== null) $.callback(held.gone, [BigInt(e.code), e.reason], "onClose")
            }
        })
    }

    B.wsSend = (...args) => {
        wantArgs(args.length, 2, 2, "wsSend", "a connection and a message")

        wsWanted(args[0], "wsSend").sock.send(wantString(args[1], "wsSend"))

        return null
    }

    B.wsSendBytes = (...args) => {
        wantArgs(args.length, 2, 2, "wsSendBytes", "a connection and its bytes")

        wsWanted(args[0], "wsSendBytes").sock.send(wsBytesOut(args[1], "wsSendBytes"))

        return null
    }

    // **One handler for both kinds of message, and the module tells them apart by what arrives.**
    // A browser's `message` event carries either, so two setters here would be two names for one
    // event and a module holding only one of them would drop half the traffic.
    B.wsOnMessage = (...args) => {
        wantArgs(args.length, 2, 2, "wsOnMessage", "a connection and a function")

        wsWanted(args[0], "wsOnMessage").heard = args[1]

        return null
    }

    B.wsOnClose = (...args) => {
        wantArgs(args.length, 2, 2, "wsOnClose", "a connection and a function")

        wsWanted(args[0], "wsOnClose").gone = args[1]

        return null
    }

    // **Closing a connection that has already gone is not an error**, which is `slate:net`'s rule
    // for `close` and is what lets a program close on its way out without asking first.
    B.wsClose = (...args) => {
        wantArgs(args.length, 1, 3, "wsClose", "a connection, and optionally a code and a reason")

        const held = WS_HELD.get(args[0])

        if (held === undefined) return null

        const code = args.length > 1 ? Number(wantInt(args[1], "wsClose")) : 1000
        const why = args.length > 2 ? wantString(args[2], "wsClose") : ""

        WS_HELD.delete(args[0])
        held.sock.close(code, why)

        return null
    }

    // -- slate's bytes, and the runtime's ----------------------------------------------------

    // **The sentences are `gz_source`'s in `gzip.sysl`, word for word**, which is what the
    // differential corpus is checking. `bytes_of` is what the interpreter reads an array with
    // and its two complaints are the two below.
    const gzBytes = (v, name) => {
        if ($.isStr(v)) return new TextEncoder().encode(v)
        if (v instanceof $.SBytes) return v.view()

        if (!Array.isArray(v))
            fault("`" + name + "` takes text or bytes, and this is " + typeName(v))

        const out = new Uint8Array(v.length)

        for (let i = 0; i < v.length; i = i + 1) {
            const b = v[i]

            if (!$.isInt(b))
                fault("`" + name + "` takes an array of numbers, and one of these is " + typeName(b))

            if (b < 0n || b > 255n) fault("a byte is between 0 and 255, and this is " + b)

            out[i] = Number(b)
        }

        return out
    }

    // **What every call here answers: a BUFFER**, which is the interpreter's answer and is what
    // a compressed body is for -- `Array.from(bytes, BigInt)` cost a whole tagged value per byte
    // of something the program was about to write to a socket.
    const gzArray = (bytes) => $.bytesOf(bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes))

    const gzLimit = (v, name) => {
        if (!$.isInt(v))
            fault("`" + name + "` takes the most it may become as a whole number, and this is " + typeName(v))

        if (v < 0n) fault("a limit is a number of bytes and this is " + v)

        return Number(v)
    }

    // **Both halves are asked for, because `hostHas("compression")` is one question.** A host
    // with one and not the other is not a host that compresses.
    const gzHave = (name) => {
        if ($.host.compression === null || $.host.decompression === null)
            fault("`" + name + "` needs the host's own compression, and this JavaScript host has no `CompressionStream`")
    }

    const gzOk = (v) => $.obj([["ok", true], ["value", v]])
    const gzBad = (message) => $.obj([["ok", false], ["error", message]])

    // Run bytes through one of the host's streams, gathering what comes out.
    //
    // **`cap` is what stops a bomb**, and it is counted as the chunks arrive rather than checked
    // at the end: a few hundred bytes of crafted deflate expands without bound, so the point of
    // a limit is never to hold the whole of what it refuses.
    const gzThrough = async (kind, bytes, cap) => {
        const stream = cap === null ? new $.host.compression(kind) : new $.host.decompression(kind)
        const writer = stream.writable.getWriter()
        const reader = stream.readable.getReader()

        // **The write is not awaited and its rejection is swallowed here**, because a stream
        // that fails fails at BOTH ends: the reader is where the failure is read, and an
        // unhandled rejection on the writer's copy of it would stop the program instead.
        writer.write(bytes).then(() => writer.close()).catch(() => {})

        const pieces = []
        let total = 0

        for (;;) {
            const step = await reader.read()

            if (step.done) break

            total = total + step.value.length

            if (cap !== null && total > cap) {
                reader.cancel().catch(() => {})

                return null
            }

            pieces.push(step.value)
        }

        const out = new Uint8Array(total)
        let at = 0

        for (const piece of pieces) {
            out.set(piece, at)
            at = at + piece.length
        }

        return out
    }

    // -- the gzip container, read the way `gzip.sysl` reads it -------------------------------

    const gzLe32 = (bytes, at) =>
        bytes[at] + bytes[at + 1] * 256 + bytes[at + 2] * 65536 + bytes[at + 3] * 16777216

    const gzPastNul = (bytes, from) => {
        let i = from

        for (;;) {
            if (i >= bytes.length) return -1

            const c = bytes[i]

            i = i + 1

            if (c === 0) return i
        }
    }

    // Where the deflate body starts, or the sentence saying why there is not one.
    const gzBodyAt = (bytes) => {
        if (bytes.length < 18) return "this is too short to be a gzip stream"

        if (bytes[0] !== 0x1f || bytes[1] !== 0x8b)
            return "this does not begin with gzip's two magic bytes, so it is not a gzip stream"

        if (bytes[2] !== 8)
            return "this gzip stream says it uses compression method " + bytes[2] +
                ", and the only one there is is deflate"

        const flags = bytes[3]
        let at = 10

        if ((flags & 0x04) !== 0) {
            if (at + 2 > bytes.length) return "this gzip stream ends inside its header"

            at = at + 2 + bytes[at] + bytes[at + 1] * 256
        }

        if ((flags & 0x08) !== 0) {
            at = gzPastNul(bytes, at)

            if (at < 0) return "this gzip stream ends inside its header"
        }

        if ((flags & 0x10) !== 0) {
            at = gzPastNul(bytes, at)

            if (at < 0) return "this gzip stream ends inside its header"
        }

        if ((flags & 0x02) !== 0) at = at + 2
        if (at + 8 > bytes.length) return "this gzip stream ends inside its header"

        return at
    }

    // The CRC-32 gzip's trailer carries, which is the one thing miniz has and a host does not.
    //
    // **A table built once**, since the alternative is a bit loop over every byte of every
    // answer -- and the checksum is what tells a damaged download from a wrong one.
    const GZ_CRC = (() => {
        const table = new Uint32Array(256)

        for (let i = 0; i < 256; i = i + 1) {
            let c = i

            for (let k = 0; k < 8; k = k + 1) c = (c & 1) !== 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1

            table[i] = c >>> 0
        }

        return table
    })()

    const gzCrc32 = (bytes) => {
        let c = 0xFFFFFFFF

        for (let i = 0; i < bytes.length; i = i + 1) c = GZ_CRC[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8)

        return (c ^ 0xFFFFFFFF) >>> 0
    }

    // What a host says when the body would not inflate.
    //
    // **One sentence where the interpreter has three**, and it is written as a plain statement
    // rather than as one of miniz's: a host's decompressor throws the same `TypeError` for a
    // truncated stream, a corrupt one and a wrong checksum, so choosing one of the interpreter's
    // words would be a guess presented as a finding. Everything a CONTAINER can say is said
    // above and below instead, which is most of what a caller ever meets.
    const GZ_UNREADABLE = "this compressed stream could not be read"

    // The two miniz raises about a stream rather than about its contents.
    const GZ_NOT_ONE = "this is not a compressed stream at all"
    const GZ_ENDS = "this compressed stream ends in the middle"

    // -- the zlib header, which is two bytes and says four things ----------------------------

    // **RFC 1950's own checks, and miniz makes all four**, so a stream that is not zlib at all is
    // refused in the same words on both back ends -- which is the case a caller actually hits,
    // somebody having handed a gzip stream or a JPEG to `inflate`. What is left to the host is a
    // header that is right and a body that is not.
    const gzZlibWrong = (bytes) => {
        if (bytes.length < 2) return GZ_ENDS

        const cmf = bytes[0]
        const flg = bytes[1]

        // The compression method, the window size, a preset dictionary this cannot supply, and
        // the check bits that make the pair a multiple of 31.
        if ((cmf & 0x0F) !== 8) return GZ_NOT_ONE
        if ((cmf >> 4) > 7) return GZ_NOT_ONE
        if ((flg & 0x20) !== 0) return GZ_NOT_ONE
        if ((cmf * 256 + flg) % 31 !== 0) return GZ_NOT_ONE

        return null
    }

    // -- the four names ----------------------------------------------------------------------

    B.gzip = (...args) => {
        wantArgs(args.length, 1, 1, "gzip", "what to compress")

        const bytes = gzBytes(args[0], "gzip")

        gzHave("gzip")

        return gzThrough("gzip", bytes, null).then(gzArray)
    }

    B.deflate = (...args) => {
        wantArgs(args.length, 1, 1, "deflate", "what to compress")

        const bytes = gzBytes(args[0], "deflate")

        gzHave("deflate")

        return gzThrough("deflate", bytes, null).then(gzArray)
    }

    B.gunzip = (...args) => {
        wantArgs(args.length, 2, 2, "gunzip",
            "what to decompress and the most it may become")

        const bytes = gzBytes(args[0], "gunzip")
        const cap = gzLimit(args[1], "gunzip")

        gzHave("gunzip")

        const at = gzBodyAt(bytes)

        if (typeof at === "string") return Promise.resolve(gzBad(at))

        // **The trailer is checked against the limit before a byte is asked for**, which is
        // `unwrapped`'s own order and is what makes the refusal the same sentence here.
        const size = gzLe32(bytes, bytes.length - 4)

        if (size > cap)
            return Promise.resolve(gzBad("this expands past the " + cap + " bytes it was allowed"))

        return gzThrough("deflate-raw", bytes.subarray(at, bytes.length - 8), cap).then((out) => {
            // **A trailer may lie**, so the cap is also counted as the chunks arrive; that is
            // what `null` means here.
            if (out === null)
                return gzBad("this expands past the " + cap + " bytes it was allowed")

            // **Two sentences for a trailer that lies, matching `unwrapped`'s two.** The
            // interpreter sizes its destination from `ISIZE` and so has no count to report for a
            // stream that held more; this one has inflated the whole thing and says the same
            // words anyway, or the two back ends would disagree over a damaged file.
            if (out.length > size)
                return gzBad("this gzip stream said it held " + size +
                    " bytes and holds more than that")

            if (out.length < size)
                return gzBad("this gzip stream said it held " + size + " bytes and produced " +
                    out.length)

            if (gzCrc32(out) !== gzLe32(bytes, bytes.length - 8))
                return gzBad("this gzip stream's checksum does not match its contents, so the bytes are damaged")

            return gzOk(gzArray(out))
        }, () => gzBad(GZ_UNREADABLE))
    }

    B.inflate = (...args) => {
        wantArgs(args.length, 2, 2, "inflate",
            "what to decompress and the most it may become")

        const bytes = gzBytes(args[0], "inflate")
        const cap = gzLimit(args[1], "inflate")

        gzHave("inflate")

        const wrong = gzZlibWrong(bytes)

        if (wrong !== null) return Promise.resolve(gzBad(wrong))

        return gzThrough("deflate", bytes, cap).then((out) => {
            if (out === null)
                return gzBad("this expands past the " + cap + " bytes it was allowed")

            return gzOk(gzArray(out))
        }, () => gzBad(GZ_UNREADABLE))
    }

    // -- brotli, which is the other half of the same answer ----------------------------------

    // **`slate:brotli` is a thing a JavaScript host does not have**, and it says so rather than
    // sitting on `OWED`. `CompressionStream` has no brotli in any browser and there is no
    // encoder in the platform to reach for, so "not in the JavaScript back end yet" would be a
    // promise nobody can keep -- which is `abbrev`'s case and gets `abbrev`'s treatment.
    // **The section goes with the `brotli` feature**, for `js_rt_lmdb.sysl`'s reason: a `B.compress`
    // this build registers no native for is a name in `$b` that nothing can reach, which is what
    // `tests_owed.sysl` compares the two sets to catch.

    const noBrotli = (name) => () =>
        fault("`" + name + "` is brotli, and a JavaScript host has no brotli encoder -- " +
            "`slate:gzip` is the compression a browser has")

    B.compress = noBrotli("compress")
    B.decompress = noBrotli("decompress")


        // -- zstd --------------------------------------------------------------------------------------

        // node's `zlib`, or nothing where there is none.
        const zstdHost = (() => {
            const load = $.host.require

            if (typeof process === "undefined" || typeof load !== "function") return null

            try {
                const zlib = load("node:zlib")

                return typeof zlib.zstdCompressSync === "function" ? zlib : null
            } catch (e) {
                return null
            }
        })()

        const noZstd = (name) =>
            fault("`" + name + "` is Zstandard, which this JavaScript host has not got -- no browser " +
                "has a `CompressionStream(\"zstd\")` and none is coming, and `slate:gzip` is the " +
                "compression a page does have")

        // What either name was given, as bytes. **Text crosses as its UTF-8**, which is what
        // `toBytes` would have made of it and what goes on a wire either way.
        const zstdSource = (v, name) => {
            if ($.isStr(v)) return Buffer.from(v, "utf8")
            if (v instanceof $.SBytes) return Buffer.from(v.view())

            if (Array.isArray(v)) {
                const bytes = []

                for (const b of v) {
                    if (!$.isInt(b)) fault("`" + name + "` takes an array of numbers, and one of these is " + typeName(b))

                    const n = Number(b)

                    if (n < 0 || n > 255) fault("a byte is between 0 and 255, and this is " + n)

                    bytes.push(n)
                }

                return Buffer.from(bytes)
            }

            fault("`" + name + "` takes text or bytes, and this is " + typeName(v))
        }

        const zstdWhole = (v, name, what) => {
            if (!$.isInt(v)) fault("`" + name + "` takes " + what + " as a whole number, and this is " + typeName(v))

            return Number(v)
        }

        // **A frame and what comes back out of one are BUFFERS**, which is the interpreter's answer.
        // It was a value per byte built in a loop, on a surface whose whole purpose is bytes going
        // somewhere else.
        const zstdBytes = (buf) => $.bytesOf(buf instanceof Uint8Array ? buf : Uint8Array.from(buf))

        // libzstd's own range, which node exposes as constants rather than as numbers to be guessed.
        const zstdMin = () => zstdHost.constants.ZSTD_minCLevel === undefined ? -131072 : zstdHost.constants.ZSTD_minCLevel
        const zstdMax = () => zstdHost.constants.ZSTD_maxCLevel === undefined ? 22 : zstdHost.constants.ZSTD_maxCLevel

        B.zstd = (...args) => {
            if (args.length !== 2)
                fault("`zstd` takes what to compress and a level, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            if (zstdHost === null) noZstd("zstd")

            const source = zstdSource(args[0], "zstd")
            const level = zstdWhole(args[1], "zstd", "the level")

            if (level < zstdMin() || level > zstdMax())
                fault("a zstd level runs from " + zstdMin() + " to " + zstdMax() + " and this is " + level)

            const params = {}

            params[zstdHost.constants.ZSTD_c_compressionLevel] = level

            // **The frame carries its own checksum**, which is what the interpreter asks for and is
            // the difference between a damaged stream and one that was never zstd.
            params[zstdHost.constants.ZSTD_c_checksumFlag] = 1

            try {
                return zstdBytes(zstdHost.zstdCompressSync(source, { params: params }))
            } catch (e) {
                fault("this could not be compressed: " + String(e && e.message ? e.message : e))
            }
        }

        // What a frame's header says it holds, or `null` where it says nothing.
        //
        // **THIS EXISTS BECAUSE node's DECOMPRESSOR IS SILENT ABOUT A FRAME THAT ENDS IN THE
        // MIDDLE.** `zstdDecompressSync` on half a frame answers an EMPTY buffer and throws nothing,
        // where libzstd's one-shot call -- which is what the interpreter reaches -- answers
        // `srcSize_wrong`. A wrong answer with no error is the worst shape a difference can take, so
        // the header is read and what came back is measured against what it claimed.
        //
        // **The header is four bytes of magic, a descriptor, and up to thirteen bytes of fields**,
        // and only the last of them is wanted. `Single_Segment_Flag` decides whether a window
        // descriptor is there; the dictionary id is 0, 1, 2 or 4 bytes; and the content size is
        // 0, 1, 2, 4 or 8, the two-byte form carrying an offset of 256.
        const zstdDeclared = (b) => {
            if (b.length < 5) return null
            if (b[0] !== 0x28 || b[1] !== 0xb5 || b[2] !== 0x2f || b[3] !== 0xfd) return null

            const flags = b[4]
            const field = flags >> 6
            const single = (flags >> 5) & 1
            const wide = field === 0 ? (single === 1 ? 1 : 0) : (field === 1 ? 2 : (field === 2 ? 4 : 8))

            if (wide === 0) return null

            let at = 5 + (single === 1 ? 0 : 1) + [0, 1, 2, 4][flags & 3]

            if (at + wide > b.length) return null

            if (wide === 1) return b[at]
            if (wide === 2) return b.readUInt16LE(at) + 256
            if (wide === 4) return b.readUInt32LE(at)

            const held = b.readBigUInt64LE(at)

            return held > BigInt(Number.MAX_SAFE_INTEGER) ? null : Number(held)
        }

        B.unzstd = (...args) => {
            if (args.length !== 2)
                fault("`unzstd` takes what to decompress and the most it may become, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            if (zstdHost === null) noZstd("unzstd")

            const source = zstdSource(args[0], "unzstd")
            const limit = zstdWhole(args[1], "unzstd", "the limit")

            if (limit < 0) fault("a limit is a number of bytes and this is " + limit)

            // **`maxOutputLength` is node's own bound and it is what makes the limit real.** Without
            // it a crafted frame of a few hundred bytes expands until the process dies, which is the
            // whole reason the argument exists and has no form that omits it.
            try {
                const back = zstdHost.zstdDecompressSync(source, { maxOutputLength: limit })
                const claimed = zstdDeclared(source)

                // **A frame that ends in the middle is what node answers nothing about**, so the
                // claim in its header is what says so. A frame that declared no size cannot be
                // checked this way and is the one case the two back ends read differently; the
                // module's page says so.
                if (claimed !== null && back.length !== claimed)
                    return $.obj([["ok", false], ["error", "this zstd frame ends in the middle"]])

                return $.obj([["ok", true], ["value", zstdBytes(back)]])
            } catch (e) {
                return $.obj([["ok", false], ["error", zstdWhy(e, limit)]])
            }
        }

        // What node objected to, said in the interpreter's words.
        //
        // **The two libraries answer the same three things and spell them differently**, so this is
        // the mapping rather than a passing on: too large is a body that would not fit, truncated is
        // a transfer that stopped, and corrupt is not zstd at all.
        const zstdWhy = (e, limit) => {
            const said = String(e && e.message ? e.message : e)

            if (e && (e.code === "ERR_BUFFER_TOO_LARGE" || e.code === "ERR_ZSTD_OUTPUT_TOO_LARGE") ||
                said.indexOf("maxOutputLength") >= 0 || said.indexOf("too large") >= 0)
                return "this expands past the " + limit + " bytes it was allowed"

            // **`unexpected end of file` is the same answer in a later node's words.** Node used to
            // hand back the short output for a frame that stopped early, leaving the declared-size
            // check above to notice; from 24.20 it throws instead. Both spellings are matched here
            // rather than one being replaced, because the version a host has is not this program's
            // to choose and a corpus that agreed on only one of them would go red on an upgrade.
            if (said.indexOf("Src size is incorrect") >= 0 || said.indexOf("srcSize") >= 0 ||
                said.indexOf("truncated") >= 0 || said.indexOf("unexpected end of file") >= 0)
                return "this zstd frame ends in the middle"

            return "this is not a zstd frame: " + said
        }

        // -- images ------------------------------------------------------------------------------

        const noImage = (name) => () =>
            fault("`" + name + "` decodes and writes images, and a JavaScript host has none -- node " +
                "has no image support in its standard library and a browser's is asynchronous " +
                "(`createImageBitmap`, `OffscreenCanvas`), where these answer on the spot. Resize " +
                "and re-encode on a server running the interpreter")

        B.readImage = noImage("readImage")
        B.imageShape = noImage("imageShape")
        B.resizeImage = noImage("resizeImage")
        B.encodePNG = noImage("encodePNG")
        B.encodeJPEG = noImage("encodeJPEG")

        B.encodeWebP = noImage("encodeWebP")


    // -- lmdb ----------------------------------------------------------------------------------

    // **`slate:lmdb` is a thing no JavaScript host has**, and it says so rather than sitting on
    // `OWED`. A browser has no memory-mapped file at all and node has no LMDB in its standard
    // library -- every binding is a native addon -- so "not in the JavaScript back end yet"
    // would be a promise nobody can keep.
    const noLmdb = (name) => () =>
        fault("`" + name + "` is LMDB, and no JavaScript host has it -- a browser has no " +
            "memory-mapped file and node's LMDB is a native addon, so this module runs in the " +
            "interpreter only")

    for (const name of ["lmdbOpen", "lmdbClose", "lmdbInfo",
        "lmdbRead", "lmdbWrite", "lmdbCommit", "lmdbAbort",
        "lmdbDb", "lmdbGet", "lmdbHas", "lmdbPut", "lmdbDelete", "lmdbClear", "lmdbStat",
        "lmdbCursor", "lmdbFirst", "lmdbNext", "lmdbSeek", "lmdbCursorClose"])
        B[name] = noLmdb(name)

    // -- actors --------------------------------------------------------------------------------

    // node's worker_threads, where this host is node at all.
    const WT = (() => {
        if ($.host.require === null) return null

        try {
            const m = $.host.require("node:worker_threads")

            return m !== null && m !== undefined && typeof m.Worker === "function" ? m : null
        } catch (e) {
            return null
        }
    })()

    // **Whether this very evaluation of the bundle is a worker, and the two hosts answer it
    // differently.** node hands the answer over in `workerData`, which is there before a line
    // runs; a page has nothing to hand over at construction, so the test is the global scope
    // itself and the start payload arrives as the first message.
    const NODE_START = WT !== null && WT.workerData !== null && WT.workerData !== undefined &&
        WT.workerData.$slateActor !== undefined ? WT.workerData.$slateActor : null

    const IN_PAGE_WORKER = typeof WorkerGlobalScope !== "undefined" && typeof self !== "undefined" &&
        self instanceof WorkerGlobalScope

    $.inWorker = NODE_START !== null || IN_PAGE_WORKER

    // The file this bundle was read from, which is what a node worker is started with. A browser
    // is the branch below it: a script with a `src` is a URL a `Worker` takes as it stands, and an
    // inline one is its own text through a blob.
    const SCRIPT_PATH = typeof __filename === "string" ? __filename : null

    const PAGE_SCRIPT = (() => {
        if (typeof document === "undefined" || document === null) return null

        const here = document.currentScript

        if (here === null || here === undefined) return null
        if (typeof here.src === "string" && here.src !== "") return { url: here.src, text: null }

        return { url: null, text: here.text }
    })()

    // What every name here says when this host cannot make a worker at all.
    const noWorkers = (name) =>
        fault("`" + name + "` needs a worker, and this JavaScript host has none -- an actor is a " +
            "worker, which node brings as `worker_threads` and a browser as `Worker`")

    // -- the declarations a message is rebuilt against -------------------------------------------

    // Every `class`, `data`, variant and `type` name the program declares, under the name it was
    // declared under. **The emitted program fills this on BOTH paths** -- the ordinary one and the
    // worker's declarations-only one -- because a message arriving on the main thread has to be
    // rebuilt there too.
    //
    // **A THUNK PER NAME rather than the value**, because these lines stand ABOVE the
    // declarations they name -- the registry has to be full before the module's own statements
    // run, and a `const` is in its dead zone until the line that fills it. Nothing calls one
    // until a message carrying that name arrives, by which time the declaration has run.
    //
    // **Guarded to a declaration, which is `declared_here`'s own rule**: a `type` alias binds a
    // value like anything else and is registered with the rest, and only a value carrying
    // `(class)` or `(data)` is ever answered.
    const DECLS = new Map()

    $.declared = (name, get) => { DECLS.set(name, get) }

    const declaredHere = (name) => {
        const get = DECLS.get(name)

        if (get === undefined) return undefined

        let held = undefined

        try {
            held = get()
        } catch (e) {
            // A name whose declaration has not run on this side yet is a name this side does
            // not have, which is the answer the caller is about to complain about anyway.
            return undefined
        }

        return held instanceof $.SObj && (held.hasName("(class)") || held.hasName("(data)"))
            ? held : undefined
    }

    // -- what a message may carry ----------------------------------------------------------------

    // **Each kind has its own sentence rather than a shared "is not sendable"**, because what a
    // reader has to do about it differs: a promise is awaited, a socket is not sent at all.
    // `not_sendable` in `actor_copy.sysl` is where these are written and the two must not drift.
    const notSendable = (v) => {
        if (v === undefined) return "undefined, which slate refuses to store anywhere at all"
        if (typeof v === "function") return "a function, and a function belongs to the heap it was made on"
        if (v instanceof Promise)
            return "a promise -- a promise is a suspended call on one machine's parked list rather " +
                "than a value in flight, so await it and send what it answers"
        if ($.isGen(v)) return "a generator, which is a line of execution on one machine rather than a value"
        if (v instanceof $.SSocket) return "a socket, which belongs to the event loop it was opened on"
        if (v instanceof $.SChild) return "a child process, which belongs to the program that started it"
        if (v instanceof $.SChannel) return "a channel, which belongs to the program that was started with it"
        if (v instanceof $.SExt) return "an external, which is a value of the JavaScript host rather than of slate"
        if (v instanceof WeakMap) return "a weak map, whose entries are one collector's business"
        if (v instanceof WeakRef) return "a weak reference, whose target is one collector's business"
        if (v instanceof $.SShape) return "a type, which is a pattern held on the heap it was declared on"

        return ""
    }

    // The words a refusal opens with, which name the KIND before the path names the place.
    const shortKind = (v) => {
        if (v === undefined) return "undefined"
        if (v instanceof $.SShape) return "a type"

        return $.typeName(v)
    }

    const atPath = (path) => path === "" ? "this value" : "`" + path + "`"

    // **`actorUnder` and `actorCounted` carry a prefix and the rest of this file's names do not**,
    // which is not a style: a `const` in this runtime is private to nothing, the emitted program
    // being one JavaScript file, so a helper named the same as another block's is a `SyntaxError`
    // that takes the whole program with it. `under` is `js_rt_json.sysl`'s and `counted` is
    // `js_rt_builtins.sysl`'s, and both were exactly that.
    const actorUnder = (path, key) => path === "" ? key : path + "." + key
    const nth = (path, i) => path + "[" + i + "]"

    // -- writing a value out ---------------------------------------------------------------------

    // The tags. They are numbers rather than words because every message carries them and nothing
    // reads one but the decoder below.
    const T_AGAIN = 0, T_ARRAY = 1, T_OBJECT = 2, T_SET = 3, T_MAP = 4, T_BYTES = 5, T_RANGE = 6,
        T_INSTANT = 7, T_DURATION = 8, T_DATE = 9, T_TIME = 10, T_DATETIME = 11, T_ZONE = 12,
        T_ZONED = 13, T_PERIOD = 14, T_REGEX = 15, T_ACTOR = 16, T_MESSAGE = 17, T_VEIL = 18

    // A whole call: the handler's name, then its arguments, through ONE encoder -- so two
    // arguments holding one object arrive holding one object, which is the same guarantee the
    // design states about two fields of one argument.
    const encodeAll = (values) => {
        const w = { seen: new Map(), moves: [] }
        const out = []

        for (let i = 0; i < values.length; i++) out.push(encodeValue(values[i], "", w))

        return { body: out, moves: w.moves }
    }

    const encodeValue = (v, path, w) => {
        const refused = notSendable(v)

        if (refused !== "")
            fault("a message may not carry " + shortKind(v) + ": " + atPath(path) + " is " + refused)

        if (v === null || typeof v === "boolean" || typeof v === "bigint" ||
            typeof v === "number" || typeof v === "string") return v

        // **A handle names an actor rather than memory, so it crosses as itself** -- and its
        // mailbox limit travels beside it, that limit being enforced in the SENDER and a receiver
        // of a handle being the next thing to send to it.
        if (v instanceof $.SActor) return [T_ACTOR, v.id, ACT.limits.get(v.id)]
        if (v instanceof $.SMessage) return [T_MESSAGE, v.id, v.name, ACT.limits.get(v.id)]

        if (v instanceof SInstant) return [T_INSTANT, v.us]
        if (v instanceof SDuration) return [T_DURATION, v.us]
        if (v instanceof SDate) return [T_DATE, v.day]
        if (v instanceof STime) return [T_TIME, v.us]
        if (v instanceof SDateTime) return [T_DATETIME, v.day, v.us]

        // **A zone travels as its IANA name**, which is the only thing that means the same on two
        // heaps -- the interpreter's rule word for word.
        if (v instanceof SZone) return [T_ZONE, v.name]
        if (v instanceof SZoned) return [T_ZONED, v.us, v.zone.name]
        if (v instanceof SPeriod) return [T_PERIOD, v.months, v.days]

        // **Rebuilt from its pattern and flags**, a compiled pattern being a slot in a table the
        // sending side keeps.
        if (v instanceof SRegex)
            return [T_REGEX, REGEX_TABLE[v.id].source, REGEX_TABLE[v.id].flags]

        if (v instanceof $.SRange)
            return [T_RANGE, v.lo, v.hi, v.inclusive, v.hasLo, v.hasHi, v.step]

        // **An opaque value crosses as its declaration and what it is made of.** Every worker runs
        // the one emitted program, so the declaration's number means the same on both sides.
        if (v instanceof $.SVeil) return [T_VEIL, v.kind, v.name, v.home, encodeValue(v.rep, path, w)]

        const already = w.seen.get(v)

        if (already !== undefined) return [T_AGAIN, already]

        if (v instanceof $.SBytes) return encodeBytes(v, w, false)

        if (Array.isArray(v)) {
            w.seen.set(v, w.seen.size)

            const out = [T_ARRAY, $.arrayShut(v) ? 1 : 0]

            for (let i = 0; i < v.length; i++) out.push(encodeValue(v[i], nth(path, i), w))

            return out
        }

        if (v instanceof $.SSet) {
            w.seen.set(v, w.seen.size)

            const out = [T_SET, v.t.frozen ? 1 : 0]
            let n = 0

            for (const m of v.values()) { out.push(encodeValue(m, nth(path, n), w)); n += 1 }

            return out
        }

        if (v instanceof $.SMap) {
            w.seen.set(v, w.seen.size)

            const out = [T_MAP, v.t.frozen ? 1 : 0]
            let n = 0

            for (const [k, m] of v.entries()) {
                out.push(encodeValue(k, nth(path, n), w))
                out.push(encodeValue(m, nth(path, n), w))
                n += 1
            }

            return out
        }

        if (v instanceof $.SObj) return encodeObject(v, path, w)

        fault("a message may not carry " + $.typeName(v) + ": " + atPath(path))
    }

    // **`transfer(b)` HANDS THE STORAGE OVER, so the sender's buffer is left empty** -- and what
    // makes that observable rather than an optimisation is exactly this: the sender no longer has
    // them. A buffer whose storage is a window into a larger one is COPIED instead, the transfer
    // list taking whole `ArrayBuffer`s and nothing smaller.
    const encodeBytes = (v, w, moving) => {
        w.seen.set(v, w.seen.size)

        const used = v.length

        if (!moving) return [T_BYTES, v.view().slice(), used, v.frozen ? 1 : 0]

        const whole = v.u.byteOffset === 0 && v.u.buffer.byteLength === v.u.length
        const carried = whole ? v.u : v.view().slice()

        v.u = new Uint8Array(0)
        v.n = 0

        w.moves.push(carried.buffer)

        return [T_BYTES, carried, used, v.frozen ? 1 : 0]
    }

    const encodeObject = (o, path, w) => {
        // **The transfer wrapper is looked for BEFORE anything else**, since it is an object in
        // every other respect and would otherwise be copied as one.
        const moving = o.getName("(transfer)")

        if (moving instanceof $.SBytes) {
            const again = w.seen.get(moving)

            return again === undefined ? encodeBytes(moving, w, true) : [T_AGAIN, again]
        }

        w.seen.set(o, w.seen.size)

        // **A class, a data type and a variant's maker are declarations rather than values to
        // copy.** The receiver already has all three under their own names.
        if (o.hasName("(class)") || o.hasName("(data)") || o.hasName("(shape)"))
            fault("a message may not carry a declaration: " + atPath(path) +
                " is a `class` or `data` name, and the receiver has its own -- send an instance instead")

        const made = $.variantName(o)
        const named = made !== null ? made : $.className(o)

        // **BOTH FLAGS CROSS, as bit 0 and bit 1** -- the interpreter carries the same pair
        // for the same reason: a value the program deliberately shut must not arrive open.
        const out = [T_OBJECT, named, (o.frozen ? 1 : 0) | (o.dataValue ? 2 : 0)]

        for (const [k, v] of o.entries()) {
            if (!$.walkedKey(o, k)) continue

            const key = typeof k === "string" ? k : ""

            out.push(encodeValue(k, actorUnder(path, key), w))
            out.push(encodeValue(v, actorUnder(path, key), w))
        }

        return out
    }

    // -- reading one back --------------------------------------------------------------------------

    const decodeAll = (body) => {
        const pool = []
        const out = []

        for (let i = 0; i < body.length; i++) out.push(decodeValue(body[i], pool))

        return out
    }

    // A zone by the name it crossed under, faulting where this side cannot read it -- the
    // interpreter's sentence, `actor_copy.sysl`'s `TagZone` arm.
    const zoneArrived = (name) => {
        const said = zoneNamed(name)

        if (said.error !== null)
            fault("a message carried the zone `" + name + "`, which this actor cannot read: " + said.error)

        return said.zone
    }

    const decodeValue = (v, pool) => {
        if (!Array.isArray(v)) return v

        const tag = v[0]

        if (tag === T_AGAIN) return pool[v[1]]

        if (tag === T_ACTOR) {
            if (v[2] !== undefined && !ACT.limits.has(v[1])) ACT.limits.set(v[1], v[2])

            return $.actorHandle(v[1])
        }

        if (tag === T_MESSAGE) {
            if (v[3] !== undefined && !ACT.limits.has(v[1])) ACT.limits.set(v[1], v[3])

            return $.actorMessage(v[1], v[2])
        }

        if (tag === T_INSTANT) return new SInstant(v[1])
        if (tag === T_DURATION) return new SDuration(v[1])
        if (tag === T_DATE) return new SDate(v[1])
        if (tag === T_TIME) return new STime(v[1])
        if (tag === T_DATETIME) return new SDateTime(v[1], v[2])
        // **The zone itself and not `zone(name)`'s answer**, which is a result: carrying that
        // made a zone arrive as `{ ok, value }` and a zoned reading arrive holding one, whose
        // name was then `undefined` on the way back.
        if (tag === T_ZONE) return zoneArrived(v[1])
        if (tag === T_ZONED) return new SZoned(v[1], zoneArrived(v[2]))
        if (tag === T_PERIOD) return new SPeriod(v[1], v[2])
        if (tag === T_REGEX) return B.regex(v[1], v[2])
        if (tag === T_VEIL) return new $.SVeil(v[1], v[2], v[3], decodeValue(v[4], pool))
        if (tag === T_RANGE) return new $.SRange(v[1], v[2], v[3], v[4], v[5], v[6])

        if (tag === T_BYTES) {
            const held = new $.SBytes(v[1], v[2])

            held.frozen = !!v[3]

            pool.push(held)

            return held
        }

        if (tag === T_ARRAY) {
            const made = []

            pool.push(made)

            for (let i = 2; i < v.length; i++) made.push(decodeValue(v[i], pool))

            // Closed AFTER it is filled, or the pushes above would be the writes it refuses.
            if (v[1]) $.shutArray(made)

            return made
        }

        if (tag === T_SET) {
            const made = new $.SSet()

            pool.push(made)

            for (let i = 2; i < v.length; i++) made.t.setKey(decodeValue(v[i], pool), null)

            made.t.frozen = !!v[1]

            return made
        }

        if (tag === T_MAP) {
            const made = new $.SMap()

            pool.push(made)

            for (let i = 2; i < v.length; i += 2) {
                const k = decodeValue(v[i], pool)

                made.t.setKey(k, decodeValue(v[i + 1], pool))
            }

            made.t.frozen = !!v[1]

            return made
        }

        if (tag === T_OBJECT) {
            const made = new $.SObj()

            pool.push(made)

            // **A class instance crosses as an instance and not as a plain object**, because both
            // sides ran the same declarations: the name it was declared under is looked up here
            // and becomes the rebuilt object's `proto`.
            const named = v[1]

            if (named !== null) {
                const cls = declaredHere(named)

                if (cls === undefined)
                    fault("a message named `" + named + "`, and this actor declares no such class")

                made.setName("proto", cls)
            }

            for (let i = 3; i < v.length; i += 2) {
                const k = decodeValue(v[i], pool)

                made.setKey(k, decodeValue(v[i + 1], pool))
            }

            made.frozen = (v[2] & 1) !== 0
            made.dataValue = (v[2] & 2) !== 0

            return made
        }

        fault("a message carried something this program cannot read back")
    }

    // -- the actor table, the ports, and the protocol ------------------------------------------------

    // **The main thread's own id is the empty string** -- it is the first actor, the one nobody
    // spawned, and a message addressed to it reaches the program rather than a handler.
    const ME = { id: null }

    const ACT = {
        // The main thread's children: id -> what is known about the worker serving it.
        kids: new Map(),

        // Messages for an actor whose worker has not been made yet. A worker spawning an actor
        // mints the id itself and tells the main thread to build one, so `spawn` still answers a
        // handle on the spot.
        queued: new Map(),

        // Promises this side is waiting on: ticket -> the two halves of one.
        waits: new Map(),

        // What this side has posted to each actor and not seen acknowledged, which is what the
        // mailbox limit is measured against -- in the SENDER, so overflow is a refusal where it
        // was written rather than a wait anywhere.
        outbox: new Map(),
        limits: new Map(),

        // Asks relayed between two workers, which only the main thread can see: ticket -> the
        // call, so that an actor dying rejects them.
        relayed: new Map(),

        // Who is watching an actor stop, on the main thread: id -> [[watcher, ticket]].
        watchers: new Map(),

        // The instance this worker serves, and the run-down flags.
        serving: null,
        stopping: false,
        busy: 0,

        // Whether this worker is still loading the program's modules, and what arrived while it
        // was. **A module may wait at its own top level**, so the load is awaited and there is a
        // window in which a call can land before the declaration this worker serves exists.
        loading: false,
        held: [],

        ticket: 0,
        minted: 0,

        // How many asks and dones this side is waiting for, and the handle that keeps the host's
        // loop turning while any of them are outstanding.
        open: 0,
        holder: null,

        port: null
    }

    const DEFAULT_MAILBOX = 65536
    const DEFAULT_HEAP = 67108864

    // **A WORKER IS UNREF'D EXCEPT WHILE THIS SIDE IS WAITING**, which is the interpreter's
    // `keep`/`unref` on its own mailbox and is what stops a program hanging on an actor nobody is
    // talking to. The keeper is an interval that never fires: a ref'd handle and nothing else.
    const keepOpen = () => {
        ACT.open += 1

        if (ACT.open === 1 && ACT.holder === null && $.host.setInterval !== null)
            ACT.holder = $.host.setInterval(() => {}, 2147483647)
    }

    const dropOpen = () => {
        ACT.open -= 1

        if (ACT.open <= 0) {
            ACT.open = 0

            if (ACT.holder !== null && $.host.clearInterval !== null) {
                $.host.clearInterval(ACT.holder)
                ACT.holder = null
            }
        }
    }

    // What `postMessage` is handed. A byte buffer being moved rides the transfer list, which is
    // what `transfer` maps onto exactly.
    const sendTo = (port, m, moves) => {
        if (moves !== undefined && moves.length > 0) port.postMessage(m, moves)
        else port.postMessage(m)
    }

    // **Every message from a worker goes to the main thread and is routed there**, which is the
    // relay this file's header pins as a limitation.
    const post = (m, moves) => {
        if (ME.id !== null) {
            if (ACT.port !== null) sendTo(ACT.port, m, moves)

            return
        }

        route(m, moves)
    }

    // The main thread's router.
    const route = (m, moves) => {
        // **What is in flight is recorded here and nowhere else**, because the main thread is the
        // one side that sees every worker-to-worker ask: a worker's own wait table cannot learn
        // that the actor it asked has died, so the death broadcast is written from this record.
        if (m.k === "call" && m.ticket !== null && m.from !== "") ACT.relayed.set(m.ticket, m)
        if (m.k === "reply") ACT.relayed.delete(m.ticket)

        if (m.to === "") { arrived(m); return }

        const kid = ACT.kids.get(m.to)

        if (kid !== undefined && !kid.dead && kid.worker !== null) { sendTo(kid.worker, m, moves); return }

        const waiting = ACT.queued.get(m.to)

        if (waiting !== undefined) { waiting.push([m, moves]); return }

        undeliverable(m)
    }

    // A message for an actor that is not there. **A `send` is dropped and an `ask` is rejected**,
    // which is the design's rule about a dead actor's handle word for word.
    const undeliverable = (m) => {
        if (m.k === "call" && m.ticket !== null)
            route({ k: "reply", to: m.from, ticket: m.ticket, ok: false,
                why: "the actor is not running", file: "", line: 0 })

        if (m.k === "call") route({ k: "ack", to: m.from, of: m.to })
    }

    // -- what arrives ------------------------------------------------------------------------------

    const arrived = (m) => {
        // **Held while this worker's modules are loading**, and delivered in order once it is
        // serving. Only the two a worker itself answers are queued: a reply or an ack belongs to
        // something this side already started and can be settled at once.
        if (ACT.loading && (m.k === "call" || m.k === "stop")) { ACT.held.push(m); return }

        if (m.k === "reply") { settle(m); return }
        if (m.k === "ack") { acked(m.of); return }
        if (m.k === "call") { serveCall(m); return }
        if (m.k === "stop") { asked_to_stop(); return }

        // The rest are the main thread's business and never a worker's.
        if (ME.id !== null) return

        // **The actor these three are ABOUT travels in `target`**, `to` being what the router
        // reads and these being the main thread's own business whoever asked.
        if (m.k === "spawn") { makeWorker(m.id, m.name, m.args, m.how); return }
        if (m.k === "detach") { detachKid(m.target); return }
        if (m.k === "ask-stop") { stopKid(m.target); return }
        if (m.k === "watch") { watchKid(m.target, m.from, m.ticket); return }
    }

    const acked = (of) => {
        const n = ACT.outbox.get(of)

        if (n !== undefined && n > 0) ACT.outbox.set(of, n - 1)
    }

    const settle = (m) => {
        const held = ACT.waits.get(m.ticket)

        if (held === undefined) return

        ACT.waits.delete(m.ticket)
        dropOpen()

        if (m.ok) held.answer(m.value === undefined ? null : decodeAll([m.value])[0])
        else held.refuse(faultFrom(m.why, m.file, m.line))
    }

    // A fault rebuilt on this side, keeping the file and the line it was raised at on the other.
    const faultFrom = (why, file, line) => {
        const made = new $.Fault(why)

        if (file !== "") made.file = file
        if (line !== 0) made.line = line

        return made
    }

    const faultParts = (e) => {
        const held = $.caught(e)

        // **A VALUE fault has no `message`, `file` or `line` to read**, the object a `catch` is
        // handed being the program's own value. The sentence is what `said` answers either way,
        // and the place comes off the error the host is still holding.
        if (!(held instanceof $.SObj) || typeof held.getName("message") !== "string")
            return { why: $.said(e), file: e === null || typeof e !== "object" || typeof e.file !== "string" ? "" : e.file,
                line: e === null || typeof e !== "object" || typeof e.line !== "number" ? 0 : e.line }

        return { why: held.getName("message"), file: held.getName("file"),
            line: Number(held.getName("line")) }
    }

    // -- serving a call ----------------------------------------------------------------------------

    const isHandler = (inst, name) => {
        if (!(inst instanceof $.SObj)) return false

        const [held] = inst.lookup("(handlers)")

        if (!Array.isArray(held)) return false

        for (const n of held) if (n === name) return true

        return false
    }

    const replyTo = (m, ok, value, bad) => {
        if (m.ticket === null) return

        if (!ok) {
            post({ k: "reply", to: m.from, ticket: m.ticket, ok: false,
                why: bad.why, file: bad.file, line: bad.line })

            return
        }

        let written = null
        let moves = []

        try {
            const w = encodeAll([value])

            written = w.body[0]
            moves = w.moves
        } catch (e) {
            const parts = faultParts(e)

            post({ k: "reply", to: m.from, ticket: m.ticket, ok: false,
                why: parts.why, file: parts.file, line: parts.line })

            return
        }

        post({ k: "reply", to: m.from, ticket: m.ticket, ok: true, value: written }, moves)
    }

    const serveCall = (m) => {
        // **The program's own line of execution has no handlers**, so a call that reaches the main
        // thread is reported rather than ignored -- `take_call`'s sentence word for word.
        if (ME.id === null) {
            replyTo(m, false, null,
                { why: "this is the program's own line of execution, which declares no handlers", file: "", line: 0 })
            post({ k: "ack", to: m.from, of: "" })

            return
        }

        ACT.busy += 1

        let args = null

        try {
            args = decodeAll(m.args)
        } catch (e) {
            replyTo(m, false, null, faultParts(e))
            finishedOne(m)

            return
        }

        if (!isHandler(ACT.serving, m.name)) {
            replyTo(m, false, null, { why: "`" + m.name +
                "` is not a handler of this actor -- an actor answers the names it wrote `on` in front of",
                file: "", line: 0 })
            finishedOne(m)

            return
        }

        let answered = null

        try {
            answered = $.method(ACT.serving, m.name, args)
        } catch (e) {
            // **An actor that faults dies**, exactly as an unhandled fault stops a program. The
            // pending `ask` is rejected with the fault and so is every other one, by the death
            // the main thread broadcasts when this worker exits.
            const parts = faultParts(e)

            replyTo(m, false, null, parts)
            finishedOne(m)
            dieOf(parts)

            return
        }

        if (!(answered instanceof Promise)) {
            replyTo(m, true, answered, null)
            finishedOne(m)

            return
        }

        // **A promise a handler answered with rejects the ASK and does not kill the actor**, which
        // is `settle_actor_answers` rather than `take_call`: the fault was raised on a line the
        // handler had already returned from.
        answered.then(
            (v) => { replyTo(m, true, v, null); finishedOne(m) },
            (e) => { replyTo(m, false, null, faultParts(e)); finishedOne(m) })
    }

    const finishedOne = (m) => {
        ACT.busy -= 1

        post({ k: "ack", to: m.from, of: ME.id })

        runDown()
    }

    // -- the run-down ------------------------------------------------------------------------------

    const asked_to_stop = () => {
        ACT.stopping = true

        runDown()
    }

    // **`stop` is orderly**: the actor takes no new messages, finishes the ones it has, and closes
    // its port -- after which the worker's own loop runs down and it exits. An actor holding a
    // timer holds the program open, which is the interpreter's answer to the same question.
    const runDown = () => {
        if (!ACT.stopping || ACT.busy > 0) return
        if (ACT.port === null) return

        const going = ACT.port

        ACT.port = null

        // **The keeper goes with the port**, or an actor stopped while it was itself waiting on
        // an ask would hold its own thread open for ever on a promise nothing can settle.
        if (ACT.holder !== null && $.host.clearInterval !== null) {
            $.host.clearInterval(ACT.holder)
            ACT.holder = null
            ACT.open = 0
        }

        try {
            going.close()
        } catch (e) {
            // A port a host has already taken away needs no closing.
        }
    }

    const dieOf = (parts) => {
        post({ k: "died", to: "", from: ME.id, why: parts.why, file: parts.file, line: parts.line })

        ACT.stopping = true

        runDown()
    }

    // -- the main thread's side of a worker ----------------------------------------------------------

    const mintId = () => {
        ACT.minted += 1

        return ME.id === null ? "a" + ACT.minted : ME.id + "/" + ACT.minted
    }

    const makeWorker = (id, name, args, how) => {
        watchExit()

        if (WT === null) {
            if (typeof Worker !== "function") { pretendDied(id, "this JavaScript host has no workers"); return }

            makePageWorker(id, name, args, how)

            return
        }

        if (SCRIPT_PATH === null) {
            pretendDied(id, "this program was not read from a file, so there is nothing for a worker to run")

            return
        }

        const options = { workerData: { $slateActor: { id: id, name: name, args: args } } }

        // **`heap` is node's `maxOldGenerationSizeMb`**, which is the nearest thing a JavaScript
        // host has to the interpreter's per-actor heap ceiling. A page has no such knob at all.
        if (how.heap > 0)
            options.resourceLimits = { maxOldGenerationSizeMb: Math.max(16, Math.ceil(how.heap / 1048576)) }

        if (how.name !== null) options.name = how.name

        let w = null

        try {
            w = new WT.Worker(SCRIPT_PATH, options)
        } catch (e) {
            pretendDied(id, String(e && e.message ? e.message : e))

            return
        }

        adopt(id, w, how)
    }

    // A page's worker, which is the same bundle reached as a URL where the script had one and as
    // its own text through a blob where it was written inline.
    const makePageWorker = (id, name, args, how) => {
        if (PAGE_SCRIPT === null) {
            pretendDied(id, "this page's script cannot be found, so there is nothing for a worker to run")

            return
        }

        let w = null

        try {
            const from = PAGE_SCRIPT.url !== null ? PAGE_SCRIPT.url
                : URL.createObjectURL(new Blob([PAGE_SCRIPT.text], { type: "text/javascript" }))

            w = new Worker(from)
        } catch (e) {
            pretendDied(id, String(e && e.message ? e.message : e))

            return
        }

        w.onmessage = (ev) => fromWorker(id, ev.data)
        w.onerror = (ev) => pretendDied(id, String(ev && ev.message ? ev.message : ev))

        ACT.kids.set(id, { worker: w, detached: false, dead: false, asked: false, fault: null, page: true })
        w.postMessage({ k: "start", id: id, name: name, args: args })
        flushQueued(id)
    }

    const adopt = (id, w, how) => {
        const kid = { worker: w, detached: false, dead: false, asked: false, fault: null, page: false }

        ACT.kids.set(id, kid)

        w.on("message", (m) => fromWorker(id, m))
        w.on("error", (e) => { kid.fault = { why: String(e && e.message ? e.message : e), file: "", line: 0 } })
        w.on("exit", () => kidExited(id))

        // **Unref'd from the start, and AFTER the listeners**, so an actor nobody is waiting for
        // does not hold the program open -- `keepOpen` is what holds it while an `ask` or a
        // `done` is outstanding.
        //
        // **THE ORDER IS THE WHOLE OF IT AND NOTHING SAYS SO.** Attaching a `message` listener
        // refs the worker's port, which is a second handle beside the thread; unref'd before the
        // listener, the port is ref'd again the moment one is added and `beforeExit` never fires
        // -- so the program prints its answer and then waits for ever, with nothing named.
        w.unref()

        flushQueued(id)
    }

    const flushQueued = (id) => {
        const waiting = ACT.queued.get(id)

        if (waiting === undefined) return

        ACT.queued.delete(id)

        for (const [m, moves] of waiting) route(m, moves)
    }

    // An actor whose worker could never be made. **It is reported as the actor having DIED rather
    // than as a fault where `spawn` was written**, because a worker spawning an actor mints the id
    // and carries on -- so there is no call left to refuse by the time this is known.
    const pretendDied = (id, why) => {
        ACT.kids.set(id, { worker: null, detached: false, dead: false, asked: true,
            fault: { why: why, file: "", line: 0 }, page: false })

        kidExited(id)
    }

    const fromWorker = (src, m) => {
        if (m.k === "died") {
            const kid = ACT.kids.get(src)

            if (kid !== undefined) kid.fault = { why: m.why, file: m.file, line: m.line }

            return
        }

        // **A message for somebody else is ROUTED and not handled**, which is the whole of the
        // relay: everything a worker posts arrives here, and what it says it is for decides.
        if (m.to === "") arrived(m)
        else route(m)
    }

    const kidExited = (id) => {
        const kid = ACT.kids.get(id)

        if (kid === undefined || kid.dead) return

        kid.dead = true

        const bad = kid.fault

        // **Every pending `ask` rejects with the fault and `done` settles with it**, all at once,
        // which is the design's list read straight down.
        for (const [ticket, held] of Array.from(ACT.waits)) {
            if (held.target !== id) continue

            ACT.waits.delete(ticket)
            dropOpen()

            if (held.kind === "done") {
                if (bad === null) held.answer(null)
                else held.refuse(faultFrom(bad.why, bad.file, bad.line))
            } else if (bad === null) {
                held.refuse(faultFrom("the actor stopped before it answered this", "", 0))
            } else {
                held.refuse(faultFrom(bad.why, bad.file, bad.line))
            }
        }

        // The same broadcast for an ask one worker made of another, which no worker's own wait
        // table could have noticed.
        for (const [ticket, m] of Array.from(ACT.relayed)) {
            if (m.to !== id && m.from !== id) continue

            ACT.relayed.delete(ticket)

            if (m.from === id) continue

            route(bad === null
                ? { k: "reply", to: m.from, ticket: ticket, ok: false,
                    why: "the actor stopped before it answered this", file: "", line: 0 }
                : { k: "reply", to: m.from, ticket: ticket, ok: false,
                    why: bad.why, file: bad.file, line: bad.line })
        }

        const watching = ACT.watchers.get(id)

        if (watching !== undefined) {
            ACT.watchers.delete(id)

            for (const [who, ticket] of watching)
                route(bad === null
                    ? { k: "reply", to: who, ticket: ticket, ok: true, value: null }
                    : { k: "reply", to: who, ticket: ticket, ok: false, why: bad.why, file: bad.file, line: bad.line })
        }

        const waiting = ACT.queued.get(id)

        if (waiting !== undefined) {
            ACT.queued.delete(id)

            for (const [m] of waiting) undeliverable(m)
        }
    }

    const detachKid = (id) => {
        const kid = ACT.kids.get(id)

        if (kid === undefined || kid.dead || kid.page) return

        kid.detached = true
        kid.worker.unref()
    }

    const stopKid = (id) => {
        const kid = ACT.kids.get(id)

        if (kid === undefined || kid.dead) return

        kid.asked = true
        sendTo(kid.worker, { k: "stop", to: id })
    }

    const watchKid = (id, who, ticket) => {
        const kid = ACT.kids.get(id)

        // **An actor nobody can find has stopped**, and a `done` about one settles at once rather
        // than waiting for a broadcast that has already been made.
        if (kid === undefined || kid.dead) {
            const bad = kid === undefined ? null : kid.fault

            route(bad === null
                ? { k: "reply", to: who, ticket: ticket, ok: true, value: null }
                : { k: "reply", to: who, ticket: ticket, ok: false, why: bad.why, file: bad.file, line: bad.line })

            return
        }

        const held = ACT.watchers.get(id)

        if (held === undefined) ACT.watchers.set(id, [[who, ticket]])
        else held.push([who, ticket])
    }

    // -- the end of the program ---------------------------------------------------------------------

    // **The program ends when its own loop has drained and every actor it spawned has stopped**,
    // which node says in one word: `beforeExit` fires when there is nothing left to do. A drained
    // program has nothing further to say to an actor, so each non-detached one is asked to stop --
    // orderly, which is what makes a `send` written on the last line still served -- and ref'd so
    // that this thread waits for it. The next `beforeExit` has nothing left to ask and the process
    // ends.
    const finishActors = () => {
        for (const [id, kid] of ACT.kids) {
            if (kid.dead || kid.asked || kid.detached || kid.worker === null) continue

            kid.asked = true
            kid.worker.ref()
            sendTo(kid.worker, { k: "stop", to: id })
        }
    }

    // **Registered when the first actor is spawned and not before**, so a program that declares
    // one and never starts one adds nothing to the host's exit path.
    let watchingExit = false

    const watchExit = () => {
        if (watchingExit) return
        if ($.inWorker || typeof process === "undefined" || typeof process.on !== "function") return

        watchingExit = true
        process.on("beforeExit", () => finishActors())
    }

    // **A suite is one process, so an actor left running is a thread of the next test's** --
    // `forget_actors` in `reset_events`, said where the runner can call it.
    $.actorReset = () => {
        for (const [, kid] of ACT.kids) {
            if (kid.worker === null || kid.dead) continue

            try {
                kid.worker.terminate()
            } catch (e) {
                // A worker the host has already taken away needs no terminating.
            }
        }

        for (const [ticket, held] of Array.from(ACT.waits)) {
            ACT.waits.delete(ticket)
            dropOpen()
            held.refuse(faultFrom("the actor is not running", "", 0))
        }

        ACT.kids.clear()
        ACT.queued.clear()
        ACT.watchers.clear()
        ACT.outbox.clear()
        ACT.limits.clear()
    }

    // -- the worker's own entry ----------------------------------------------------------------------

    // **What the emitted bundle calls instead of running the program, when it is a worker.** The
    // declarations are run first -- every name the program declares and not one line of what it
    // does -- and then this side serves messages.
    // Which module's top level is running while a worker loads, and `""` at every other moment.
    // **The emitted declarations copy is what sets it**, one line either side of each module, so
    // the refusal `spawn` raises can name the file the reader has to look at.
    let LOADING_MODULE = ""

    $.loadingModule = (name) => { LOADING_MODULE = name }

    $.actorWorker = (load) => {
        if (NODE_START !== null) {
            ME.id = NODE_START.id
            ACT.port = WT.parentPort

            WT.parentPort.on("message", (m) => arrived(m))
            startServing(load, NODE_START.name, NODE_START.args)

            return
        }

        // A page hands nothing over at construction, so the start payload is the first message.
        ACT.port = self

        self.onmessage = (ev) => {
            const m = ev.data

            if (m.k === "start" && ME.id === null) {
                ME.id = m.id
                startServing(load, m.name, m.args)

                return
            }

            arrived(m)
        }
    }

    // **The loader is AWAITED, because a module may wait at its own top level.** A worker runs
    // every module the program imports in full, so `await` is legal there and the emitted loader
    // is an `async` function; awaiting a loader that finished synchronously costs a microtask.
    //
    // **Anything that arrives while it loads is HELD.** Without the wait there was no window at
    // all; with it, a call could reach a worker whose declaration has not been made yet, so the
    // two kinds of message a worker serves are queued and delivered in order once it is serving.
    const startServing = async (load, name, args) => {
        try {
            ACT.loading = true

            await load()

            const cls = declaredHere(name)

            if (cls === undefined)
                fault("`" + name + "` is not an actor this program declares")

            ACT.serving = instantiate(cls, name, decodeAll(args))
            ACT.loading = false

            while (ACT.held.length > 0) arrived(ACT.held.shift())
        } catch (e) {
            ACT.loading = false
            ACT.held.length = 0
            dieOf(faultParts(e))
        }
    }

    // **A declaration with no fields has no constructor at all**, which is `make_constructor`'s own
    // rule: the instance is then the object every instance is, its declaration as its `proto` and
    // nothing of its own.
    const instantiate = (cls, name, args) => {
        const [maker] = cls.lookup("new")

        if (typeof maker === "function") return $.call(maker, args)

        if (args.length !== 0)
            fault("`" + name + "` declares no state, so `spawn` takes no arguments for it and was given " +
                actorCounted(args.length))

        const made = new $.SObj()

        made.setName("proto", cls)

        return made
    }

    // -- the eight names ------------------------------------------------------------------------------

    const actorCounted = (n) => n + (n === 1 ? " argument" : " arguments")

    // Where a message is going and what it is called. **Both spellings, because a message is a
    // value and a handle is one too**: `send(c.bump, 2)` reads the handler off the handle and
    // `send(c, "bump", 2)` names it as text.
    const addressed = (args, name) => {
        if (args.length === 0)
            fault("`" + name + "` takes a message or an actor and a handler name, and was given nothing")

        const first = args[0]

        if (first instanceof $.SMessage)
            return { id: first.id, name: first.name, args: args.slice(1) }

        if (first instanceof $.SActor) {
            if (args.length < 2)
                fault("`" + name + "` takes an actor and the name of a handler -- `" + name +
                    "(a, \"total\")`, or `" + name + "(a.total)`")

            if (!$.isStr(args[1]))
                fault("`" + name + "` takes a handler's name as text, and this is " + $.typeName(args[1]))

            return { id: first.id, name: args[1], args: args.slice(2) }
        }

        fault("`" + name + "` takes a message or an actor, and this is " + $.typeName(first))
    }

    const handleOf = (v, name) => {
        if (v instanceof $.SActor) return v.id

        fault("`" + name + "` takes an actor, and this is " + $.typeName(v))
    }

    const positive = (v, what) => {
        if (!$.isInt(v)) fault(what + " is a whole number, and this is " + $.typeName(v))
        if (v <= 0n) fault(what + " is a positive whole number, and this is " + v)

        return Number(v)
    }

    const spawnOptions = (v) => {
        const how = { heap: DEFAULT_HEAP, mailbox: DEFAULT_MAILBOX, name: null }

        if (!(v instanceof $.SObj))
            fault("`spawn`'s options are an object, and this is " + $.typeName(v))

        for (const [k, held] of v.entries()) {
            if (!$.isStr(k)) fault("an option is named, and this is " + $.typeName(k))

            if (k === "heap") how.heap = positive(held, "`heap`")
            else if (k === "mailbox") how.mailbox = positive(held, "`mailbox`")
            else if (k === "name") how.name = $.isStr(held) ? held : null
            else fault("`spawn` has no option called `" + k + "` -- it takes `heap`, `mailbox` and `name`")
        }

        return how
    }

    // The most arguments a declaration's constructor takes, which is what makes
    // `spawn(A, args..., options)` unambiguous.
    const makerArity = (cls) => {
        const [maker] = cls.lookup("new")

        if (typeof maker !== "function" || maker.$p === undefined) return 0

        const params = maker.$p

        if (params.length > 0 && params[params.length - 1].startsWith("...")) return Infinity

        return params.length
    }

    B.actorSpawn = (...args) => {
        // **A `spawn` while this worker is loading its modules would never stop.** A worker runs
        // every module the program imports, so a module that spawns at its own top level starts
        // an actor whose worker runs that module, which spawns again. The interpreter refuses it
        // in these words too.
        if (LOADING_MODULE !== "")
            fault("`spawn` cannot be called while `" + LOADING_MODULE + "` is being loaded -- an " +
                "actor's VM runs every module the program imports, so an actor started from a " +
                "module's top level would start another for ever. Spawn from a definition the " +
                "program calls instead.")

        if (args.length === 0)
            fault("`spawn` takes an actor declaration and its constructor's arguments, and was given nothing")

        const cls = args[0]

        if (!(cls instanceof $.SObj))
            fault("`spawn` takes an actor declaration, and this is " + $.typeName(cls))

        const name = $.classOwnName(cls)

        if (name === null)
            fault("`spawn` takes an `actor` declaration, and this object is not one")

        if (!cls.hasName("(actor)"))
            fault("`spawn` takes an `actor` declaration, and `" + name + "` is a class -- an actor is " +
                "declared with `actor`, which is what gives it handlers another thread can reach")

        if (WT === null && typeof Worker !== "function") noWorkers("spawn")

        const given = args.length - 1
        const takes = makerArity(cls)

        let how = { heap: DEFAULT_HEAP, mailbox: DEFAULT_MAILBOX, name: null }
        let upto = args.length

        if (given === takes + 1) {
            how = spawnOptions(args[args.length - 1])
            upto = args.length - 1
        } else if (given > takes + 1) {
            fault("`" + name + "` takes " + actorCounted(takes) + " and `spawn` was given " + given)
        }

        const written = encodeAll(args.slice(1, upto))
        const id = mintId()

        ACT.limits.set(id, how.mailbox)
        ACT.outbox.set(id, 0)

        if (ME.id === null) makeWorker(id, name, written.body, how)
        else {
            ACT.queued.set(id, [])
            post({ k: "spawn", to: "", id: id, name: name, args: written.body, how: how }, written.moves)
        }

        return $.actorHandle(id)
    }

    // How many messages this side has posted to an actor and not seen acknowledged.
    const room = (id, name, what) => {
        const limit = ACT.limits.get(id)

        if (limit === undefined) return

        const held = ACT.outbox.get(id)
        const n = held === undefined ? 0 : held

        if (n < limit) { ACT.outbox.set(id, n + 1); return }

        fault("`" + what + "` was sent to an actor whose mailbox is full -- a full mailbox is a " +
            "refusal rather than a wait, so either the receiver is too slow or its `mailbox` limit is too low")
    }

    B.actorSend = (...args) => {
        const to = addressed(args, "send")
        const written = encodeAll(to.args)

        room(to.id, "send", to.name)

        post({ k: "call", to: to.id, from: ME.id === null ? "" : ME.id, name: to.name,
            args: written.body, ticket: null }, written.moves)

        return null
    }

    const waiting = (target, kind) => {
        ACT.ticket += 1

        const ticket = (ME.id === null ? "" : ME.id) + "#" + ACT.ticket

        keepOpen()

        const made = new Promise((answer, refuse) =>
            ACT.waits.set(ticket, { answer: answer, refuse: refuse, kind: kind, target: target }))

        return { ticket: ticket, promised: made }
    }

    B.actorAsk = (...args) => {
        const to = addressed(args, "ask")
        const written = encodeAll(to.args)
        const held = waiting(to.id, "ask")

        const limit = ACT.limits.get(to.id)
        const n = ACT.outbox.get(to.id)

        if (limit !== undefined && n !== undefined && n >= limit) {
            settle({ ticket: held.ticket, ok: false, why: "this actor's mailbox is full", file: "", line: 0 })

            return held.promised
        }

        if (limit !== undefined) ACT.outbox.set(to.id, (n === undefined ? 0 : n) + 1)

        post({ k: "call", to: to.id, from: ME.id === null ? "" : ME.id, name: to.name,
            args: written.body, ticket: held.ticket }, written.moves)

        return held.promised
    }

    B.actorDone = (...args) => {
        if (args.length !== 1)
            fault("`done` takes an actor, and was given " + actorCounted(args.length))

        const id = handleOf(args[0], "done")
        const held = waiting(id, "done")

        post({ k: "watch", to: "", from: ME.id === null ? "" : ME.id, target: id, ticket: held.ticket })

        // The router reads `to` and a watch is the main thread's own business, so the actor being
        // asked about travels in `target` and is put back here.
        return held.promised
    }

    B.actorStop = (...args) => {
        if (args.length !== 1)
            fault("`stop` takes an actor, and was given " + actorCounted(args.length))

        const id = handleOf(args[0], "stop")

        if (ME.id === null) stopKid(id)
        else post({ k: "ask-stop", to: "", target: id })

        return null
    }

    B.actorDetach = (...args) => {
        if (args.length !== 1)
            fault("`detach` takes an actor, and was given " + actorCounted(args.length))

        const id = handleOf(args[0], "detach")

        if (ME.id === null) detachKid(id)
        else post({ k: "detach", to: "", target: id })

        return null
    }

    B.actorMe = (...args) => {
        if (args.length !== 0)
            fault("`me` takes nothing, and was given " + actorCounted(args.length))

        if (ME.id === null)
            fault("`me()` is an actor's own handle and is answered inside a handler -- the program's " +
                "own line of execution has no handle, being the one nobody spawned")

        return $.actorHandle(ME.id)
    }

    B.actorTransfer = (...args) => {
        if (args.length !== 1)
            fault("`transfer` takes bytes, and was given " + actorCounted(args.length))

        if (!(args[0] instanceof $.SBytes))
            fault("`transfer` takes bytes, and this is " + $.typeName(args[0]) +
                " -- a buffer is the one container whose storage can move between heaps whole")

        const held = new $.SObj()

        held.setName("(transfer)", args[0])

        return held
    }


        // -- sqlite ------------------------------------------------------------------------------------

        // node's own SQLite, or nothing where there is none.
        //
        // **`require` rather than a global, because there is no global to read**, and the two
        // conditions are asked separately so that a host with `process` and no module loader answers
        // the same *no* rather than throwing.
        //
        // **ASKED AT THE FIRST CALL AND NOT WHEN THE RUNTIME LOADS, WHICH IS NOT A TIDINESS
        // DECISION.** `node:sqlite` is still marked experimental, so requiring it prints
        // `ExperimentalWarning: SQLite is an experimental feature` on **stderr** -- and an eager
        // require puts that line in front of every program this back end emits, whether or not it has
        // ever heard of a database. Four tests that compare what node wrote went red on it, none of
        // them about SQLite. So the module is fetched once, at the first call that needs it, and a
        // program that does not open a database never mentions it.
        let sqliteMod = undefined

        const sqliteHost = () => {
            if (sqliteMod !== undefined) return sqliteMod

            sqliteMod = null

            const load = $.host.require

            if (typeof process === "undefined" || typeof load !== "function") return null

            try {
                const mod = load("node:sqlite")

                if (typeof mod.DatabaseSync === "function") sqliteMod = mod
            } catch (e) {
                sqliteMod = null
            }

            return sqliteMod
        }

        const noSqlite = (name) =>
            fault("`" + name + "` is SQLite, which this JavaScript host has not got -- node has " +
                "carried `node:sqlite` since 22.5, and a browser has no database of this kind at all")

        // One slot per connection and one per statement, which is the interpreter's arrangement word
        // for word: a handle is an integer into a table on this side, so nothing of node's ever
        // becomes a slate value.
        const sqliteDbs = []
        const sqliteStmts = []

        const sqliteDbOf = (v, name) => {
            if (!$.isInt(v)) fault("`" + name + "` takes a database, and this is " + typeName(v))

            const held = sqliteDbs[Number(v)]

            if (held === undefined || held === null) fault("this database is closed")

            return held
        }

        const sqliteStmtOf = (v, name) => {
            if (!$.isInt(v)) fault("`" + name + "` takes a database, and this is " + typeName(v))

            const held = sqliteStmts[Number(v)]

            if (held === undefined || held === null) fault("this database is closed")

            return held
        }

        // How many parameters this SQL takes. See the header: node has no door to the count, and
        // without one the two back ends disagree about a `?` nobody bound.
        const sqliteWants = (sql) => {
            const named = new Map()
            let i = 0
            let next = 1
            let most = 0

            const quoted = (end) => {
                i += 1

                while (i < sql.length) {
                    if (sql[i] === end) {
                        // **A doubled quote is the quote itself**, which is SQL's only escape.
                        if (sql[i + 1] === end) i += 2
                        else {
                            i += 1

                            return
                        }
                    } else i += 1
                }
            }

            while (i < sql.length) {
                const c = sql[i]

                if (c === "'" || c === '"' || c === "`") quoted(c)
                else if (c === "[") quoted("]")
                else if (c === "-" && sql[i + 1] === "-") {
                    while (i < sql.length && sql[i] !== "\n") i += 1
                } else if (c === "/" && sql[i + 1] === "*") {
                    i += 2

                    while (i < sql.length && !(sql[i] === "*" && sql[i + 1] === "/")) i += 1

                    i += 2
                } else if (c === "?") {
                    i += 1

                    let digits = ""

                    while (i < sql.length && sql[i] >= "0" && sql[i] <= "9") {
                        digits += sql[i]
                        i += 1
                    }

                    const at = digits === "" ? next : Number(digits)

                    if (at >= next) next = at + 1
                    if (at > most) most = at
                } else if (c === ":" || c === "@" || c === "$") {
                    let j = i + 1

                    while (j < sql.length && /[A-Za-z0-9_]/.test(sql[j])) j += 1

                    if (j === i + 1) {
                        i += 1

                        continue
                    }

                    const key = sql.slice(i, j)

                    i = j

                    // **A name used twice is ONE parameter**, which is the whole reason a named one
                    // is worth having.
                    if (named.has(key)) continue

                    named.set(key, next)

                    if (next > most) most = next

                    next += 1
                } else i += 1
            }

            return most
        }

        // What a parameter binds as. **An array is a BLOB and there is nothing to choose**, SQLite
        // having one kind of bytes where PostgreSQL has `int[]` and `bytea` both.
        const sqliteParam = (v) => {
            if (v === null) return null
            if ($.isInt(v) || $.isReal(v) || $.isStr(v)) return v

            // **A boolean is 0 or 1**, which is what the column would have held anyway: SQLite has no
            // boolean storage class and `true` in SQL is the integer 1.
            if (typeof v === "boolean") return v ? 1n : 0n

            // A buffer is a BLOB, which is the one kind of bytes SQLite has.
            if (v instanceof $.SBytes) return Buffer.from(v.view())

            if (Array.isArray(v)) {
                const bytes = []

                for (const b of v) {
                    if (!$.isInt(b))
                        fault("`a parameter` takes an array of numbers, and one of these is " + typeName(b))

                    const n = Number(b)

                    if (n < 0 || n > 255) fault("a byte is between 0 and 255, and this is " + n)

                    bytes.push(n)
                }

                return new Uint8Array(bytes)
            }

            fault("a parameter is text, a number, a boolean, bytes or null, and this is " + typeName(v))
        }

        // One cell of a row. **`setReadBigInts` is what makes the five storage classes tell
        // themselves apart here**: without it node answers a JavaScript number for an INTEGER as well
        // as for a REAL, and slate's two number types would be one.
        const sqliteCell = (v) => {
            if (v === null || typeof v === "bigint" || typeof v === "number" || typeof v === "string")
                return v

            // **A BLOB comes back as a BUFFER**, which is the interpreter's answer: a row holding a
            // hundred kilobytes of image cost a megabyte and a half of heap as an array of numbers.
            return $.bytesOf(v instanceof Uint8Array ? v : Uint8Array.from(v))
        }

        const sqliteBound = (stmt, args, name) => {
            const params = args[1]

            if (!Array.isArray(params))
                fault("`" + name + "` takes the parameters as an array, and this is " + typeName(params))

            if (stmt.wants !== params.length)
                fault("this SQL takes " + stmt.wants + (stmt.wants === 1 ? " parameter" : " parameters") +
                    " and was given " + params.length)

            return params.map(sqliteParam)
        }

        // What node objected to, said the way the interpreter says it. **Both are quoting SQLite's own
        // message** -- `no such table: notes` reaches the person who wrote the table name either way --
        // so this is a prefix rather than a translation.
        const sqliteWhy = (e) =>
            "the database refused this SQL: " + String(e && e.message ? e.message : e)

        B.sqliteOpen = (...args) => {
            if (args.length < 1 || args.length > 2)
                fault("`sqlite` takes a path and an optional object of options, and was given " +
                    args.length + (args.length === 1 ? " argument" : " arguments"))

            const host = sqliteHost()

            if (host === null) noSqlite("sqlite")

            if (!$.isStr(args[0]))
                fault("`sqlite` takes the path as text, and this is " + typeName(args[0]))

            const options = args.length === 2 ? args[1] : null
            let readOnly = false
            let wait = 0n

            if (options !== null) {
                if (!(options instanceof $.SObj))
                    fault("`sqlite` takes an object of options, and this is " + typeName(options))

                for (const [k, v] of options.entries()) {
                    if (k !== "readOnly" && k !== "busyTimeout")
                        fault("`" + k + "` is not one of a database's options -- there are two, " +
                            "`readOnly` and `busyTimeout`")
                }

                if (options.hasName("readOnly")) {
                    readOnly = options.getName("readOnly")

                    if (typeof readOnly !== "boolean")
                        fault("`readOnly` is true or false, and this is " + typeName(readOnly))
                }

                if (options.hasName("busyTimeout")) {
                    wait = options.getName("busyTimeout")

                    if (!$.isInt(wait))
                        fault("`busyTimeout` is a whole number of milliseconds, and this is " + typeName(wait))

                    if (wait < 0n) fault("`busyTimeout` is a number of milliseconds, and this is " + wait)
                }
            }

            let db = null

            try {
                db = new host.DatabaseSync(args[0], { readOnly: readOnly })
            } catch (e) {
                fault("`" + args[0] + "` could not be opened: " + String(e && e.message ? e.message : e))
            }

            // **The busy timeout is a PRAGMA here and `sqlite3_busy_timeout` there**, which is the
            // same setting: SQLite implements the pragma by making that call.
            if (wait > 0n) {
                try {
                    db.exec("PRAGMA busy_timeout = " + wait)
                } catch (e) {
                    fault("`" + args[0] + "` would not take a busy timeout: " +
                        String(e && e.message ? e.message : e))
                }
            }

            sqliteDbs.push(db)

            return BigInt(sqliteDbs.length - 1)
        }

        B.sqliteClose = (...args) => {
            if (args.length !== 1)
                fault("`sqliteClose` takes a database, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            const at = Number(args[0])
            const held = sqliteDbs[at]

            if (held !== undefined && held !== null) {
                sqliteDbs[at] = null

                try {
                    held.close()
                } catch (e) {
                    // A connection already shut by the host is one this had nothing left to do about.
                }
            }

            return null
        }

        B.sqliteExec = (...args) => {
            if (args.length !== 2)
                fault("`sqliteExec` takes a database and some SQL, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            const db = sqliteDbOf(args[0], "sqliteExec")

            if (!$.isStr(args[1]))
                fault("`exec` takes the SQL as text, and this is " + typeName(args[1]))

            try {
                db.exec(args[1])
            } catch (e) {
                fault(sqliteWhy(e))
            }

            return null
        }

        B.sqlitePrepare = (...args) => {
            if (args.length !== 2)
                fault("`sqlitePrepare` takes a database and some SQL, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            const db = sqliteDbOf(args[0], "sqlitePrepare")

            if (!$.isStr(args[1]))
                fault("this takes the SQL as text, and this is " + typeName(args[1]))

            let stmt = null

            try {
                stmt = db.prepare(args[1])
            } catch (e) {
                fault(sqliteWhy(e))
            }

            stmt.setReadBigInts(true)
            sqliteStmts.push({ stmt: stmt, db: db, wants: sqliteWants(args[1]) })

            return BigInt(sqliteStmts.length - 1)
        }

        B.sqliteFinalize = (...args) => {
            if (args.length !== 1)
                fault("`sqliteFinalize` takes a statement, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            const at = Number(args[0])

            if (sqliteStmts[at] !== undefined) sqliteStmts[at] = null

            return null
        }

        B.sqliteQuery = (...args) => {
            if (args.length !== 2)
                fault("`sqliteQuery` takes a statement and its parameters, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            const held = sqliteStmtOf(args[0], "sqliteQuery")
            const params = sqliteBound(held, args, "sqliteQuery")

            let rows = null

            try {
                rows = held.stmt.all(...params)
            } catch (e) {
                fault(sqliteWhy(e))
            }

            return rows.map((row) => {
                const entries = []

                for (const name of Object.keys(row)) entries.push([name, sqliteCell(row[name])])

                return $.obj(entries)
            })
        }

        B.sqliteRun = (...args) => {
            if (args.length !== 2)
                fault("`sqliteRun` takes a statement and its parameters, and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))

            const held = sqliteStmtOf(args[0], "sqliteRun")
            const params = sqliteBound(held, args, "sqliteRun")

            let did = null

            try {
                did = held.stmt.run(...params)
            } catch (e) {
                fault(sqliteWhy(e))
            }

            const whole = (n) => typeof n === "bigint" ? n : BigInt(n)

            return $.obj([["changes", whole(did.changes)],
                ["lastInsertRowid", whole(did.lastInsertRowid)]])
        }

        // **A property of the machine's SQLite, asked of a connection**, because SQL is the only door
        // to it here -- `sqlite_compileoption_used` is the same C function the interpreter calls, so
        // the `SQLITE_` prefix is optional in both.
        B.sqliteCompiled = (...args) => {
            if (args.length !== 2)
                fault("`compiledWith` takes a database and the name of an option, and was given " +
                    args.length + (args.length === 1 ? " argument" : " arguments"))

            const db = sqliteDbOf(args[0], "sqliteCompiled")

            if (!$.isStr(args[1]))
                fault("`compiledWith` takes the name of an option as text, and this is " + typeName(args[1]))

            const asked = db.prepare("select sqlite_compileoption_used(?) as used")

            return asked.all(args[1])[0].used === 1
        }

    // -- the options object, read as `fetch_option` reads it ---------------------------------

    const fetchOptions = (v) => {
        if (v === null || v === undefined) return null

        if (!(v instanceof $.SObj))
            fault("`fetch` takes its options as an object, and this is " + typeName(v))

        return v
    }

    // **`lookup` rather than `$.field`**, which is `field_from`'s own reading: what is wanted is
    // the field the program wrote or inherited, and not the builtin method of that name that a
    // field access would fall back to.
    const fetchText = (opts, key) => {
        if (opts === null) return ""

        const v = opts.lookup(key)[0]

        if (v === undefined) return ""
        if (!$.isStr(v)) fault("`" + key + "` is a string, and this is " + typeName(v))

        return v
    }

    const fetchHeaders = (opts) => {
        const out = []

        if (opts === null) return out

        const v = opts.lookup("headers")[0]

        if (v === undefined) return out

        if (!(v instanceof $.SObj))
            fault("`headers` is an object of names and values, and this is " + typeName(v))

        for (const [k, held] of v.entries()) {
            if (typeof k !== "string")
                fault("a header is named by a string, and this is " + typeName(k))

            out.push([k, $.text(held)])
        }

        return out
    }

    // `fetch_flag`'s reading: true or false, and false where it is left out.
    const fetchFlag = (opts, key) => {
        if (opts === null) return false

        const v = opts.lookup(key)[0]

        if (v === undefined) return false
        if (typeof v !== "boolean") fault("`" + key + "` is true or false, and this is " + typeName(v))

        return v
    }

    // `fetch_timeout`'s reading: a duration or a whole number of milliseconds, zero for none,
    // and a negative one a fault.
    const fetchTimeout = (opts) => {
        if (opts === null) return 0n

        const v = opts.lookup("timeout")[0]

        if (v === undefined) return 0n

        let ms

        if ($.isInt(v)) ms = BigInt(v)
        else if (v instanceof SDuration) ms = BigInt(v.us) / 1000n
        else fault("`timeout` is a duration or a number of milliseconds, and this is " + typeName(v))

        if (ms < 0n) fault("`timeout` cannot be negative, and this is " + ms + " milliseconds")

        return ms
    }

    // **The host decodes a compressed body itself**, so all that is written here is the answer
    // for one that will not decode: a host's body read rejects with one `TypeError` however the
    // stream was damaged, and in one of these encodings that is `undecodable`'s sentence in
    // `client_options.sysl` rather than a failed connection.
    const fetchEncodings = ["gzip", "x-gzip", "deflate"]

    const fetchWhy = (e) =>
        String(e !== null && e !== undefined && e.message !== undefined ? e.message : e)

    // -- the url, read as `parse_url` reads it -----------------------------------------------

    // Whether a URL names no scheme, and is therefore a reference waiting for a base. RFC 3986's
    // rule, which is `relative_url`'s in `http.sysl` written as the pattern it is.
    const fetchRelative = (url) => !/^[A-Za-z][A-Za-z0-9+.-]*:/.test(url)

    // **A PAGE'S OWN ADDRESS IS THE BASE, WHICH IS WHY `fetch("/signup")` IS WHAT A BROWSER
    // PROGRAM WRITES.** The platform's `fetch` resolves a reference against `location`, and
    // refusing one here made the commonest call a page makes -- its own server, at its own
    // origin -- the one call `slate:fetch` would not make. The resolution is `new URL`'s and not
    // this runtime's: `/signup`, `./next`, `../up` and a bare path are one rule in the URL
    // specification and writing a second reading of it here would be a way to disagree with the
    // browser the program is running in.
    //
    // **Only a host with a `location` does this.** node has none and neither has the
    // interpreter, so a reference stays a refusal there and says what it is missing.
    const fetchBase = (url) => {
        if (!fetchRelative(url)) return url

        if (typeof location === "undefined" || location === null ||
                typeof location.href !== "string") return url

        try {
            return new URL(url, location.href).href
        } catch (e) {
            return url
        }
    }

    // **The two refusals `parse_url` has, in its words.** Everything else about a url is the
    // host's business: it has a parser, slate does not need a second one, and what a malformed
    // authority means is a question with one right answer per host anyway.
    const fetchUrlWrong = (url) => {
        const secure = url.startsWith("https://")

        if (!secure && !url.startsWith("http://"))
            return "`" + url + "` is not an http or https URL" +
                (fetchRelative(url) ? ", and there is no page to resolve it against" : "")

        const rest = url.slice(secure ? 8 : 7)
        const cut = rest.indexOf("/")

        if ((cut < 0 ? rest : rest.slice(0, cut)) === "")
            return "`" + url + "` names no host"

        return null
    }

    const fetchOk = (v) => $.obj([["ok", true], ["value", v]])
    const fetchBad = (message) => $.obj([["ok", false], ["error", message]])

    // What the server said, as the object `deliver_response` builds.
    //
    // **The body is decoded STRICTLY and a body that is not UTF-8 is empty**, which is
    // `from_utf8`'s answer in `client.sysl` and is why `text()` is not used: a host's `text()`
    // replaces every bad byte with U+FFFD, so a response of arbitrary bytes would come back as a
    // string of replacement characters here and as `""` there.
    // The headers as `header_lines_into` builds them.
    const fetchPairs = (r) => {
        const pairs = []

        // **`Set-Cookie` is skipped here and taken from `getSetCookie` below**, a `Headers`
        // object having joined it with the rest and joined it wrongly: a cookie carries commas
        // of its own, so the combined value cannot be taken apart again. `getSetCookie` exists
        // for exactly this and answers the lines.
        r.headers.forEach((v, k) => { if (k !== "set-cookie") pairs.push([k, v]) })

        // **In a browser this is empty and the field is absent, and that is the host's rule
        // rather than a gap here**: `Set-Cookie` is a forbidden response-header name, so a page
        // never sees one at all. The browser still applies the cookie; what it withholds is the
        // reading of it.
        const cookies = typeof r.headers.getSetCookie === "function" ? r.headers.getSetCookie() : []

        if (cookies.length > 0) pairs.push(["set-cookie", cookies])

        return $.obj(pairs)
    }

    const fetchAnswer = (r, fail) => r.arrayBuffer().then((bytes) => {
        let body = ""

        try {
            body = new TextDecoder("utf-8", { fatal: true }).decode(bytes)
        } catch (e) {
            body = ""
        }

        return fetchOk($.obj([["status", BigInt(r.status)], ["headers", fetchPairs(r)],
            ["body", body]]))
    }, (e) => {
        const coding = fetchCoding(r)

        if (fetchEncodings.includes(coding)) return fail(fetchUndecodable(coding))

        return fail("this connection failed: " + fetchWhy(e))
    })

    const fetchCoding = (r) => (r.headers.get("content-encoding") ?? "").trim().toLowerCase()

    const fetchUndecodable = (coding) => "the server said the body was compressed with " +
        (coding === "x-gzip" ? "gzip" : coding) + ", and it could not be decompressed"

    // `{ status, headers, body }` with the body a source, which is `body_head` and `body_object`
    // in `client_stream.sysl` -- read through the host's own `getReader()`.
    //
    // **The host decodes as it reads**, as the interpreter does with miniz's `Decoder` (`take_body`
    // in `client_stream.sysl`), so a compressed body arrives here as the bytes it stands for. One
    // place they part: a host answers a stream that stops short of its end with what it decoded,
    // where the interpreter says it could not be decompressed. A body that will not decode, a
    // connection that goes and a limit that runs out each reject the read with the host's own
    // error, so the sentence is chosen here from what is known -- `late()` says whether the limit
    // fired -- and is the interpreter's word for word.
    //
    // **`over` is called exactly once, however the body ends**, and is what clears the limit;
    // `abort` is what `dispose` adds to cancelling the reader, so the connection goes whichever of
    // the two a host listens to.
    const fetchStreamed = (r, url, over, late, abort) => {
        const coding = fetchCoding(r)
        const reader = r.body === null ? null : r.body.getReader()
        let finished = false
        let busy = false

        const step = (done, value) => $.obj([["done", done], ["value", value]])

        const end = () => {
            if (finished) return

            finished = true
            over()
        }

        const broke = () => {
            const t = late()

            if (t !== null) return t
            if (fetchEncodings.includes(coding)) return fetchUndecodable(coding)

            return url + " stopped sending in the middle of the body"
        }

        // An empty chunk is read past, there being nothing in it to hand over.
        const pull = () => reader.read().then((got) => {
            if (finished) return step(true, null)

            if (got.done) {
                end()
                return step(true, null)
            }

            if (got.value.length === 0) return pull()

            return step(false, $.bytesOf(got.value))
        }, (e) => {
            if (finished) return step(true, null)

            const why = broke()

            end()
            return step(false, fetchBad(why))
        })

        const next = () => {
            if (busy)
                fault("this streamed body is already working on a `next` -- await that promise " +
                    "before asking it for another value")

            if (finished || reader === null) {
                end()
                return Promise.resolve(step(true, null))
            }

            busy = true

            return pull().then((s) => {
                busy = false
                return s
            })
        }

        const dispose = () => {
            if (!finished) {
                end()

                if (reader !== null) reader.cancel().catch(() => null)

                abort()
            }

            return null
        }

        // **`return` is what a `for await` left early calls**, so a `break` closes the
        // connection with no `using` around the loop -- `do_body_return`'s rule.
        const finish = () => {
            dispose()
            return step(true, null)
        }

        const body = $.obj([["proto", $.obj([["next", next], ["dispose", dispose],
            ["close", dispose], ["return", finish]])]])

        return fetchOk($.obj([["status", BigInt(r.status)], ["headers", fetchPairs(r)],
            ["body", body]]))
    }

    // `fetch(url)` and `fetch(url, options)` -- a promise of what the server said.
    B.fetch = (...args) => {
        wantArgs(args.length, 1, 2, "fetch", "a URL and optionally some options")

        if (!$.isStr(args[0]))
            fault("`fetch` takes a URL, and this is " + typeName(args[0]))

        const url = fetchBase(args[0])
        const opts = fetchOptions(args.length === 2 ? args[1] : null)
        const method = fetchText(opts, "method")
        const body = fetchText(opts, "body")
        const heads = fetchHeaders(opts)
        const trust = fetchText(opts, "trust")
        const limit = fetchTimeout(opts)
        const stream = fetchFlag(opts, "stream")

        // **`reuse` is read for its type and then left to the host**, whose connections are its
        // own: no JavaScript host lets a request opt out of its pool, and node's refuses the
        // `Connection` header that would say so. Nothing is lost by it -- the option asks the
        // interpreter for a connection nobody else uses, which is a request about the transport,
        // never about the answer.
        fetchFlag(opts, "reuse")

        if ($.host.fetch === null)
            fault("`fetch` needs the host's own `fetch`, and this JavaScript host has none")

        // **A refusal rather than a quiet ignoring**, a program that believes it pinned a
        // certificate and did not being worse off than one told it cannot.
        if (trust !== "")
            fault("`trust` names a certificate to trust as well as the machine's own, and a " +
                "JavaScript host gives a program no way to add one -- what a host trusts is the " +
                "host's own store")

        const wrong = fetchUrlWrong(url)

        if (wrong !== null) return Promise.resolve(fetchBad(wrong))

        const init = { method: method === "" ? "GET" : method, headers: heads }

        if (body !== "") init.body = body

        // **A timeout is an `AbortController` and the engine's own timer, and not
        // `AbortSignal.timeout`**: that one's timer cannot be cancelled, and a host that keeps a
        // process alive for a pending timer would wait out a thirty-second limit on a fetch that
        // answered in ten milliseconds. This one is cleared the moment the answer is whole,
        // which is `finish_fetch` cancelling the interpreter's.
        //
        // **The abort reaches the body read as well as the request**, so the limit covers the
        // whole fetch on both hosts, and a fetch it stopped answers the interpreter's sentence
        // rather than the host's `AbortError`.
        let timer = null
        let timedOut = false
        let ctl = null

        if (limit > 0n) {
            if ($.host.abortController === null || $.host.setTimeout === null)
                fault("`timeout` needs the host's own `AbortController` and timers, and this " +
                    "JavaScript host has none")

            ctl = new $.host.abortController()
            init.signal = ctl.signal
            timer = $.host.setTimeout(() => { timedOut = true; ctl.abort() },
                Math.min(Number(limit), 2147483647))
        } else if (stream && $.host.abortController !== null) {
            // **A streamed body is given a controller even with no limit**, so that `dispose`
            // can end the request as well as the read.
            ctl = new $.host.abortController()
            init.signal = ctl.signal
        }

        const lateSentence = () => timedOut
            ? url + " did not answer within " + limit + " milliseconds"
            : null

        const fail = (message) => fetchBad(lateSentence() ?? message)

        const clear = () => {
            if (timer !== null) $.host.clearTimeout(timer)

            timer = null
        }

        const done = (answer) => {
            clear()
            return answer
        }

        // **A streamed answer keeps the limit running**, the body being part of the exchange it
        // covers; the body clears it when it ends. A fetch that failed before a body existed
        // clears it here, as a buffered one does.
        const answered = stream
            ? (r) => fetchStreamed(r, url, clear, lateSentence,
                () => { if (ctl !== null) ctl.abort() })
            : (r) => fetchAnswer(r, fail).then(done)

        // **The failure is a result and never a rejection**, which is `fetch`'s rule in slate
        // whichever host answers: a server that cannot be reached is the ordinary thing a client
        // deals with. The host's own words are quoted rather than replaced, being the only
        // account of what went wrong that exists here.
        return $.host.fetch(url, init).then(answered,
            (e) => done(fail("cannot reach " + url + ": " + fetchWhy(e))))
    }

        // -- sockets ---------------------------------------------------------------------------------

        // node's own TCP, or nothing where there is none.
        //
        // **`require` rather than a global, because there is no global to read.** A browser has
        // neither, and the two conditions are asked separately so that a host with `process` and no
        // module loader answers the same *no* rather than throwing.
        const netHost = (() => {
            const load = $.host.require

            if (typeof process === "undefined" || typeof load !== "function") return null

            try {
                return load("node:net")
            } catch (e) {
                return null
            }
        })()

        // node's `tls`, which is there wherever its `net` is.
        const tlsHost = (() => {
            if (netHost === null) return null

            try {
                return $.host.require("node:tls")
            } catch (e) {
                return null
            }
        })()

        const noSockets = (name) =>
            fault("`" + name + "` needs a host with sockets, and this JavaScript host has none")

        // One slot per socket, and a slot is given back by `close` and reused. **The generation is
        // what stops the value a program still holds from coming to mean its successor**, which is
        // the same arrangement the timers' ids run on.
        const socks = []
        const spareSocks = []
        let socketGen = 0

        const takeSocket = (handle, listening) => {
            socketGen += 1

            const slot = {
                handle: handle,
                listening: listening,
                gen: socketGen,
                reader: null,
                asText: true,
                onError: null,
                reading: false,
                listeners: null,
                secured: false,
                upgrading: false,
                plain: null,
                unclaimed: false,
                backlog: null,
                accept: null,
                closed: false
            }

            const spare = spareSocks.pop()

            if (spare !== undefined) {
                socks[spare] = slot

                return new $.SSocket(spare, socketGen)
            }

            socks.push(slot)

            return new $.SSocket(socks.length - 1, socketGen)
        }

        // What a program is holding, or the sentence saying it is not that.
        //
        // **The two refusals are the interpreter's own, word for word.** One is about the kind of
        // value and the other about a socket that has been given back, and a program telling them
        // apart is a program that knows whether it wrote the wrong name or closed too early.
        const socketOf = (v, name) => {
            if (!(v instanceof $.SSocket)) fault("`" + name + "` takes a socket, and this is " + typeName(v))

            const slot = socks[v.id]

            if (slot === undefined || slot === null || slot.gen !== v.gen || slot.closed)
                fault("this socket is closed, and `" + name + "` needs an open one")

            return slot
        }

        // A function to call back, checked the way the interpreter checks one.
        const wantHandler = (v, sentence) => {
            if (typeof v !== "function") fault(sentence + typeName(v))

            return v
        }

        // What node calls an error, as one sentence. **node's `code` and libuv's spelling are the
        // same word** -- `ECONNREFUSED`, `ENOTFOUND` -- so the two back ends name the same cause even
        // where the rest of the sentence differs, which is the most that can be promised about an
        // operating system's own message.
        const netWhy = (e) => {
            if (e === null || e === undefined) return "unknown error"
            if (e.code !== undefined && e.message !== undefined) return e.code + ": " + e.message

            return String(e.message === undefined ? e : e.message)
        }

        // An IPv4 client of a dual-stack listener is written the way it dialled.
        //
        // **Not cosmetic**: node binds `::` for a listener with no host, so every IPv4 peer arrives
        // as `::ffff:127.0.0.1` -- and an allow-list or a rate limit keyed on `127.0.0.1` would match
        // nothing at all. The interpreter takes the same prefix off for the same reason.
        const unmapped = (ip) => ip.startsWith("::ffff:") ? ip.slice(7) : ip

        // Hand one chunk, or the end of the stream, to whoever is reading.
        //
        // **The end of a stream is `null` and not a failure**, which is the right distinction and not
        // merely libuv's: a peer closing its half is how a request ordinarily ends.
        const deliverChunk = (slot, value) => {
            const f = slot.reader

            if (f === null) return

            $.callback(f, [value], slot.asText ? "onData" : "onBytes")
        }

        // A socket failed. **The reason goes to `onError` where there is one and the stream ends
        // either way**, which is the interpreter's rule: a reset is something any peer can produce,
        // so it arrives as the same `null` a peer that finished sends and `onError` is how a program
        // tells the two apart.
        const failStream = (slot, why) => {
            if (slot.onError !== null) $.callback(slot.onError, [why], "onError")
            else deliverChunk(slot, null)
        }

        // Start delivering what arrives, once. **A second `onData` swaps the slate callback and does
        // not add a second node listener**, which is what makes a protocol that changes what it
        // expects halfway through writable at all -- and is why the flow is not started twice.
        //
        // **A socket in the middle of a TLS handshake is not started here**: the reader is recorded
        // and `startTls` installs it on the secured socket once the handshake has finished, so a
        // handshake that fails is reported once and in its own words rather than twice.
        const startReading = (slot) => {
            if (slot.reading || slot.listening || slot.upgrading) return

            slot.reading = true

            const onChunk = (buf) => {
                if (slot.asText) {
                    // **A chunk is a chunk and not a message**, so this can split a character in half
                    // where a peer sends one across two packets -- and a chunk that is not text at
                    // all fails the connection rather than arriving as replacement characters.
                    const said = new TextDecoder("utf-8", { fatal: true })

                    let text = null

                    try {
                        text = said.decode(buf)
                    } catch (e) {
                        failStream(slot, "this chunk is not text -- `onBytes` reads a socket that carries something else")

                        return
                    }

                    deliverChunk(slot, text)

                    return
                }

                // **A CHUNK IS A BUFFER NOW, WHERE IT WAS AN ARRAY OF NUMBERS** -- the interpreter's
                // `plainly_arrived` carries the reasoning. A copy, because node reuses the `Buffer`
                // it hands to the listener.
                deliverChunk(slot, $.bytesOf(new Uint8Array(buf)))
            }

            const onEnd = () => deliverChunk(slot, null)
            const onFailed = (e) => failStream(slot, "this connection failed: " + netWhy(e))

            // Kept so that `startTls` can take them off the plain socket it is about to wrap.
            slot.listeners = { data: onChunk, end: onEnd, error: onFailed }

            slot.handle.on("data", onChunk)
            slot.handle.on("end", onEnd)
            slot.handle.on("error", onFailed)
        }

        // A listener's own options, which is a port or a record carrying one. Answers the port and
        // whether `reusePort` was asked for -- `false` where the record left it out, which is the
        // ordinary case and the one every existing program keeps.
        const listenTarget = (v) => {
            if ($.isInt(v)) return { port: Number(v), reusePort: false, secure: null }

            if (v instanceof $.SObj) {
                const port = v.getName("port")

                if (!$.isInt(port)) fault("`listen` takes a port, and this is " + typeName(port))

                const reusePort = v.hasName("reusePort") ? v.getName("reusePort") : false

                if (typeof reusePort !== "boolean") fault("`reusePort` is true or false, and this is " + typeName(reusePort))

                // **`cert` is what says the listener is to be secured**, as it is in the
                // interpreter: a `key` with no `cert` beside it is not looked at.
                if (v.hasName("cert")) {
                    const cert = pemOf(v, "cert", "{ port, cert, key }")
                    const key = pemOf(v, "key", "{ port, cert, key }")

                    return { port: Number(port), reusePort: reusePort, secure: { cert: cert, key: key, alpn: alpnOf(v) } }
                }

                return { port: Number(port), reusePort: reusePort, secure: null }
            }

            fault("`listen` takes a port or a record of options, and this is " + typeName(v))
        }

        B.listen = (where, f) => {
            if (netHost === null) noSockets("listen")

            wantHandler(f, "`listen` needs a function to call with each connection, and this is ")

            // `listen(socket, fn)`: a listener another program passed over a channel.
            if (where instanceof $.SSocket) return listenPassed(where, f)

            const target = listenTarget(where)
            const port = target.port

            if (port < 0 || port > 65535) fault("a port is between 0 and 65535, and this is " + port)

            // **A secured listener is node's `tls.createServer`, and `f` is called once a
            // connection's handshake has finished** -- where the interpreter hands the connection
            // over first and handshakes at its first read. What the program is given is the same:
            // a connection whose bytes are already decrypted. The certificate and key are checked
            // here, before anything binds, with the interpreter's sentence.
            let secure = null

            if (target.secure !== null) {
                if (tlsHost === null) noSockets("listen")

                try {
                    secure = tlsHost.createSecureContext({ cert: target.secure.cert, key: target.secure.key })
                } catch (e) {
                    fault("this certificate and key could not be used: " + netWhy(e))
                }
            }

            // **`pauseOnConnect` and not only the `pause()` below**: a paused node socket is a
            // paused *stream*, and its handle goes on reading into a buffer until the high-water
            // mark. Bytes read that way belong to this process -- so a connection handed to another
            // program over a channel lost whatever had arrived before the handover, and the worker
            // waited for a request that had already been eaten. Not reading at all until `onData`
            // is also exactly what the interpreter does.
            //
            // **A secured listener cannot say it**: `tls` reads from the raw socket to run the
            // handshake, so a paused one never finishes it. The secured connection is paused once
            // the handshake is over instead, and what a program reads is held for it by the stream.
            let server = null

            if (secure === null) {
                server = netHost.createServer({ pauseOnConnect: true })
            } else {
                // **The certificate and key go in as themselves and not as the context checked
                // above**: node's `tls.Server` ignores a `secureContext` for the certificate it
                // offers and answers every handshake with `no suitable signature algorithm`.
                const opts = { cert: target.secure.cert, key: target.secure.key }

                if (target.secure.alpn.length > 0) opts.ALPNProtocols = target.secure.alpn

                server = tlsHost.createServer(opts)

                // A client that fails its handshake is nothing the program is told about, as it
                // never had the connection; node would otherwise leave the event unhandled.
                server.on("tlsClientError", () => null)
            }

            const value = takeSocket(server, true)

            server.on(secure === null ? "connection" : "secureConnection", (conn) => {
                // **The connection gets a slot of its own and no reader**, exactly as it does in the
                // interpreter: it is the program's to read from, write to and close.
                const held = takeSocket(conn, false)

                if (secure !== null) socks[held.id].secured = true

                conn.pause()
                $.callback(f, [held], "listen")
            })

            // **A listener that cannot bind is a fault and not a result**, which is the interpreter's
            // reading: a port already taken is a mistake in the program or in what is running beside
            // it, where a refused *connection* is the ordinary thing a client handles.
            server.on("error", (e) => fault("cannot listen on port " + port + ": " + netWhy(e)))

            // **`reusePort` is passed through by the same key node itself uses** (node 23.1+), so
            // several processes may share this port and the kernel spreads accepted connections
            // across them -- the same flag `slate:net`'s interpreter path asks the kernel for.
            server.listen({ port: port, reusePort: target.reusePort })

            return value
        }

        // `listen(socket, fn)` -- accept on a listening socket another program passed over a channel.
        //
        // **The socket is already bound and listening**, so there is no port to choose and nothing
        // to secure, and the sentences are the interpreter's. The program goes on holding the value
        // it was handed: `close` on it stops the listening and `localPort` answers the port.
        const listenPassed = (where, f) => {
            const slot = socketOf(where, "listen")

            if (slot.listening) fault("this socket is already listening")

            if (!slot.unclaimed)
                fault("`listen` takes a socket another program was listening on, and this one is a connection")

            const queued = slot.backlog

            slot.unclaimed = false
            slot.listening = true
            slot.backlog = null

            const deliver = (conn) => {
                const held = takeSocket(conn, false)

                conn.pause()
                $.callback(f, [held], "listen")
            }

            slot.accept = deliver

            for (const conn of queued) deliver(conn)

            return where
        }

        B.connect = (host, port) => {
            if (netHost === null) noSockets("connect")

            wantString(host, "connect")

            if (!$.isInt(port)) fault("`connect` takes a port, and this is " + typeName(port))

            const n = Number(port)

            if (n < 0 || n > 65535) fault("a port is between 0 and 65535, and this is " + n)

            // **A refused connection is a settled promise and not a thrown complaint**, a peer that
            // is not there being the ordinary thing a client deals with.
            return new Promise((resolve) => {
                const conn = netHost.connect({ host: host, port: n })
                const held = takeSocket(conn, false)
                let settled = false

                conn.pause()

                conn.once("connect", () => {
                    if (settled) return

                    settled = true

                    resolve($.obj([["ok", true], ["value", held]]))
                })

                conn.once("error", (e) => {
                    if (settled) return

                    settled = true

                    dropSocket(held.id, held.gen)
                    resolve($.obj([["ok", false], ["error", "cannot connect to " + host + ":" + n + ": " + netWhy(e)]]))
                })
            })
        }

        const readSocket = (v, f, asText) => {
            const name = asText ? "onData" : "onBytes"

            wantHandler(f, "`" + name + "` needs a function to call with each chunk, and this is ")

            const slot = socketOf(v, name)

            slot.reader = f
            slot.asText = asText

            startReading(slot)

            if (!slot.listening && !slot.upgrading) slot.handle.resume()

            return null
        }

        B.onData = (v, f) => readSocket(v, f, true)
        B.onBytes = (v, f) => readSocket(v, f, false)

        B.onError = (v, f) => {
            wantHandler(f, "`onError` needs a function to call with the reason, and this is ")

            socketOf(v, "onError").onError = f

            return null
        }

        // `send(sock, v)` -- a promise that settles when the bytes have gone. **An array is sent as
        // bytes**, which is the one thing about this call a program has to know.
        B.send = (v, data) => {
            const slot = socketOf(v, "send")

            let payload = null

            if ($.isStr(data)) payload = Buffer.from(data, "utf8")

            // **A buffer is the shape a program reaches for now**, and it is the cheap one: nothing
            // is decoded on the way to the socket.
            else if (data instanceof $.SBytes) payload = Buffer.from(data.view())
            else if (Array.isArray(data)) {
                const bytes = []

                for (const b of data) {
                    if (!$.isInt(b)) fault("`send` takes an array of numbers, and one of these is " + typeName(b))

                    const n = Number(b)

                    if (n < 0 || n > 255) fault("a byte is between 0 and 255, and this is " + n)

                    bytes.push(n)
                }

                payload = Buffer.from(bytes)
            } else fault("`send` takes a string or an array of numbers, and this is " + typeName(data))

            if (slot.finished === true) {
                return Promise.resolve($.obj([["ok", false], ["error", "cannot send: this end has shut down its writing, and only `close` is left to it"]]))
            }

            return new Promise((resolve) => {
                slot.handle.write(payload, (e) => {
                    if (e === null || e === undefined) resolve($.obj([["ok", true], ["value", null]]))
                    else resolve($.obj([["ok", false], ["error", "cannot send: " + netWhy(e)]]))
                })
            })
        }

        // `shutdown(sock)` -- a promise that settles once this end has said it will write no more:
        // node's `socket.end()`, which on a secured socket writes the close-notify first. **A second
        // one answers `{ ok: true }` again** and reading goes on, exactly as the interpreter does.
        B.shutdown = (v) => {
            const slot = socketOf(v, "shutdown")

            if (slot.listening || slot.unclaimed) {
                return Promise.resolve($.obj([["ok", false], ["error", "cannot shut down: this socket is not a connection"]]))
            }

            if (slot.finished === true) return Promise.resolve($.obj([["ok", true], ["value", null]]))

            if (slot.upgrading) {
                return Promise.resolve($.obj([["ok", false], ["error", "cannot shut down: the TLS handshake has not finished"]]))
            }

            slot.finished = true

            return new Promise((resolve) => {
                slot.handle.end(() => resolve($.obj([["ok", true], ["value", null]])))
            })
        }

        // Give a slot back, which is what lets the program exit.
        const dropSocket = (id, gen) => {
            const slot = socks[id]

            if (slot === undefined || slot === null || slot.gen !== gen || slot.closed) return

            slot.closed = true
            slot.reader = null
            slot.onError = null
            socks[id] = null
            spareSocks.push(id)

            try {
                if (slot.listening || slot.unclaimed) slot.handle.close()
                else slot.handle.destroy()

                // A secured socket stands on the plain one it wrapped, and both are let go.
                if (slot.plain !== null) slot.plain.destroy()
            } catch (e) {
                // **A socket the host has already torn down is nothing to say about**, which is the
                // same reading closing twice gets below.
            }
        }

        // A socket somebody else accepted, taken into this program's own table.
        //
        // **`pause` for the reason a listener's connection is paused**: it is the program's to read
        // from when it calls `onData`, and node would otherwise start delivering data to nobody. Not
        // a builtin -- `js_rt_process.sysl` calls it for a socket that arrived over a channel, and it
        // is here because this is the file that owns the table.
        //
        // **A listener arrives as a node `net.Server` and is `Unclaimed`**, the interpreter's word
        // for a passed socket nobody has used yet: connections that come before `listen(socket, fn)`
        // are held, unread, and handed to `fn` when it is called.
        const adoptSocket = (conn) => {
            if (netHost !== null && conn instanceof netHost.Server) {
                const held = takeSocket(conn, false)
                const slot = socks[held.id]

                slot.unclaimed = true
                slot.backlog = []
                conn.pauseOnConnect = true
                conn.on("connection", (c) => {
                    c.pause()

                    if (slot.accept === null) slot.backlog.push(c)
                    else slot.accept(c)
                })
                conn.on("error", (e) => fault("a connection could not be accepted: " + netWhy(e)))

                return held
            }

            conn.pause()

            return takeSocket(conn, false)
        }

        // A socket about to be handed to another program stops reading here, before it goes.
        //
        // **node keeps the sender's copy of the descriptor open and READING until the receiver
        // acknowledges the handle**, and what it reads in that window goes to a callback node has
        // already emptied -- so the peer's next bytes vanish and the receiver waits for them for
        // ever. Stopping the read leaves them in the kernel, where the receiver's copy finds them.
        // node has no public call for this (`pause()` stops the stream, not the handle), so the
        // handle's own `readStop` is used, guarded for a host where it is absent. Answers whether
        // a read was stopped, so that a handover that failed can put it back.
        const stopReadingForHandover = (slot) => {
            const h = slot.handle._handle

            if (h === null || h === undefined || typeof h.readStop !== "function" || !h.reading) return false

            h.reading = false
            h.readStop()

            return true
        }

        // The socket stayed here after all -- the message could not be written -- so a program that
        // was reading it goes on reading.
        const restartReading = (slot) => {
            const h = slot.handle._handle

            if (h === null || h === undefined || typeof h.readStart !== "function") return

            h.reading = true
            h.readStart()
        }

        B.close = (v) => {
            if (!(v instanceof $.SSocket)) fault("`close` takes a socket, and this is " + typeName(v))

            // **Closing a socket twice is not an error.** A server closing its connections and a read
            // callback closing its own on end-of-stream is the ordinary way to write this, and making
            // the second one a failure would make the ordinary way wrong.
            dropSocket(v.id, v.gen)

            return null
        }

        B.localPort = (v) => {
            const slot = socketOf(v, "localPort")

            const port = slot.listening
                ? (slot.handle.address() === null ? null : slot.handle.address().port)
                : slot.handle.localPort

            if (port === null || port === undefined) fault("this socket has no address")

            return BigInt(port)
        }

        // **`null` where the socket has no other end**, which is a listener and a socket that has
        // been closed. That is an answer rather than a fault: a program asking who connected is
        // asking about a thing that may not be there.
        B.remoteAddress = (v) => {
            const slot = socketOf(v, "remoteAddress")

            if (slot.listening) return null

            const ip = slot.handle.remoteAddress

            return ip === null || ip === undefined ? null : unmapped(ip)
        }

        // **`null` on a plain socket, which is what both back ends answer and is why this is here
        // rather than on the owed list.** `slate:http` reads it at the first byte of every connection
        // to tell HTTP/2 from HTTP/1.1, so a name that refused would make every `serve` fault over a
        // question whose answer is *no*.
        B.alpnProtocol = (v) => {
            const chosen = socketOf(v, "alpnProtocol").handle.alpnProtocol

            return chosen === null || chosen === undefined || chosen === false ? null : chosen
        }

        // A certificate, a key or an authority: PEM text, or its bytes. `tls.sysl`'s `pem_of` and
        // `trust`, sentence for sentence.
        const pemOf = (o, name, shape) => {
            if (!o.hasName(name)) fault("securing this needs `" + name + "`, as PEM text -- `" + shape + "`")

            return pemText(o.getName(name), name)
        }

        const pemText = (v, name) => {
            if ($.isStr(v)) return v
            if (v instanceof $.SBytes || Array.isArray(v)) return Buffer.from($.bytesLike(v, name))

            fault("`" + name + "` is PEM text or its bytes, and this is " + typeName(v))
        }

        // The protocols one end offers, where it named any. Empty is ALPN not offered at all.
        const alpnOf = (o) => {
            if (!o.hasName("alpn")) return []

            const names = o.getName("alpn")

            if (!Array.isArray(names)) fault("`alpn` is a list of protocol names, and this is " + typeName(names))

            for (const n of names)
                if (!$.isStr(n)) fault("`alpn` is a list of protocol names, and one of them is " + typeName(n))

            return names
        }

        // `startTls`'s second argument -- the interpreter's `start_tls_target`, read in its order:
        // **`cert` says this end is the server**, and is looked for before `host`.
        const upgradeTarget = (v) => {
            if ($.isStr(v)) return { server: false, host: v, trust: null, alpn: [] }

            if (v instanceof $.SObj) {
                if (v.hasName("cert")) {
                    const cert = pemOf(v, "cert", "{ cert, key }")
                    const key = pemOf(v, "key", "{ cert, key }")

                    return { server: true, cert: cert, key: key, alpn: alpnOf(v) }
                }

                if (!v.hasName("host"))
                    fault("`startTls` was given an object with no `host` in it -- the name is what the certificate is checked against, and a server upgrading its end says `{ cert, key }` instead")

                const host = v.getName("host")

                if (!$.isStr(host)) fault("`startTls` takes the host as a name, and this is " + typeName(host))

                const trust = v.hasName("trust") ? pemText(v.getName("trust"), "trust") : null

                return { server: false, host: host, trust: trust, alpn: alpnOf(v) }
            }

            fault("`startTls` takes the host to connect as, or an object saying more about it, and this is " + typeName(v))
        }

        // A handshake that did not finish, in the interpreter's words where they are slate's own.
        //
        // **node reports a peer that hung up mid-handshake as a reset it made up itself**, with a
        // sentence about "secure TLS connection" -- where the interpreter reads the same event as the
        // end of the stream. The two are one event and are given the one sentence.
        const handshakeWhy = (e) => {
            if (e !== null && e !== undefined && e.code === "ECONNRESET" && String(e.message).includes("before secure TLS"))
                return "this connection ended before the TLS handshake finished"

            return "the TLS handshake failed: " + netWhy(e)
        }

        // `startTls(sock, host)` and `startTls(conn, { cert, key })` -- an open socket, upgraded.
        //
        // **node's own STARTTLS: the plain socket is handed to `tls`, which wraps the handle it
        // stands on**, and anything still being written in the clear goes out first -- which is the
        // one byte a PostgreSQL server answers before its handshake. The slot keeps its number and
        // its generation and only its handle changes, so the value the program holds is the secured
        // socket from here on, exactly as in the interpreter.
        //
        // **The promise carries a result and never rejects**: `{ ok: true, value: null }` once the
        // handshake has finished, `{ ok: false, error }` where it did not -- and a socket whose
        // handshake failed is closed, the reader being told `"this connection could not be secured"`
        // the way any other failed stream is told.
        B.startTls = (sock, options) => {
            if (netHost === null || tlsHost === null) noSockets("startTls")

            const target = upgradeTarget(options)
            const slot = socketOf(sock, "startTls")

            if (slot.secured) fault("this socket is already secured, and `startTls` upgrades a plain one")

            if (slot.listening) fault("`startTls` upgrades a connection, and this socket is listening for them")

            return new Promise((resolve) => {
                let context = null

                try {
                    context = target.server
                        ? tlsHost.createSecureContext({ cert: target.cert, key: target.key })
                        : tlsHost.createSecureContext(target.trust === null ? {} : { ca: tlsHost.rootCertificates.concat([target.trust]) })
                } catch (e) {
                    const why = target.server
                        ? "this certificate and key could not be used: "
                        : "this certificate could not be trusted: "

                    resolve($.obj([["ok", false], ["error", why + netWhy(e)]]))

                    return
                }

                const plain = slot.handle

                // **The plain socket's reader comes off before `tls` takes its handle**, or it would
                // be handed the handshake's ciphertext as though it were the program's data.
                if (slot.listeners !== null) {
                    plain.removeListener("data", slot.listeners.data)
                    plain.removeListener("end", slot.listeners.end)
                    plain.removeListener("error", slot.listeners.error)
                    slot.listeners = null
                }

                // What the secured socket reports is the secured socket's, and the plain one under
                // it must not stop node with an `error` nobody is listening for.
                plain.on("error", () => null)

                slot.reading = false
                slot.secured = true
                slot.upgrading = true

                const opts = { socket: plain, secureContext: context }

                if (target.alpn.length > 0) opts.ALPNProtocols = target.alpn

                let secured = null

                if (target.server) {
                    opts.isServer = true
                    secured = new tlsHost.TLSSocket(plain, opts)
                } else {
                    // **The name is what the certificate is checked against**, and is offered as SNI
                    // where it is a name -- an address may not be, by RFC 6066.
                    opts.host = target.host
                    if (netHost.isIP(target.host) === 0) opts.servername = target.host
                    secured = tlsHost.connect(opts)
                }

                slot.plain = plain
                slot.handle = secured

                let settled = false

                const finished = () => {
                    if (settled) return

                    settled = true
                    slot.upgrading = false

                    resolve($.obj([["ok", true], ["value", null]]))

                    if (slot.closed) return

                    if (slot.reader !== null) {
                        startReading(slot)
                        secured.resume()
                    }
                }

                const denied = (why) => {
                    if (settled) return

                    settled = true
                    slot.upgrading = false

                    resolve($.obj([["ok", false], ["error", why]]))

                    if (slot.closed) return

                    failStream(slot, "this connection could not be secured")
                    dropSocket(sock.id, sock.gen)
                }

                secured.once(target.server ? "secure" : "secureConnect", finished)

                // **Kept for the life of the socket and not only the handshake**: an `error` nobody
                // listens for stops node outright, and the reader's own listener is not on until the
                // handshake is done.
                secured.on("error", (e) => denied(handshakeWhy(e)))
                secured.once("close", () => denied("this connection ended before the TLS handshake finished"))
            })
        }

    // -- child processes -----------------------------------------------------------------------

    // node's own, or nothing where there is none. **`require` rather than a global**, for
    // `js_rt_net.sysl`'s reason: a browser has neither, and the two conditions are asked apart so
    // that a host with `process` and no module loader answers the same *no* rather than throwing.
    const procHost = (() => {
        const load = $.host.require

        if (typeof process === "undefined" || typeof load !== "function") return null

        try {
            return { children: load("node:child_process"), sockets: load("node:net"),
                     system: load("node:os") }
        } catch (e) {
            return null
        }
    })()

    const noChildren = (name) =>
        fault("`" + name + "` needs a host with processes, and this JavaScript host has none")

    // The descriptor the child is given, and the name it arrives under. Both are the
    // interpreter's, and they are what makes a child of one back end readable by the other.
    const CHANNEL_VARIABLE = "SLATE_CHANNEL_FD"
    const CHANNEL_FD = 3

    // The name the parent's host arrives under, and the three answers a peer can have. **A
    // socket may only be passed between two programs on the same host**, so each end has to know
    // what the other is before it writes one.
    const HOST_VARIABLE = "SLATE_CHANNEL_HOST"
    const HOST_NAME = "js"
    const OTHER_HOST = "native"
    const HOST_UNKNOWN = "?"

    // The line a channel opens with, which is how a parent finds out what its child is. The
    // interpreter writes the same bytes.
    const helloText = (host) => "{\"$slate\":\"" + host + "\"}"

    // The host a message names, where it is one of those lines and not an ordinary message.
    const helloHost = (m) => {
        if (m === null || typeof m !== "object" || Array.isArray(m)) return null

        const keys = Object.keys(m)

        if (keys.length !== 1 || keys[0] !== "$slate") return null

        return m.$slate === HOST_NAME || m.$slate === OTHER_HOST ? m.$slate : null
    }

    // Why a socket may not be passed to a peer, and `null` where it may. **The refusals are the
    // interpreter's own, word for word.**
    const handlesRefused = (peer, isChild) => {
        if (peer === HOST_NAME) return null

        const who = isChild ? "this child" : "the program that started this one"

        if (peer === OTHER_HOST)
            return who + " is running on the interpreter and this program on the JavaScript host, so a socket cannot cross the channel"

        if (peer === HOST_UNKNOWN)
            return who + " is not a slate program, so a socket cannot cross the channel"

        if (isChild)
            return "this child has not said what it is yet -- a socket may be passed to a child once that child has sent its first message"

        return who + " did not say which host it is running on, so a socket cannot cross the channel"
    }

    // **The signals by name, and the list is the interpreter's own.** node takes a name and
    // answers one, where libuv counts -- so the number is looked up here, or the two back ends
    // would report a killed child differently.
    const SIGNAL_NAMES = ["SIGHUP", "SIGINT", "SIGQUIT", "SIGABRT", "SIGKILL", "SIGPIPE",
        "SIGALRM", "SIGTERM", "SIGCHLD", "SIGCONT", "SIGSTOP", "SIGTSTP", "SIGUSR1", "SIGUSR2",
        "SIGWINCH"]

    const SENDABLE = "SIGHUP, SIGINT, SIGQUIT, SIGABRT, SIGPIPE, SIGALRM, SIGTERM, SIGCHLD, " +
        "SIGCONT, SIGTSTP, SIGUSR1, SIGUSR2 and SIGWINCH"

    const signalNumber = (name) => {
        if (procHost === null) return undefined

        const known = procHost.system.constants.signals[name]

        return SIGNAL_NAMES.indexOf(name) < 0 ? undefined : known
    }

    // One slot per child, never given back: `child.pid` and `child.exited` answer for a child
    // that has already died, so a slot reused underneath a value a program still holds would be
    // a use-after-free wearing an integer's clothes. The interpreter's table, word for word.
    const kidSlots = []

    const childOf = (v, name) => {
        if (!(v instanceof $.SChild))
            fault("`" + name + "` is something a child process does, and this is " + typeName(v))

        const slot = kidSlots[v.id]

        if (slot === undefined || slot === null || slot.gen !== v.gen)
            fault("this child was started by another program, and `" + name + "` needs one of this program's")

        return slot
    }

    const wantChildHandler = (v, name) => {
        if (typeof v !== "function")
            fault("`" + name + "` needs a function to call, and this is " + typeName(v))

        return v
    }

    // Hand every whole message in the buffer to whoever is listening.
    //
    // **A message arrives whole or not at all**, a read being a run of bytes rather than a
    // message: two arrive in one read as often as half of one does.
    const takeLines = (slot) => {
        for (;;) {
            const cut = slot.inbox.indexOf("\n")

            if (cut < 0) return

            const line = slot.inbox.slice(0, cut).replace(/\r$/, "")

            slot.inbox = slot.inbox.slice(cut + 1)

            if (line.length === 0) continue

            // **The line a channel opens with says which host the child is on, and is
            // swallowed.** Only a child's first line is read this way, so a program whose own
            // messages look like this is misread only in its very first one.
            if (slot.child && slot.peer === "") {
                if (line === helloText(HOST_NAME)) { slot.peer = HOST_NAME; continue }
                if (line === helloText(OTHER_HOST)) { slot.peer = OTHER_HOST; continue }

                slot.peer = HOST_UNKNOWN
            }

            // **A line that is not JSON stops the program naming the channel**, rather than
            // being dropped where nobody would see it: the sender is another program of the same
            // system, so this is a defect somebody can fix.
            const read = B.parseJSON(line)

            if (read.getKey("ok") !== true)
                fault("a message on the channel is not JSON: " + read.getKey("error"))

            const f = slot.onMessage

            // **A socket is `null` on this wire and always will be.** A descriptor crosses
            // node's own channel and nothing else, so a plain pipe carries messages alone.
            if (f !== null) $.callback(f, [read.getKey("value"), null], "onMessage")
        }
    }

    // One message off node's own channel, which is the wire a socket can cross.
    //
    // **The value is put back through `parseJSON` rather than converted here**, so that one
    // reading of a JSON document reaches a slate program however it arrived.
    const nodeMessage = (slot, msg, socket) => {
        if (slot.child && slot.peer === "") {
            const said = helloHost(msg)

            if (said !== null) { slot.peer = said; return }

            slot.peer = HOST_UNKNOWN
        }

        const read = B.parseJSON(JSON.stringify(msg === undefined ? null : msg))

        if (read.getKey("ok") !== true)
            fault("a message on the channel is not JSON: " + read.getKey("error"))

        const f = slot.onMessage

        if (f === null) return

        const held = socket === undefined || socket === null ? null : adoptSocket(socket)

        $.callback(f, [read.getKey("value"), held], "onMessage")
    }

    // Read one end of a channel until it ends. **A failure is an end and not a fault**: a
    // channel fails when the peer goes, and the peer going is the ordinary end of a conversation.
    const readChannel = (pipe, slot, ended) => {
        pipe.setEncoding("utf8")
        pipe.on("data", (d) => { slot.inbox += d; takeLines(slot) })
        pipe.on("end", ended)
        pipe.on("close", ended)
        pipe.on("error", ended)
    }

    // One message, framed: the JSON and the newline that ends it.
    //
    // **`toJSON` is what refuses a value that is not a message**, which is where the sentence
    // comes from and why it is the same sentence on both back ends.
    const framed = (v) => B.toJSON(v) + "\n"

    // **A write that cannot be made is a RESULT and not a fault.** A worker dying while its
    // supervisor was writing to it is the ordinary shape of a process ending, and a supervisor
    // that had to wrap every `send` in a `try` to survive one is a supervisor nobody would write.
    // **Given to `send` so that a failed write is reported to it and not emitted as an `error` event on
    // the child.** That event reached the handler for a child that could not be started, which then
    // settled the child as never having run, and the exit that followed was never delivered.
    const ignoreSendError = () => {}

    const writeMessage = (slot, text, socket, why) => {
        if (!slot.open || slot.channel === null) return $.obj([["ok", false], ["error", why]])

        // **A node channel that has already disconnected is a failed write, said here.** `send`
        // on one does not throw: it emits an `error` event on the child, and so does a write the
        // kernel refuses a moment later (`EPIPE`, which is what answering a worker that has
        // already ended produces). The callback below is what turns the second kind into a value
        // nobody listens for, and this check is the first kind.
        if (slot.node && !slot.channel.connected)
            return $.obj([["ok", false], ["error", why]])

        try {
            if (!slot.node) slot.channel.write(text)
            else if (socket === undefined || socket === null) slot.channel.send(JSON.parse(text), ignoreSendError)
            else slot.channel.send(JSON.parse(text), socket, ignoreSendError)

            return $.obj([["ok", true], ["value", null]])
        } catch (e) {
            return $.obj([["ok", false],
                ["error", "this message could not be sent: " + (e && e.message ? e.message : String(e))]])
        }
    }

    // One message with a socket beside it, and this program's own copy given up.
    //
    // **The copy is given up because what crossed is a duplicate**, so leaving both open would
    // have two programs reading one connection and each seeing half of it. node closes its own
    // side of a sent handle by default and this closes the slate value that named it, so the two
    // back ends agree about what a program is holding afterwards.
    const sendWithSocket = (slot, text, sock, isChild, why) => {
        if (!(sock instanceof $.SSocket))
            fault("`send` passes on a socket, and this is " + typeName(sock))

        const refusal = handlesRefused(slot.peer, isChild)

        if (refusal !== null) fault(refusal)

        const held = socketOf(sock, "send")
        const stopped = stopReadingForHandover(held)
        const answer = writeMessage(slot, text, held.handle, why)

        if (answer.getKey("ok") === true) B.close(sock)
        else if (stopped) restartReading(held)

        return answer
    }

    const childOptions = (v, name) => {
        if (v === null || v === undefined) return { cwd: "", env: null, ipc: false }
        if (!(v instanceof $.SObj))
            fault("`" + name + "` takes its options as an object, and this is " + typeName(v))

        const cwd = v.getKey("cwd")
        const env = v.getKey("env")
        const ipc = v.getKey("ipc")

        if (cwd !== undefined && !$.isStr(cwd))
            fault("`cwd` is a string, and this is " + typeName(cwd))

        if (ipc !== undefined && typeof ipc !== "boolean")
            fault("`ipc` is true or false, and this is " + typeName(ipc))

        // **The environment REPLACES the child's rather than adding to it**, which is what `run`
        // does in the interpreter and what libuv does underneath it.
        let given = null

        if (env !== undefined && env !== null) {
            if (!(env instanceof $.SObj))
                fault("`env` is an object of names and values, and this is " + typeName(env))

            given = {}

            for (const pair of B.entries(env)) {
                const k = pair[0]
                const value = pair[1]

                if (!$.isStr(k))
                    fault("an environment variable is named by a string, and this is " + typeName(k))

                if (!$.isStr(value))
                    fault("an environment variable is a string, and `" + k + "` is " + typeName(value))

                given[k] = value
            }
        }

        return { cwd: $.isStr(cwd) ? cwd : "", env: given, ipc: ipc === true }
    }

    B.spawn = (...args) => {
        if (args.length < 1 || args.length > 3)
            fault("`spawn` takes a command, its arguments and optionally some options, and was given " +
                args.length + (args.length === 1 ? " argument" : " arguments"))

        const command = args[0]

        if (!$.isStr(command)) fault("`spawn` takes a command as a string, and this is " + typeName(command))

        const given = args.length > 1 ? args[1] : []

        if (!Array.isArray(given))
            fault("`spawn` takes the arguments as an array, and this is " + typeName(given))

        const argv = []

        for (const a of given) {
            if (!$.isStr(a))
                fault("`spawn` takes its arguments as strings, and one of them is " + typeName(a))

            argv.push(a)
        }

        const options = childOptions(args.length > 2 ? args[2] : null, "spawn")

        if (procHost === null) noChildren("spawn")

        // **stdin is closed and the other two are inherited**, which is the interpreter's pair of
        // decisions: a child waiting on input nobody will type is a hang with nothing on screen,
        // and a worker's complaints belong wherever its supervisor's do.
        const stdio = ["ignore", "inherit", "inherit"]

        // **node's own channel in the fourth slot, not a plain pipe.** It writes the same
        // newline-delimited JSON on the same descriptor, so a child under the interpreter cannot
        // tell the difference -- and it is the only wire on this host a socket can cross.
        if (options.ipc) stdio.push("ipc")

        const environment = options.env === null ? { ...process.env } : { ...options.env }

        if (options.ipc) {
            environment[CHANNEL_VARIABLE] = String(CHANNEL_FD)
            environment[HOST_VARIABLE] = HOST_NAME
        }

        const settings = { stdio: stdio, env: environment }

        if (options.cwd !== "") settings.cwd = options.cwd

        let handle = null

        try {
            handle = procHost.children.spawn(command, argv, settings)
        } catch (e) {
            return $.obj([["ok", false],
                ["error", "cannot run `" + command + "`: " + (e && e.message ? e.message : String(e))]])
        }

        // **A SPAWN THAT FAILED IS ANSWERED AT ONCE HERE TOO, AND node MAKES THAT AWKWARD.**
        // node reports a program that is not there through an `error` event on the next tick,
        // where libuv answers `uv_spawn` on the spot -- so a caller would learn about a missing
        // program at two different times on the two back ends, and a supervisor written against
        // one would be wrong on the other. `pid` is `undefined` immediately for a child that did
        // not start, which is what makes the two agree; the listener is still attached, an
        // `error` event nobody is listening for being an exception that ends the program.
        if (handle.pid === undefined) {
            handle.on("error", () => {})

            return $.obj([["ok", false], ["error", "cannot run `" + command + "`: the program could not be started"]])
        }

        const slot = { handle: handle, gen: kidSlots.length + 1, pid: BigInt(handle.pid === undefined ? 0 : handle.pid),
            channel: options.ipc ? handle : null, node: true, child: true, peer: "", ipc: options.ipc,
            open: options.ipc, inbox: "", onMessage: null, onExit: null, settled: false,
            exited: null, resolve: null, exitAnswer: null }

        slot.exited = new Promise((done) => { slot.resolve = done })
        kidSlots.push(slot)

        // **A spawn that fails is reported through the promise here and through the answer in
        // the interpreter**, node telling a caller about a missing program one turn later. The
        // answer is still a result either way: what differs is only when it is known.
        handle.on("error", (e) => {
            if (slot.settled) return

            // **An `error` after the program started is not a program that would not start.** node
            // emits one for a write to the channel as well, and the exit and close that follow are
            // what settle the child.
            if (handle.pid !== undefined) return

            slot.settled = true
            slot.open = false
            slot.channel = null
            slot.resolve($.obj([["ok", false],
                ["error", "cannot run `" + command + "`: " + (e && e.message ? e.message : String(e))]]))
        })

        handle.on("exit", (code, signal) => {
            if (slot.settled) return

            slot.open = false

            const number = signal === null || signal === undefined ? null : signalNumber(signal)

            // **A signal is `null` and not zero**, zero being a status a program can exit with.
            // The channel is left READABLE and stops being writable, which is the interpreter's
            // rule: a child that writes a message and exits in the same breath is ordinary, and
            // the exit reaches this program first as often as not.
            slot.exitAnswer = $.obj([["status", $.i64(BigInt(code === null || code === undefined ? 0 : code))],
                ["signal", number === undefined || number === null ? null : $.i64(BigInt(number))]])
        })

        // **Resolved on `close`, not `exit`.** node fires `exit` the moment the process has
        // terminated, which can land before the last read of its stdio -- the IPC channel
        // included -- has been delivered: a worker that writes a message and exits in the same
        // breath is ordinary, and `exit` racing ahead of that last message is exactly the failure
        // the interpreter avoids by settling `exited` only once its own channel has drained.
        // `close` fires once every stdio stream on the child -- the channel among them -- has
        // itself closed, which is the same condition. A child that leaves the channel open (a
        // grandchild inheriting it) delays `close` here exactly as it delays the interpreter's
        // drain, so the two hosts still agree on when a worker with an open grandchild settles.
        handle.on("close", () => {
            if (slot.settled) return

            slot.settled = true

            const answer = slot.exitAnswer
            const told = slot.onExit

            slot.onExit = null
            slot.resolve($.obj([["ok", true], ["value", answer]]))

            if (told !== null) $.callback(told, [answer], "onExit")
        })

        if (options.ipc) {
            handle.on("message", (msg, socket) => nodeMessage(slot, msg, socket))
            handle.on("disconnect", () => { slot.open = false })
        }

        return $.obj([["ok", true], ["value", new $.SChild(kidSlots.length - 1, slot.gen)]])
    }

    B.$childSend = (...args) => {
        if (args.length < 2 || args.length > 3)
            fault("`send` takes one message and optionally a socket to pass on, and was given " +
                (args.length - 1) + (args.length === 2 ? " argument" : " arguments"))

        const slot = childOf(args[0], "send")

        // **The message is framed BEFORE the channel is looked at**, so a value that is not a
        // message is refused in `toJSON`'s words whether the child is alive or not.
        const text = framed(args[1])

        if (!slot.ipc)
            fault("this child was started without a channel -- `spawn` opens one where the options say `ipc: true`")

        const why = slot.settled ? "this child has exited" : "this channel is closed"

        if (args.length === 3) return sendWithSocket(slot, text, args[2], true, why)

        return writeMessage(slot, text, null, why)
    }

    B.$childKill = (...args) => {
        if (args.length < 1 || args.length > 2)
            fault("`kill` takes a signal or nothing at all, and was given " + (args.length - 1) +
                (args.length === 2 ? " argument" : " arguments"))

        const slot = childOf(args[0], "kill")
        const name = args.length === 2 ? args[1] : "SIGTERM"

        if (!$.isStr(name)) fault("`kill` takes a signal by name, and this is " + typeName(name))

        if (signalNumber(name) === undefined)
            fault("`" + name + "` is not a signal -- the ones a program may send are " + SENDABLE +
                ", SIGKILL and SIGSTOP")

        if (slot.settled) return $.obj([["ok", false], ["error", "this child has exited"]])

        try {
            slot.handle.kill(name)

            return $.obj([["ok", true], ["value", null]])
        } catch (e) {
            return $.obj([["ok", false],
                ["error", "this child could not be signalled: " + (e && e.message ? e.message : String(e))]])
        }
    }

    B.$childOnMessage = (...args) => {
        if (args.length !== 2)
            fault("`onMessage` takes a function to call, and was given " + (args.length - 1) +
                (args.length === 2 ? " argument" : " arguments"))

        const slot = childOf(args[0], "onMessage")

        slot.onMessage = wantChildHandler(args[1], "onMessage")

        if (!slot.node) takeLines(slot)

        return null
    }

    B.$childOnExit = (...args) => {
        if (args.length !== 2)
            fault("`onExit` takes a function to call, and was given " + (args.length - 1) +
                (args.length === 2 ? " argument" : " arguments"))

        const slot = childOf(args[0], "onExit")

        slot.onExit = wantChildHandler(args[1], "onExit")

        return null
    }

    B.$childPid = (v) => childOf(v, "pid").pid

    B.$childExited = (v) => childOf(v, "exited").exited

    // -- this program's own end ------------------------------------------------------------------

    let ownChannel = null

    // `channel()` -- this program's end of the channel it was started with, or `null`.
    //
    // **`null` rather than a fault, because a program may be run both ways**: the same file is a
    // worker under a supervisor and a script somebody typed the name of.
    B.channel = (...args) => {
        if (args.length !== 0)
            fault("`channel` takes nothing at all, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (ownChannel !== null) return new $.SChannel(0)
        if (procHost === null) return null

        // **Which host the parent is on comes out of the environment**, where it was put at the
        // spawn -- so a worker knows before it does anything whether a socket can go back up the
        // channel, and there is nothing to wait for.
        const parentHost = process.env[HOST_VARIABLE]
        const peer = parentHost === undefined || parentHost === null ? "" : parentHost

        // **node's own channel where a node parent opened one**, which is the wire a socket can
        // cross. A parent under the interpreter sets no `NODE_CHANNEL_FD`, so `process.send` is
        // not there and the descriptor is read directly instead -- messages either way, and a
        // socket only on the first.
        if (process.channel !== undefined && process.channel !== null &&
            typeof process.send === "function") {
            ownChannel = { channel: process, node: true, child: false, peer: peer, open: true,
                inbox: "", onMessage: null }

            process.on("message", (msg, socket) => nodeMessage(ownChannel, msg, socket))
            process.on("disconnect", () => {
                ownChannel.open = false
                ownChannel.channel = null
            })

            process.send({ "$slate": HOST_NAME })

            return new $.SChannel(0)
        }

        const named = process.env[CHANNEL_VARIABLE]

        if (named === undefined || named === null || named === "") return null

        if (!/^[0-9]+$/.test(named))
            fault("`" + CHANNEL_VARIABLE + "` names the channel's descriptor and holds `" + named +
                "`, which is not one")

        const pipe = new procHost.sockets.Socket({ fd: Number(named), readable: true, writable: true })

        ownChannel = { channel: pipe, node: false, child: false, peer: peer, open: true,
            inbox: "", onMessage: null }

        // **The channel keeps the program alive while it is open**, which is what a worker
        // waiting to be told something is -- and the channel ending, which is what the parent
        // going away looks like, is what lets it exit. node's rule and the interpreter's.
        readChannel(pipe, ownChannel, () => {
            ownChannel.open = false
            ownChannel.channel = null

            try {
                pipe.destroy()
            } catch (e) {
            }
        })

        // **And this program says what IT is, first thing**, the parent having no other way to
        // find out: it started a command, and what that command turned out to be is only
        // knowable from what it says.
        pipe.write(helloText(HOST_NAME) + "\n")

        return new $.SChannel(0)
    }

    const channelOf = (v, name) => {
        if (!(v instanceof $.SChannel))
            fault("`" + name + "` is something a channel does, and this is " + typeName(v))

        if (ownChannel === null)
            fault("this channel was opened by another program, and `" + name + "` needs this one's")

        return ownChannel
    }

    B.$channelSend = (...args) => {
        if (args.length < 2 || args.length > 3)
            fault("`send` takes one message and optionally a socket to pass on, and was given " +
                (args.length - 1) + (args.length === 2 ? " argument" : " arguments"))

        const slot = channelOf(args[0], "send")
        const text = framed(args[1])

        if (args.length === 3)
            return sendWithSocket(slot, text, args[2], false, "this channel is closed")

        return writeMessage(slot, text, null, "this channel is closed")
    }

    B.$channelOnMessage = (...args) => {
        if (args.length !== 2)
            fault("`onMessage` takes a function to call, and was given " + (args.length - 1) +
                (args.length === 2 ? " argument" : " arguments"))

        const slot = channelOf(args[0], "onMessage")

        slot.onMessage = wantChildHandler(args[1], "onMessage")

        if (!slot.node) takeLines(slot)

        return null
    }

    // -- what the machine and the command line say about this program ------------------------------

    // `cpus()` -- how many things this machine can really do at once.
    //
    // **node's `availableParallelism` first**, which is libuv's `uv_available_parallelism` and
    // therefore the very call the interpreter makes: it reads a cgroup quota and an affinity
    // mask, so a program in a container asks for the share it has rather than for the host's
    // whole processor count. `os.cpus().length` is the older answer and is what a node before
    // 19.4 has; a browser's is `navigator.hardwareConcurrency`, and a host with none of the
    // three can still do one thing at a time.
    // **A builtin taking nothing has no count to refuse**, the call rule reading a count as a
    // floor and zero being the floor already -- so these four simply ignore what they are given,
    // exactly as `wants(args, 0, ...)` does in the interpreter.
    B.cpus = () => {
        const system = procHost === null ? null : procHost.system
        const said = system !== null && typeof system.availableParallelism === "function"
            ? system.availableParallelism()
            : system !== null && typeof system.cpus === "function" ? system.cpus().length
            : typeof navigator !== "undefined" && typeof navigator.hardwareConcurrency === "number"
            ? navigator.hardwareConcurrency : 1

        return BigInt(said < 1 ? 1 : Math.floor(said))
    }

    // `pid()` -- the number the operating system knows THIS program by, `child.pid`'s own
    // question turned on the process asking it.
    //
    // **node's `process.pid`, and there is no substitute for it.** Nothing else here carries a
    // number the operating system assigned, so a browser -- which has no process of its own at
    // all -- answers `null` rather than inventing one: `channel()` already answers `null` for
    // "there is nothing to say" instead of refusing, and this is that same kind of absence.
    B.pid = () => {
        return typeof process !== "undefined" && typeof process.pid === "number"
            ? BigInt(process.pid) : null
    }

    // `execPath()` and `scriptPath()` -- what would have to be started to run this program again.
    //
    // **`process.argv` opens with exactly this pair**, which is the same fact the interpreter
    // keeps beside `args`: the executable and then the file it was given. A host with no command
    // line answers the empty string for both, and `slate:cluster` refuses to guess from it.
    B.execPath = () => {
        return typeof process !== "undefined" && Array.isArray(process.argv) &&
            typeof process.argv[0] === "string" ? process.argv[0] : ""
    }

    B.scriptPath = () => {
        return typeof process !== "undefined" && Array.isArray(process.argv) &&
            typeof process.argv[1] === "string" ? process.argv[1] : ""
    }

        // -- the HTTP/1.1 request parser -------------------------------------------------------------

        // **The id is an index and is never reused**, so a stale or invented one answers emptily
        // rather than reaching a live connection. A program may hold an integer it made up.
        const parsers = []

        // **The count is checked before the kind**, which is the interpreter's order and matters:
        // four type errors for one missing argument is the commonest way a diagnostic becomes noise.
        const wantParserArgs = (args, want, name, takes) => {
            if (args.length !== want)
                fault("`" + name + "` takes " + takes + ", and was given " + args.length +
                    (args.length === 1 ? " argument" : " arguments"))
        }

        const parserAt = (v, name) => {
            if (typeof Buffer === "undefined")
                fault("`" + name + "` needs a host with sockets, and this JavaScript host has none")

            if (!$.isInt(v)) fault("`" + name + "` takes a parser, and this is " + typeName(v))

            const p = parsers[Number(v)]

            return p === undefined || p === null ? null : p
        }

        const wantLimit = (v, name) => {
            if (!$.isInt(v)) fault("`" + name + "` takes its limits as numbers of bytes, and one of them is " + typeName(v))

            return Number(v)
        }

        const newParser = (streaming, headLimit, bodyLimit) => {
            parsers.push({
                streaming: streaming,
                headLimit: headLimit,
                bodyLimit: bodyLimit,
                buf: Buffer.alloc(0),
                done: [],
                parts: [],
                upgraded: null,
                stopped: false,
                state: "head",
                head: null,
                body: null,
                need: 0,
                chunked: false
            })

            return BigInt(parsers.length - 1)
        }

        // -- reading a head ---------------------------------------------------------------------------

        // A refusal, as the object `httpFeed` answers with.
        const httpRefusal = (status, message) => $.obj([["status", BigInt(status)], ["message", message]])

        // The tokens of a comma-separated header field, lower-cased and trimmed.
        const httpTokens = (value) => value.toLowerCase().split(",").map((t) => t.trim())

        // Whether a header name is one at all. **RFC 9110's `token`**, and a name outside it is a
        // request that was not HTTP -- a space before the colon is the oldest smuggling trick there
        // is.
        const httpName = /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/

        // What a head says, or the status that refuses it.
        //
        // **The head is ASCII by the grammar** and is read as latin1 rather than as UTF-8, which is
        // what keeps a byte that is not text out of the parse: every byte becomes exactly one
        // character and nothing is replaced.
        const readHead = (text) => {
            const lines = text.split("\r\n")
            const line = lines[0].split(" ")

            if (line.length !== 3) return { status: 400, message: "this is not a request line" }

            const method = line[0]
            const target = line[1]
            const version = line[2]

            if (!httpName.test(method)) return { status: 400, message: "this is not a method" }
            if (target.length === 0) return { status: 400, message: "this request line has no target" }

            if (version !== "HTTP/1.1" && version !== "HTTP/1.0")
                return { status: 400, message: "this server speaks HTTP/1.1 and HTTP/1.0, and this says " + version }

            const names = []
            const values = []
            let length = null
            let encoded = false
            let connection = []

            for (let i = 1; i < lines.length; i++) {
                const at = lines[i]

                if (at.length === 0) continue

                // **A continuation line is refused rather than joined.** Obsolete folding has been
                // forbidden since RFC 7230 and is a smuggling primitive of its own.
                if (at.startsWith(" ") || at.startsWith("\t"))
                    return { status: 400, message: "a header continued onto the next line, which is not allowed" }

                const cut = at.indexOf(":")

                if (cut < 1) return { status: 400, message: "this is not a header" }

                const name = at.slice(0, cut)

                if (!httpName.test(name)) return { status: 400, message: "`" + name + "` is not a header name" }

                const value = at.slice(cut + 1).trim()
                const lower = name.toLowerCase()

                if (lower === "content-length") {
                    // **A SECOND `Content-Length` IS THE CLASSIC SMUGGLING SHAPE**, and llhttp
                    // refuses it whatever the two say.
                    if (length !== null) return { status: 400, message: "this request has two `Content-Length` headers" }
                    if (!/^[0-9]+$/.test(value)) return { status: 400, message: "`Content-Length` is not a number" }

                    length = Number(value)
                } else if (lower === "transfer-encoding") {
                    const codings = httpTokens(value)

                    for (const coding of codings)
                        if (coding !== "chunked" && coding !== "identity")
                            return { status: 400, message: "this server reads `chunked` and no other transfer encoding, and this says " + coding }

                    if (codings[codings.length - 1] === "chunked") encoded = true
                } else if (lower === "connection") connection = connection.concat(httpTokens(value))

                names.push(name)
                values.push(value)
            }

            // **`Content-Length` BESIDE A `Transfer-Encoding` is the other half of the same
            // primitive**, one hop framing by the length and the next by the chunks.
            if (encoded && length !== null)
                return { status: 400, message: "this request has both a `Content-Length` and a `Transfer-Encoding`" }

            const keepAlive = version === "HTTP/1.1"
                ? !connection.includes("close")
                : connection.includes("keep-alive")

            return {
                method: method,
                target: target,
                names: names,
                values: values,
                keepAlive: keepAlive,
                upgrade: connection.includes("upgrade") || method === "CONNECT",
                length: length,
                chunked: encoded
            }
        }

        // -- what a program is handed -----------------------------------------------------------------

        const httpRequestObject = (head, body) => {
            const headers = new $.SObj()

            for (let i = 0; i < head.names.length; i++)
                headers.setName(head.names[i].toLowerCase(), head.values[i])

            const cut = head.target.indexOf("?")
            const entries = [
                ["method", head.method],
                ["path", cut < 0 ? head.target : head.target.slice(0, cut)],
                ["search", cut < 0 ? "" : head.target.slice(cut + 1)],
                ["headers", headers]
            ]

            if (body !== null) {
                // **`body` IS THE TEXT AND `bytes` IS WHAT ARRIVED**, and a body that is not UTF-8
                // makes the first `""` and leaves the second exact -- a PNG posted to a route is
                // otherwise the same value as a request with no body at all.
                let text = ""

                try {
                    text = new TextDecoder("utf-8", { fatal: true }).decode(body)
                } catch (e) {
                    text = ""
                }

                entries.push(["body", text])
                entries.push(["bytes", $.bytesOf(new Uint8Array(body))])
            }

            entries.push(["keepAlive", head.keepAlive])
            entries.push(["upgrade", head.upgrade])

            return $.obj(entries)
        }

        // -- feeding ------------------------------------------------------------------------------------

        // One message has finished. A whole-request parser queues the request; a streaming one has
        // already handed the head and the body over and says only that it is over.
        const httpFinished = (p) => {
            if (p.streaming) p.parts.push($.obj([["kind", "end"]]))
            else p.done.push(httpRequestObject(p.head, p.body === null ? Buffer.alloc(0) : p.body))

            p.head = null
            p.body = null
            p.state = "head"
            p.chunked = false
            p.need = 0
        }

        // Hand a piece of a body to a streaming parser's queue.
        const httpChunkPart = (piece) =>
            $.obj([["kind", "body"], ["chunk", $.bytesOf(new Uint8Array(piece))]])

        // Everything the buffer holds, as far as it goes. **Answers a refusal or nothing**, and
        // leaves whatever it could not use in `p.buf`.
        const httpAdvance = (p) => {
            for (;;) {
                if (p.stopped) return null

                if (p.state === "head") {
                    const end = p.buf.indexOf("\r\n\r\n", 0, "latin1")

                    if (end < 0) {
                        if (p.buf.length > p.headLimit)
                            return httpRefusal(431, "the head is larger than " + p.headLimit + " bytes")

                        return null
                    }

                    if (end + 4 > p.headLimit)
                        return httpRefusal(431, "the head is larger than " + p.headLimit + " bytes")

                    const head = readHead(p.buf.toString("latin1", 0, end))

                    if (head.status !== undefined) return httpRefusal(head.status, head.message)

                    p.buf = p.buf.subarray(end + 4)
                    p.head = head
                    p.body = p.streaming ? null : Buffer.alloc(0)

                    if (p.streaming) {
                        const kept = httpRequestObject(head, null)

                        kept.setName("kind", "head")
                        p.parts.push(kept)
                    }

                    // **An upgrade STOPS the parse where the HTTP stopped**, everything after it
                    // belonging to whatever protocol was upgraded to.
                    if (head.upgrade) {
                        p.stopped = true
                        httpFinished(p)

                        return null
                    }

                    if (head.chunked) {
                        p.state = "chunkSize"
                        p.chunked = true
                    } else if (head.length !== null && head.length > 0) {
                        if (!p.streaming && head.length > p.bodyLimit)
                            return httpRefusal(413, "the body is larger than " + p.bodyLimit + " bytes")

                        p.state = "body"
                        p.need = head.length
                    } else httpFinished(p)

                    continue
                }

                if (p.state === "body") {
                    if (p.buf.length === 0) return null

                    const take = Math.min(p.need, p.buf.length)
                    const piece = p.buf.subarray(0, take)

                    p.buf = p.buf.subarray(take)
                    p.need -= take

                    if (p.streaming) p.parts.push(httpChunkPart(piece))
                    else {
                        p.body = Buffer.concat([p.body, piece])

                        if (p.body.length > p.bodyLimit)
                            return httpRefusal(413, "the body is larger than " + p.bodyLimit + " bytes")
                    }

                    if (p.need === 0) httpFinished(p)

                    continue
                }

                if (p.state === "chunkSize") {
                    const end = p.buf.indexOf("\r\n", 0, "latin1")

                    if (end < 0) {
                        if (p.buf.length > p.headLimit)
                            return httpRefusal(400, "this chunk size is not one")

                        return null
                    }

                    // **The extensions after a `;` are read and thrown away**, which is what the
                    // grammar says to do with them.
                    const said = p.buf.toString("latin1", 0, end).split(";")[0].trim()

                    if (!/^[0-9a-fA-F]+$/.test(said)) return httpRefusal(400, "this chunk size is not one")

                    const size = parseInt(said, 16)

                    p.buf = p.buf.subarray(end + 2)

                    if (size === 0) {
                        p.state = "trailer"

                        continue
                    }

                    p.state = "chunk"
                    p.need = size

                    continue
                }

                if (p.state === "chunk") {
                    if (p.buf.length === 0) return null

                    const take = Math.min(p.need, p.buf.length)
                    const piece = p.buf.subarray(0, take)

                    p.buf = p.buf.subarray(take)
                    p.need -= take

                    if (p.streaming) p.parts.push(httpChunkPart(piece))
                    else {
                        p.body = Buffer.concat([p.body, piece])

                        if (p.body.length > p.bodyLimit)
                            return httpRefusal(413, "the body is larger than " + p.bodyLimit + " bytes")
                    }

                    if (p.need === 0) p.state = "chunkEnd"

                    continue
                }

                if (p.state === "chunkEnd") {
                    if (p.buf.length < 2) return null
                    if (p.buf.toString("latin1", 0, 2) !== "\r\n") return httpRefusal(400, "this chunk did not end where it said it would")

                    p.buf = p.buf.subarray(2)
                    p.state = "chunkSize"

                    continue
                }

                // The trailer, which ends at the blank line after the last chunk.
                const end = p.buf.indexOf("\r\n", 0, "latin1")

                if (end < 0) return null

                if (end === 0) {
                    p.buf = p.buf.subarray(2)

                    httpFinished(p)

                    continue
                }

                p.buf = p.buf.subarray(end + 2)
            }
        }

        // -- the eight names ----------------------------------------------------------------------------

        B.httpParser = (...args) => {
            wantParserArgs(args, 2, "httpParser", "a head limit and a body limit")

            if (typeof Buffer === "undefined")
                fault("`httpParser` needs a host with sockets, and this JavaScript host has none")

            return newParser(false, wantLimit(args[0], "httpParser"), wantLimit(args[1], "httpParser"))
        }

        B.httpStream = (...args) => {
            wantParserArgs(args, 1, "httpStream", "a head limit")

            if (typeof Buffer === "undefined")
                fault("`httpStream` needs a host with sockets, and this JavaScript host has none")

            return newParser(true, wantLimit(args[0], "httpStream"), Number.MAX_SAFE_INTEGER)
        }

        B.httpFeed = (...args) => {
            wantParserArgs(args, 2, "httpFeed", "a parser and some bytes")

            const v = args[0]
            const bytes = args[1]
            const p = parserAt(v, "httpFeed")

            if (p === null) return null

            const raw = $.bytesLike(bytes, "httpFeed")

            // **`httpUpgraded` counts bytes of the LAST feed**, so what was already buffered before
            // this one arrived does not count towards it.
            const held = p.buf.length

            p.buf = Buffer.concat([p.buf, Buffer.from(raw)])
            p.upgraded = null

            const before = p.buf.length
            const refused = httpAdvance(p)

            if (p.stopped && p.upgraded === null) {
                const consumed = before - p.buf.length

                p.upgraded = Math.max(0, consumed - held)
            }

            return refused
        }

        B.httpTake = (...args) => {
            wantParserArgs(args, 1, "httpTake", "a parser")

            const p = parserAt(args[0], "httpTake")

            if (p === null || p.done.length === 0) return null

            return p.done.shift()
        }

        B.httpTakePart = (...args) => {
            wantParserArgs(args, 1, "httpTakePart", "a parser")

            const p = parserAt(args[0], "httpTakePart")

            if (p === null || p.parts.length === 0) return null

            return p.parts.shift()
        }

        // **The peer has stopped sending**, so a request whose body ends at end-of-file completes.
        // A request never has one -- every framing here is a length or a set of chunks -- so this
        // finishes nothing and is here because the seam has it.
        B.httpFinish = (...args) => {
            wantParserArgs(args, 1, "httpFinish", "a parser")
            parserAt(args[0], "httpFinish")

            return null
        }

        // **Zero is representable, so a caller tests `!= null` and never truthiness.** A boundary at
        // the very start of a chunk would otherwise read as no upgrade at all.
        B.httpUpgraded = (...args) => {
            wantParserArgs(args, 1, "httpUpgraded", "a parser")

            const p = parserAt(args[0], "httpUpgraded")

            return p === null || p.upgraded === null ? null : BigInt(p.upgraded)
        }

        B.httpClose = (...args) => {
            wantParserArgs(args, 1, "httpClose", "a parser")

            if (parserAt(args[0], "httpClose") !== null) parsers[Number(args[0])] = null

            return null
        }

        // -- HTTP/2, the server's half ------------------------------------------------------------------

        const h2 = (() => {
            // RFC 7541 Appendix A, in order: an index of `n` names `STATIC[n - 1]`.
            const STATIC = [
                [":authority", ""], [":method", "GET"], [":method", "POST"], [":path", "/"],
                [":path", "/index.html"], [":scheme", "http"], [":scheme", "https"], [":status", "200"],
                [":status", "204"], [":status", "206"], [":status", "304"], [":status", "400"],
                [":status", "404"], [":status", "500"], ["accept-charset", ""],
                ["accept-encoding", "gzip, deflate"], ["accept-language", ""], ["accept-ranges", ""],
                ["accept", ""], ["access-control-allow-origin", ""], ["age", ""], ["allow", ""],
                ["authorization", ""], ["cache-control", ""], ["content-disposition", ""],
                ["content-encoding", ""], ["content-language", ""], ["content-length", ""],
                ["content-location", ""], ["content-range", ""], ["content-type", ""], ["cookie", ""],
                ["date", ""], ["etag", ""], ["expect", ""], ["expires", ""], ["from", ""], ["host", ""],
                ["if-match", ""], ["if-modified-since", ""], ["if-none-match", ""], ["if-range", ""],
                ["if-unmodified-since", ""], ["last-modified", ""], ["link", ""], ["location", ""],
                ["max-forwards", ""], ["proxy-authenticate", ""], ["proxy-authorization", ""],
                ["range", ""], ["referer", ""], ["refresh", ""], ["retry-after", ""], ["server", ""],
                ["set-cookie", ""], ["strict-transport-security", ""], ["transfer-encoding", ""],
                ["user-agent", ""], ["vary", ""], ["via", ""], ["www-authenticate", ""]
            ]

            // The static entries by what a field says: the index of a name and value together, and of
            // a name alone (the first entry that has it).
            const staticFull = new Map()
            const staticName = new Map()

            STATIC.forEach((e, i) => {
                if (e[1] !== "") staticFull.set(e[0] + "\u0000" + e[1], i + 1)
                if (!staticName.has(e[0])) staticName.set(e[0], i + 1)
            })

            // RFC 7541 Appendix B: the code of each byte and how many bits it is. The end-of-string
            // symbol is not here, so a stream that spells it falls off the tree and is refused.
            const HUFF_CODES = [
                0x1ff8, 0x7fffd8, 0xfffffe2, 0xfffffe3, 0xfffffe4, 0xfffffe5, 0xfffffe6, 0xfffffe7,
                0xfffffe8, 0xffffea, 0x3ffffffc, 0xfffffe9, 0xfffffea, 0x3ffffffd, 0xfffffeb, 0xfffffec,
                0xfffffed, 0xfffffee, 0xfffffef, 0xffffff0, 0xffffff1, 0xffffff2, 0x3ffffffe, 0xffffff3,
                0xffffff4, 0xffffff5, 0xffffff6, 0xffffff7, 0xffffff8, 0xffffff9, 0xffffffa, 0xffffffb,
                0x14, 0x3f8, 0x3f9, 0xffa, 0x1ff9, 0x15, 0xf8, 0x7fa,
                0x3fa, 0x3fb, 0xf9, 0x7fb, 0xfa, 0x16, 0x17, 0x18,
                0x0, 0x1, 0x2, 0x19, 0x1a, 0x1b, 0x1c, 0x1d,
                0x1e, 0x1f, 0x5c, 0xfb, 0x7ffc, 0x20, 0xffb, 0x3fc,
                0x1ffa, 0x21, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62,
                0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a,
                0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72,
                0xfc, 0x73, 0xfd, 0x1ffb, 0x7fff0, 0x1ffc, 0x3ffc, 0x22,
                0x7ffd, 0x3, 0x23, 0x4, 0x24, 0x5, 0x25, 0x26,
                0x27, 0x6, 0x74, 0x75, 0x28, 0x29, 0x2a, 0x7,
                0x2b, 0x76, 0x2c, 0x8, 0x9, 0x2d, 0x77, 0x78,
                0x79, 0x7a, 0x7b, 0x7ffe, 0x7fc, 0x3ffd, 0x1ffd, 0xffffffc,
                0xfffe6, 0x3fffd2, 0xfffe7, 0xfffe8, 0x3fffd3, 0x3fffd4, 0x3fffd5, 0x7fffd9,
                0x3fffd6, 0x7fffda, 0x7fffdb, 0x7fffdc, 0x7fffdd, 0x7fffde, 0xffffeb, 0x7fffdf,
                0xffffec, 0xffffed, 0x3fffd7, 0x7fffe0, 0xffffee, 0x7fffe1, 0x7fffe2, 0x7fffe3,
                0x7fffe4, 0x1fffdc, 0x3fffd8, 0x7fffe5, 0x3fffd9, 0x7fffe6, 0x7fffe7, 0xffffef,
                0x3fffda, 0x1fffdd, 0xfffe9, 0x3fffdb, 0x3fffdc, 0x7fffe8, 0x7fffe9, 0x1fffde,
                0x7fffea, 0x3fffdd, 0x3fffde, 0xfffff0, 0x1fffdf, 0x3fffdf, 0x7fffeb, 0x7fffec,
                0x1fffe0, 0x1fffe1, 0x3fffe0, 0x1fffe2, 0x7fffed, 0x3fffe1, 0x7fffee, 0x7fffef,
                0xfffea, 0x3fffe2, 0x3fffe3, 0x3fffe4, 0x7ffff0, 0x3fffe5, 0x3fffe6, 0x7ffff1,
                0x3ffffe0, 0x3ffffe1, 0xfffeb, 0x7fff1, 0x3fffe7, 0x7ffff2, 0x3fffe8, 0x1ffffec,
                0x3ffffe2, 0x3ffffe3, 0x3ffffe4, 0x7ffffde, 0x7ffffdf, 0x3ffffe5, 0xfffff1, 0x1ffffed,
                0x7fff2, 0x1fffe3, 0x3ffffe6, 0x7ffffe0, 0x7ffffe1, 0x3ffffe7, 0x7ffffe2, 0xfffff2,
                0x1fffe4, 0x1fffe5, 0x3ffffe8, 0x3ffffe9, 0xffffffd, 0x7ffffe3, 0x7ffffe4, 0x7ffffe5,
                0xfffec, 0xfffff3, 0xfffed, 0x1fffe6, 0x3fffe9, 0x1fffe7, 0x1fffe8, 0x7ffff3,
                0x3fffea, 0x3fffeb, 0x1ffffee, 0x1ffffef, 0xfffff4, 0xfffff5, 0x3ffffea, 0x7ffff4,
                0x3ffffeb, 0x7ffffe6, 0x3ffffec, 0x3ffffed, 0x7ffffe7, 0x7ffffe8, 0x7ffffe9, 0x7ffffea,
                0x7ffffeb, 0xffffffe, 0x7ffffec, 0x7ffffed, 0x7ffffee, 0x7ffffef, 0x7fffff0, 0x3ffffee
            ]

            const HUFF_LENS = [
                13, 23, 28, 28, 28, 28, 28, 28, 28, 24, 30, 28, 28, 30, 28, 28,
                28, 28, 28, 28, 28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 28,
                6, 10, 10, 12, 13, 6, 8, 11, 10, 10, 8, 11, 8, 6, 6, 6,
                5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 7, 8, 15, 6, 12, 10,
                13, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
                7, 7, 7, 7, 7, 7, 7, 7, 8, 7, 8, 13, 19, 13, 14, 6,
                15, 5, 6, 5, 6, 5, 6, 6, 6, 5, 7, 7, 6, 6, 6, 5,
                6, 7, 6, 5, 5, 6, 7, 7, 7, 7, 7, 15, 11, 14, 13, 28,
                20, 22, 20, 20, 22, 22, 22, 23, 22, 23, 23, 23, 23, 23, 24, 23,
                24, 24, 22, 23, 24, 23, 23, 23, 23, 21, 22, 23, 22, 23, 23, 24,
                22, 21, 20, 22, 22, 23, 23, 21, 23, 22, 22, 24, 21, 22, 23, 23,
                21, 21, 22, 21, 23, 22, 23, 23, 20, 22, 22, 22, 23, 22, 22, 23,
                26, 26, 20, 19, 22, 23, 22, 25, 26, 26, 26, 27, 27, 26, 24, 25,
                19, 21, 26, 27, 27, 26, 27, 24, 21, 21, 26, 26, 28, 27, 27, 27,
                20, 24, 20, 21, 22, 21, 21, 23, 22, 22, 25, 25, 24, 24, 26, 23,
                26, 27, 26, 26, 27, 27, 27, 27, 27, 28, 27, 27, 27, 27, 27, 26
            ]

            // The code as a binary tree: an inner node is `[zero, one]` and a leaf is its byte.
            const huffRoot = [undefined, undefined]

            HUFF_CODES.forEach((code, sym) => {
                let n = huffRoot

                for (let b = HUFF_LENS[sym] - 1; b > 0; b--) {
                    const bit = (code >>> b) & 1

                    if (n[bit] === undefined) n[bit] = [undefined, undefined]

                    n = n[bit]
                }

                n[code & 1] = sym
            })

            // What a peer got wrong, as the answer `h2Receive` gives.
            class H2Error extends Error {}

            const refuse = (message) => { throw new H2Error(message) }

            const huffDecode = (buf) => {
                const out = []
                let node = huffRoot
                let bits = 0
                let ones = true

                for (const byte of buf) {
                    for (let i = 7; i >= 0; i--) {
                        const bit = (byte >> i) & 1

                        node = node[bit]

                        if (node === undefined) refuse("a header block was not valid HPACK: bad Huffman code")

                        bits++

                        if (bit === 0) ones = false

                        if (typeof node === "number") {
                            out.push(node)

                            node = huffRoot
                            bits = 0
                            ones = true
                        }
                    }
                }

                // What is left over is padding, which is the start of the end-of-string code: fewer than
                // eight bits and every one of them set.
                if (bits > 7 || !ones) refuse("a header block was not valid HPACK: bad Huffman padding")

                return Buffer.from(out)
            }

            // An HPACK integer with a `prefix`-bit prefix, as `[value, next position]`.
            const readInt = (buf, pos, prefix) => {
                const max = (1 << prefix) - 1

                if (pos >= buf.length) refuse("a header block was not valid HPACK: it ended early")

                let value = buf[pos++] & max

                if (value < max) return [value, pos]

                let shift = 0

                for (;;) {
                    if (pos >= buf.length) refuse("a header block was not valid HPACK: it ended early")

                    const b = buf[pos++]

                    value += (b & 0x7f) * Math.pow(2, shift)
                    shift += 7

                    if (shift > 35) refuse("a header block was not valid HPACK: an integer is too large")

                    if ((b & 0x80) === 0) return [value, pos]
                }
            }

            // A string literal, as a latin1 string of its bytes and the next position.
            const readString = (buf, pos) => {
                const huffman = pos < buf.length && (buf[pos] & 0x80) !== 0
                const [len, at] = readInt(buf, pos, 7)

                if (at + len > buf.length) refuse("a header block was not valid HPACK: a string ran past its end")

                const raw = buf.subarray(at, at + len)

                return [(huffman ? huffDecode(raw) : raw).toString("latin1"), at + len]
            }

            // The peer's header table, with the size rule that evicts the oldest.
            class Decoder {
                constructor() {
                    this.table = []
                    this.size = 0
                    this.max = 4096
                    this.limit = 4096
                }

                evict(room) {
                    while (this.size > room && this.table.length > 0) {
                        const old = this.table.pop()

                        this.size -= old[0].length + old[1].length + 32
                    }
                }

                add(name, value) {
                    const cost = name.length + value.length + 32

                    if (cost > this.max) {
                        this.table = []
                        this.size = 0

                        return
                    }

                    this.evict(this.max - cost)
                    this.table.unshift([name, value])
                    this.size += cost
                }

                lookup(i) {
                    if (i === 0) refuse("a header block was not valid HPACK: index zero")
                    if (i <= STATIC.length) return STATIC[i - 1]

                    const e = this.table[i - STATIC.length - 1]

                    if (e === undefined) refuse("a header block was not valid HPACK: index " + i + " is not in the table")

                    return e
                }

                // A whole header block, as `[name, value]` pairs of text.
                decode(buf) {
                    const fields = []
                    let pos = 0

                    while (pos < buf.length) {
                        const b = buf[pos]

                        if ((b & 0x80) !== 0) {
                            const [i, next] = readInt(buf, pos, 7)

                            pos = next
                            fields.push(this.lookup(i))
                        } else if ((b & 0x20) !== 0 && (b & 0x40) === 0) {
                            const [size, next] = readInt(buf, pos, 5)

                            pos = next

                            if (size > this.limit) refuse("a header block was not valid HPACK: the table was resized past its limit")

                            this.max = size
                            this.evict(size)
                        } else {
                            const indexed = (b & 0x40) !== 0
                            const [i, next] = readInt(buf, pos, indexed ? 6 : 4)

                            pos = next

                            let name

                            if (i > 0) {
                                name = this.lookup(i)[0]
                            } else {
                                const [n, after] = readString(buf, pos)

                                name = n
                                pos = after
                            }

                            const [value, after] = readString(buf, pos)

                            pos = after

                            if (indexed) this.add(name, value)

                            fields.push([name, value])
                        }
                    }

                    return fields.map(([n, v]) => [n, Buffer.from(v, "latin1").toString("utf8")])
                }
            }

            // An HPACK integer written with `prefix` bits under `flags`.
            const putInt = (out, flags, prefix, value) => {
                const max = (1 << prefix) - 1

                if (value < max) {
                    out.push(flags | value)

                    return
                }

                out.push(flags | max)

                value -= max

                while (value >= 128) {
                    out.push((value & 0x7f) | 0x80)

                    value = Math.floor(value / 128)
                }

                out.push(value)
            }

            // A header block, with nothing indexed.
            const encodeFields = (fields) => {
                const out = []

                for (const [name, value, sensitive] of fields) {
                    const whole = staticFull.get(name + "\u0000" + value)

                    if (whole !== undefined && !sensitive) {
                        putInt(out, 0x80, 7, whole)

                        continue
                    }

                    const flags = sensitive ? 0x10 : 0x00
                    const named = staticName.get(name)

                    if (named !== undefined) {
                        putInt(out, flags, 4, named)
                    } else {
                        out.push(flags)

                        const bytes = Buffer.from(name, "utf8")

                        putInt(out, 0, 7, bytes.length)

                        for (const byte of bytes) out.push(byte)
                    }

                    const bytes = Buffer.from(value, "utf8")

                    putInt(out, 0, 7, bytes.length)

                    for (const byte of bytes) out.push(byte)
                }

                return Buffer.from(out)
            }

            // -- frames --------------------------------------------------------------------------------------

            const DATA = 0, HEADERS = 1, PRIORITY = 2, RST_STREAM = 3, SETTINGS = 4, PUSH_PROMISE = 5
            const PING = 6, GOAWAY = 7, WINDOW_UPDATE = 8, CONTINUATION = 9
            const END_STREAM = 1, ACK = 1, END_HEADERS = 4, PADDED = 8, PRIORITY_FLAG = 32

            const PREFACE = Buffer.from("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n", "latin1")

            // The size of a frame this side accepts: the protocol's default, which it never raises.
            const MAX_FRAME = 16384

            // Flow-control credit is given back in lumps of this size rather than frame by frame.
            const CREDIT_LUMP = 16384

            const frame = (type, flags, stream, payload) => {
                const head = Buffer.alloc(9)

                head.writeUIntBE(payload.length, 0, 3)
                head[3] = type
                head[4] = flags
                head.writeUInt32BE(stream, 5)

                return payload.length === 0 ? head : Buffer.concat([head, payload])
            }

            const u32 = (n) => {
                const b = Buffer.alloc(4)

                b.writeUInt32BE(n, 0)

                return b
            }

            class Session {
                constructor(auto) {
                    this.auto = auto
                    this.inbuf = Buffer.alloc(0)
                    this.prefaced = false
                    this.out = []
                    this.events = []
                    this.streams = new Map()
                    this.pending = new Set()
                    this.dec = new Decoder()
                    this.sendWin = 65535
                    this.peerWin = 65535
                    this.peerFrame = 16384
                    this.connCredit = 0
                    this.continuing = null
                    this.lastStream = 0
                    this.closed = false

                    // The server's own SETTINGS go first, and an empty one is every default.
                    this.out.push(frame(SETTINGS, 0, 0, Buffer.alloc(0)))
                }

                // -- reading -------------------------------------------------------------------------------

                // Bytes in. Answers `null`, or the sentence for what the peer got wrong.
                receive(chunk) {
                    this.inbuf = this.inbuf.length === 0 ? Buffer.from(chunk) : Buffer.concat([this.inbuf, chunk])

                    try {
                        this.pump()
                    } catch (e) {
                        if (e instanceof H2Error) return e.message

                        throw e
                    }

                    return null
                }

                pump() {
                    if (!this.prefaced) {
                        const n = Math.min(this.inbuf.length, PREFACE.length)

                        if (!this.inbuf.subarray(0, n).equals(PREFACE.subarray(0, n)))
                            refuse("the connection did not begin with the HTTP/2 preface")

                        if (n < PREFACE.length) return

                        this.inbuf = this.inbuf.subarray(PREFACE.length)
                        this.prefaced = true
                    }

                    for (;;) {
                        if (this.inbuf.length < 9) return

                        const len = this.inbuf.readUIntBE(0, 3)

                        if (len > MAX_FRAME) refuse("a frame of " + len + " bytes is larger than the " + MAX_FRAME + " this side accepts")

                        if (this.inbuf.length < 9 + len) return

                        const type = this.inbuf[3]
                        const flags = this.inbuf[4]
                        const stream = this.inbuf.readUInt32BE(5) & 0x7fffffff
                        const payload = this.inbuf.subarray(9, 9 + len)

                        this.inbuf = this.inbuf.subarray(9 + len)
                        this.take(type, flags, stream, payload)
                    }
                }

                take(type, flags, stream, payload) {
                    if (this.continuing !== null && (type !== CONTINUATION || stream !== this.continuing.stream))
                        refuse("a header block was interrupted by another frame")

                    switch (type) {
                        case DATA: return this.takeData(flags, stream, payload)
                        case HEADERS: return this.takeHeaders(flags, stream, payload)
                        case CONTINUATION: return this.takeContinuation(flags, stream, payload)
                        case PRIORITY: return
                        case RST_STREAM: return this.takeReset(stream, payload)
                        case SETTINGS: return this.takeSettings(flags, stream, payload)
                        case PUSH_PROMISE: refuse("a client may not push")
                        case PING: return this.takePing(flags, stream, payload)
                        case GOAWAY: return this.takeGoaway(stream, payload)
                        case WINDOW_UPDATE: return this.takeWindow(stream, payload)
                        default: return
                    }
                }

                // A frame's payload without its padding.
                unpadded(flags, payload) {
                    if ((flags & PADDED) === 0) return [payload, 0]

                    if (payload.length < 1) refuse("a padded frame has no padding length")

                    const pad = payload[0]

                    if (pad >= payload.length) refuse("a frame is padded past its own length")

                    return [payload.subarray(1, payload.length - pad), pad + 1]
                }

                takeData(flags, stream, payload) {
                    if (stream === 0) refuse("DATA on stream zero")

                    const [data, padding] = this.unpadded(flags, payload)
                    const s = this.streams.get(stream)

                    // Padding is not something the program reads, so its credit goes straight back.
                    this.credit(s, padding, true)

                    if (s === undefined) {
                        if (stream > this.lastStream) refuse("DATA on a stream that was never opened")

                        this.credit(undefined, data.length, false)

                        return
                    }

                    if (s.recvEnded) refuse("DATA on a stream the peer had ended")

                    if (data.length > 0) {
                        this.events.push({ kind: "data", stream: stream, bytes: new Uint8Array(data) })

                        if (this.auto) this.consume(stream, data.length)
                    }

                    if ((flags & END_STREAM) !== 0) this.ended(s)
                }

                takeHeaders(flags, stream, payload) {
                    if (stream === 0) refuse("HEADERS on stream zero")

                    let [block] = this.unpadded(flags, payload)

                    if ((flags & PRIORITY_FLAG) !== 0) {
                        if (block.length < 5) refuse("a HEADERS frame is too short for its priority")

                        block = block.subarray(5)
                    }

                    if ((flags & END_HEADERS) === 0) {
                        this.continuing = { stream: stream, flags: flags, parts: [block] }

                        return
                    }

                    this.headed(stream, flags, block)
                }

                takeContinuation(flags, stream, payload) {
                    if (this.continuing === null) refuse("a CONTINUATION with no header block to continue")

                    this.continuing.parts.push(payload)

                    if ((flags & END_HEADERS) === 0) return

                    const held = this.continuing

                    this.continuing = null
                    this.headed(stream, held.flags, Buffer.concat(held.parts))
                }

                // A whole header block has arrived: a request, or the trailers of one.
                headed(stream, flags, block) {
                    const fields = this.dec.decode(block)
                    const known = this.streams.get(stream)

                    if (known !== undefined) {
                        if (known.recvEnded) refuse("HEADERS on a stream the peer had ended")

                        this.events.push({ kind: "headers", stream: stream, headers: fields, of: "trailer" })

                        if ((flags & END_STREAM) !== 0) this.ended(known)

                        return
                    }

                    if (stream % 2 === 0 || stream <= this.lastStream)
                        refuse("a request opened stream " + stream + ", which a client may not use")

                    this.lastStream = stream

                    const s = {
                        id: stream,
                        recvEnded: false,
                        sentEnded: false,
                        headSent: false,
                        finishing: false,
                        trailers: null,
                        queue: [],
                        sendWin: this.peerWin,
                        credit: 0,
                        closed: false
                    }

                    this.streams.set(stream, s)
                    this.events.push({ kind: "headers", stream: stream, headers: fields, of: "request" })

                    if ((flags & END_STREAM) !== 0) this.ended(s)
                }

                // The peer will send this stream no more.
                ended(s) {
                    s.recvEnded = true

                    this.events.push({ kind: "streamEnd", stream: s.id })
                    this.settle(s)
                }

                // Both halves of a stream are over: it goes, and the program is told.
                settle(s) {
                    if (s.recvEnded && s.sentEnded) this.drop(s, 0)
                }

                drop(s, code) {
                    if (s.closed) return

                    s.closed = true
                    s.queue = []

                    this.streams.delete(s.id)
                    this.pending.delete(s)
                    this.events.push({ kind: "streamClose", stream: s.id, code: code })
                }

                takeReset(stream, payload) {
                    if (stream === 0) refuse("RST_STREAM on stream zero")
                    if (payload.length !== 4) refuse("an RST_STREAM that is not four bytes")

                    const s = this.streams.get(stream)

                    if (s === undefined) return

                    this.events.push({ kind: "rstStream", stream: stream, code: payload.readUInt32BE(0) })
                    this.drop(s, payload.readUInt32BE(0))
                }

                takeSettings(flags, stream, payload) {
                    if (stream !== 0) refuse("SETTINGS on a stream")

                    if ((flags & ACK) !== 0) {
                        if (payload.length !== 0) refuse("a SETTINGS acknowledgement with a payload")

                        return
                    }

                    if (payload.length % 6 !== 0) refuse("a SETTINGS frame that is not whole entries")

                    for (let at = 0; at < payload.length; at += 6) {
                        const id = payload.readUInt16BE(at)
                        const value = payload.readUInt32BE(at + 2)

                        if (id === 4) {
                            if (value > 0x7fffffff) refuse("an initial window larger than the protocol allows")

                            const delta = value - this.peerWin

                            this.peerWin = value

                            for (const s of this.streams.values()) s.sendWin += delta
                        } else if (id === 5) {
                            if (value < 16384 || value > 16777215) refuse("a maximum frame size outside the protocol's range")

                            this.peerFrame = value
                        }
                    }

                    this.out.push(frame(SETTINGS, ACK, 0, Buffer.alloc(0)))
                    this.events.push({ kind: "settings" })
                }

                takePing(flags, stream, payload) {
                    if (stream !== 0) refuse("PING on a stream")
                    if (payload.length !== 8) refuse("a PING that is not eight bytes")

                    const ack = (flags & ACK) !== 0

                    if (!ack) this.out.push(frame(PING, ACK, 0, Buffer.from(payload)))

                    this.events.push({ kind: "ping", ack: ack })
                }

                takeGoaway(stream, payload) {
                    if (stream !== 0) refuse("GOAWAY on a stream")
                    if (payload.length < 8) refuse("a GOAWAY that is too short")

                    this.events.push({
                        kind: "goaway",
                        lastStream: payload.readUInt32BE(0) & 0x7fffffff,
                        code: payload.readUInt32BE(4)
                    })
                }

                takeWindow(stream, payload) {
                    if (payload.length !== 4) refuse("a WINDOW_UPDATE that is not four bytes")

                    const by = payload.readUInt32BE(0) & 0x7fffffff

                    if (by === 0) refuse("a WINDOW_UPDATE of nothing")

                    if (stream === 0) {
                        this.sendWin += by

                        if (this.sendWin > 0x7fffffff) refuse("a connection window past the protocol's limit")
                    } else {
                        const s = this.streams.get(stream)

                        if (s === undefined) return

                        s.sendWin += by

                        if (s.sendWin > 0x7fffffff) {
                            this.out.push(frame(RST_STREAM, 0, stream, u32(3)))
                            this.drop(s, 3)

                            return
                        }
                    }

                    this.events.push({ kind: "windowUpdate", stream: stream, increment: by })
                }

                // -- flow control received ----------------------------------------------------------------

                // Credit `n` bytes back to the peer: the connection's, and the stream's where it is still
                // sending. **Lumps, not frames**, so a body arriving in sixteen-kilobyte DATA frames is
                // not answered by a WINDOW_UPDATE per frame.
                credit(s, n, immediate) {
                    if (n === 0) return

                    this.connCredit += n

                    if (immediate || this.connCredit >= CREDIT_LUMP) {
                        this.out.push(frame(WINDOW_UPDATE, 0, 0, u32(this.connCredit)))
                        this.connCredit = 0
                    }

                    if (s === undefined || s.recvEnded) return

                    s.credit += n

                    if (immediate || s.credit >= CREDIT_LUMP) {
                        this.out.push(frame(WINDOW_UPDATE, 0, s.id, u32(s.credit)))
                        s.credit = 0
                    }
                }

                consume(stream, n) {
                    this.credit(this.streams.get(stream), n, false)
                }

                // -- writing -------------------------------------------------------------------------------

                // A header block as a HEADERS frame and the CONTINUATIONs it needs.
                headFrames(stream, block, endStream) {
                    const size = this.peerFrame
                    let first = true

                    for (let at = 0; first || at < block.length; at += size) {
                        const part = block.subarray(at, at + size)
                        const last = at + size >= block.length

                        if (first) {
                            this.out.push(frame(HEADERS, (last ? END_HEADERS : 0) | (endStream ? END_STREAM : 0), stream, part))
                            first = false
                        } else {
                            this.out.push(frame(CONTINUATION, last ? END_HEADERS : 0, stream, part))
                        }
                    }
                }

                open(stream, name) {
                    const s = this.streams.get(stream)

                    if (s === undefined || s.closed) fault("`" + name + "` was given stream " + stream + ", which is not open")

                    return s
                }

                respond(stream, fields, body, whole) {
                    const s = this.open(stream, whole ? "h2Respond" : "h2RespondStream")

                    if (s.headSent) fault("stream " + stream + " has already been answered")

                    s.headSent = true

                    const ends = whole && body.length === 0

                    this.headFrames(stream, encodeFields(fields), ends)

                    if (ends) {
                        s.sentEnded = true
                        this.settle(s)

                        return
                    }

                    if (whole) {
                        s.queue.push(body)
                        s.finishing = true
                        this.pending.add(s)
                    }
                }

                push(stream, piece) {
                    const s = this.streams.get(stream)

                    if (s === undefined || s.closed) return "stream " + stream + " is closed"
                    if (!s.headSent) return "stream " + stream + " has no head yet"
                    if (s.finishing) return "stream " + stream + " has already been finished"

                    if (piece.length > 0) {
                        s.queue.push(piece)
                        this.pending.add(s)
                    }

                    return null
                }

                finish(stream, trailers) {
                    const s = this.streams.get(stream)

                    if (s === undefined || s.closed) return "stream " + stream + " is closed"
                    if (!s.headSent) return "stream " + stream + " has no head yet"
                    if (s.finishing) return "stream " + stream + " has already been finished"

                    s.finishing = true
                    s.trailers = trailers === null ? null : encodeFields(trailers)
                    this.pending.add(s)

                    return null
                }

                goaway(last, code) {
                    const body = Buffer.alloc(8)

                    body.writeUInt32BE(last, 0)
                    body.writeUInt32BE(code, 4)
                    this.out.push(frame(GOAWAY, 0, 0, body))
                }

                // Every queued body that the windows allow, as DATA frames.
                flush() {
                    for (const s of this.pending) {
                        while (s.queue.length > 0 && s.sendWin > 0 && this.sendWin > 0) {
                            const head = s.queue[0]
                            const n = Math.min(head.length, s.sendWin, this.sendWin, this.peerFrame)
                            const piece = n === head.length ? head : head.subarray(0, n)

                            if (n === head.length) s.queue.shift()
                            else s.queue[0] = head.subarray(n)

                            s.sendWin -= n
                            this.sendWin -= n

                            const last = s.queue.length === 0 && s.finishing && s.trailers === null

                            this.out.push(frame(DATA, last ? END_STREAM : 0, s.id, Buffer.from(piece)))

                            if (last) {
                                s.sentEnded = true

                                break
                            }
                        }

                        if (s.queue.length === 0 && s.finishing && !s.sentEnded) {
                            if (s.trailers !== null) this.headFrames(s.id, s.trailers, true)
                            else this.out.push(frame(DATA, END_STREAM, s.id, Buffer.alloc(0)))

                            s.sentEnded = true
                        }

                        if (s.queue.length === 0) {
                            this.pending.delete(s)
                            this.settle(s)
                        }
                    }
                }

                send() {
                    this.flush()

                    const out = this.out.length === 0 ? Buffer.alloc(0) : Buffer.concat(this.out)

                    this.out = []

                    return out
                }
            }

            return { Session, H2Error }
        })()


        const h2Sessions = []

        const h2At = (v, name) => {
            if (!$.isInt(v)) fault("`" + name + "` takes a session, and this is " + typeName(v))

            const s = h2Sessions[Number(v)]

            if (s === undefined || s === null) fault("`" + name + "` was given a session that is closed or was never opened")

            return s
        }

        const h2Count = (args, low, high, name, what) => {
            if (args.length < low || args.length > high)
                fault("`" + name + "` takes " + what + ", and was given " + args.length + " argument" + (args.length === 1 ? "" : "s"))
        }

        const h2Stream = (v, name) => {
            if (!$.isInt(v) || Number(v) < 1) fault("`" + name + "` takes a stream number, and this is " + typeName(v))

            return Number(v)
        }

        // Headers as an object or as pairs, as `[name, value, sensitive]`, names lower-cased.
        const h2Fields = (v, name) => {
            const pairs = []

            if (v instanceof $.SObj) {
                for (const [k, x] of v.fields.values()) pairs.push([k, x])
            } else if (Array.isArray(v)) {
                for (const p of v) {
                    if (!Array.isArray(p) || p.length < 2) fault("`" + name + "` takes headers as an object or as [name, value] pairs")

                    pairs.push(p)
                }
            } else {
                fault("`" + name + "` takes headers as an object or as [name, value] pairs, and this is " + typeName(v))
            }

            return pairs.map((p) => {
                if (!$.isStr(p[0])) fault("a header name is text")
                if (!$.isStr(p[1])) fault("a header value is text")

                return [p[0].toLowerCase(), p[1], p.length > 2 && p[2] === true]
            })
        }

        // A body as bytes, text crossing as its UTF-8; `undefined` and `null` are no body.
        const h2Body = (v, name) => {
            if (v === undefined || v === null) return Buffer.alloc(0)
            if ($.isStr(v)) return Buffer.from(v, "utf8")

            return Buffer.from($.bytesLike(v, name))
        }

        const h2Refusal = (message) => $.obj([["error", message]])

        const h2NeedSockets = (name) => {
            if (typeof Buffer === "undefined")
                fault("`" + name + "` needs a host with sockets, and this JavaScript host has none")
        }

        B.h2Server = (...args) => {
            h2Count(args, 0, 1, "h2Server", "an optional object of options")
            h2NeedSockets("h2Server")

            let auto = true

            if (args.length === 1) {
                if (!(args[0] instanceof $.SObj)) fault("`h2Server` takes an optional object of options, and this is " + typeName(args[0]))

                const option = args[0].getKey("autoWindowUpdate")

                if (option !== undefined) {
                    if (typeof option !== "boolean") fault("`autoWindowUpdate` is true or false, and this is " + typeName(option))

                    auto = option
                }
            }

            h2Sessions.push(new h2.Session(auto))

            return BigInt(h2Sessions.length - 1)
        }

        B.h2Receive = (...args) => {
            h2Count(args, 2, 2, "h2Receive", "a session and some bytes")

            const s = h2At(args[0], "h2Receive")
            const said = s.receive(Buffer.from($.bytesLike(args[1], "h2Receive")))

            return said === null ? null : h2Refusal(said)
        }

        B.h2Send = (...args) => {
            h2Count(args, 1, 1, "h2Send", "a session")

            return $.bytesOf(new Uint8Array(h2At(args[0], "h2Send").send()))
        }

        B.h2Next = (...args) => {
            h2Count(args, 1, 1, "h2Next", "a session")

            const e = h2At(args[0], "h2Next").events.shift()

            if (e === undefined) return null

            const fields = [["kind", e.kind]]

            if (e.stream !== undefined) fields.push(["stream", BigInt(e.stream)])
            if (e.headers !== undefined) fields.push(["headers", e.headers.map((h) => [h[0], h[1]])], ["of", e.of])
            if (e.bytes !== undefined) fields.push(["bytes", $.bytesOf(e.bytes)])
            if (e.code !== undefined) fields.push(["code", BigInt(e.code)])
            if (e.lastStream !== undefined) fields.push(["lastStream", BigInt(e.lastStream)])
            if (e.increment !== undefined) fields.push(["increment", BigInt(e.increment)])
            if (e.ack !== undefined) fields.push(["ack", e.ack])

            return $.obj(fields)
        }

        B.h2Respond = (...args) => {
            h2Count(args, 3, 4, "h2Respond", "a session, a stream, the headers and an optional body")

            const s = h2At(args[0], "h2Respond")

            s.respond(h2Stream(args[1], "h2Respond"), h2Fields(args[2], "h2Respond"), h2Body(args[3], "h2Respond"), true)

            return null
        }

        B.h2RespondStream = (...args) => {
            h2Count(args, 3, 3, "h2RespondStream", "a session, a stream and the headers")

            const s = h2At(args[0], "h2RespondStream")

            s.respond(h2Stream(args[1], "h2RespondStream"), h2Fields(args[2], "h2RespondStream"), Buffer.alloc(0), false)

            return null
        }

        B.h2Push = (...args) => {
            h2Count(args, 3, 3, "h2Push", "a session, a stream and a piece of the body")

            const s = h2At(args[0], "h2Push")
            const said = s.push(h2Stream(args[1], "h2Push"), h2Body(args[2], "h2Push"))

            return said === null ? null : h2Refusal(said)
        }

        B.h2Finish = (...args) => {
            h2Count(args, 2, 3, "h2Finish", "a session, a stream and optional trailers")

            const s = h2At(args[0], "h2Finish")
            const trailers = args[2] === undefined || args[2] === null ? null : h2Fields(args[2], "h2Finish")
            const said = s.finish(h2Stream(args[1], "h2Finish"), trailers)

            return said === null ? null : h2Refusal(said)
        }

        B.h2Goaway = (...args) => {
            h2Count(args, 2, 3, "h2Goaway", "a session, the last stream and an optional code")

            const s = h2At(args[0], "h2Goaway")

            if (!$.isInt(args[1])) fault("`h2Goaway` takes the last stream as a number, and this is " + typeName(args[1]))

            const code = args[2] === undefined ? 0n : args[2]

            if (!$.isInt(code)) fault("`h2Goaway` takes its code as a number, and this is " + typeName(code))

            s.goaway(Number(args[1]), Number(code))

            return null
        }

        B.h2Consume = (...args) => {
            h2Count(args, 3, 3, "h2Consume", "a session, a stream and a number of bytes")

            const s = h2At(args[0], "h2Consume")

            if (s.auto) fault("`h2Consume` is refused on a session that extends its own windows; open it with { autoWindowUpdate: false }")

            if (!$.isInt(args[2]) || Number(args[2]) < 0) fault("`h2Consume` takes a number of bytes, and this is " + typeName(args[2]))

            s.consume(h2Stream(args[1], "h2Consume"), Number(args[2]))

            return null
        }

        B.h2Close = (...args) => {
            h2Count(args, 1, 1, "h2Close", "a session")

            h2At(args[0], "h2Close")

            h2Sessions[Number(args[0])] = null

            return null
        }

    // -- the event loop ---------------------------------------------------------------------------
    //
    // **A promise is JavaScript's own**, which is the whole reason this is short: an `async` slate
    // function already compiles to an `async function` and `await` to `await`, so what was missing
    // was never the machinery -- it was the ten builtins that make a promise from OUTSIDE one.
    //
    // **The timers come from `$.host`**, taken from the engine before slate's own names were
    // installed over them. A host with none is a host with no event loop.

    const noLoop = (name) =>
        fault("`" + name + "` needs an event loop, and this JavaScript host has no timers")

    // A delay, in milliseconds or as a duration.
    //
    // **A duration is truncated to whole milliseconds, which is what the interpreter does** --
    // `do_timer` divides by a thousand -- and is all either host's timers can take anyway.
    const wantDelay = (v) => {
        if (v instanceof SDuration) return Number(v.us / 1000n)

        if (!$.isNum(v)) fault("a delay is a number of milliseconds or a duration, and this is " + typeName(v))

        const ms = Number(asReal(v))

        return ms < 0 ? 0 : ms
    }

    // Every live timer, by the id the program holds.
    //
    // **The id is slate's own number and not the engine's handle**, which node gives as an object
    // and quickjs as a number -- neither of which is the integer a slate program is promised. It
    // is never reused, so cancelling a timer that has already fired finds nothing rather than
    // finding whatever took its place.
    const timers = new Map()
    let nextTimer = 0n

    // **THE ORDER TIMERS FIRE IN IS SLATE'S RULE AND THE HOST IS ONLY ASKED TO WAKE US.**
    // A timer fires when it comes due, and two that come due together fire in the order they
    // were set -- the interpreter's rule, since libuv orders by (due, start). Handing each timer
    // to the host's own `setTimeout` broke it under node: node reads the clock afresh for every
    // `setTimeout` call, so a stall of ten milliseconds between `setTimeout(c, 30)` and
    // `setTimeout(b, 20)` made `c` due first, where the interpreter, whose clock is the one
    // reading taken when its turn of the loop began, fires `b` first. So the queue is slate's:
    // ordered by (due, seq), with ONE host timer armed for the earliest entry.
    //
    // **A deadline is measured from the clock reading of the synchronous run that set the
    // timer.** `base` is read once per run and dropped when the run's microtask returns, so
    // timers set one after another share a reading however long the code between them took.
    const clock = () => $.host.monotonic !== null ? $.host.monotonic() : Date.now()
    const queue = []
    let nextSeq = 0
    let turnBase = null
    let wake = null
    let wakeDue = 0

    const base = () => {
        if (turnBase === null) {
            turnBase = clock()
            Promise.resolve().then(() => { turnBase = null })
        }

        return turnBase
    }

    const disarm = () => {
        if (wake === null) return

        wake.stop(wake.handle)
        wake = null
    }

    // One host wake for the earliest entry. One already due is woken through `setImmediate`
    // where the host has it, since a host's `setTimeout(f, 0)` waits a millisecond and a
    // thousand timers due together would cost a second.
    const arm = () => {
        disarm()

        if (queue.length === 0) return

        wakeDue = queue[0].due

        const wait = wakeDue - clock()

        if (wait <= 0 && $.host.setImmediate !== null && $.host.clearImmediate !== null)
            wake = { handle: $.host.setImmediate(fire), stop: $.host.clearImmediate }
        else
            wake = { handle: $.host.setTimeout(fire, wait <= 0 ? 0 : Math.ceil(wait)), stop: $.host.clearTimeout }
    }

    // One entry per wake, so that the host's microtasks run between two timers as they do
    // between two `setTimeout` callbacks of its own.
    function fire() {
        wake = null

        if (queue.length === 0) return

        // Woken a fraction early, which a host's whole-millisecond timers do.
        if (queue[0].due > clock()) {
            arm()

            return
        }

        const entry = queue.shift()

        try {
            entry.run()
        } finally {
            arm()
        }
    }

    const enqueue = (entry) => {
        let at = queue.length

        while (at > 0 && queue[at - 1].due > entry.due) at--

        queue.splice(at, 0, entry)

        if (at === 0) arm()
    }

    const dequeue = (entry) => {
        const at = queue.indexOf(entry)

        if (at < 0) return

        queue.splice(at, 1)

        if (at === 0) arm()
    }

    const startTimer = (args, repeating) => {
        if (args.length === 0 || args.length > 2)
            fault("a timer takes a function and a delay, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        const f = args[0]

        if (typeof f !== "function") fault("a timer needs a function to call, and this is " + typeName(f))

        const ms = args.length === 2 ? wantDelay(args[1]) : 0
        const id = ++nextTimer
        const held = { entry: null }

        if ($.host.setTimeout === null) noLoop(repeating ? "setInterval" : "setTimeout")

        timers.set(id, held)

        if (repeating) {
            // **An interval is a chain of one-shots**, on every host. Re-armed after the
            // callback rather than on a schedule, so it drifts by however long the callback took;
            // a program that cares uses a deadline rather than a count of ticks.
            const again = () => {
                $.callback(f, [], "setInterval")

                // Cancelled by its own callback, which is how an interval in a program that means
                // to end is usually stopped.
                if (timers.get(id) === held) {
                    held.entry = { due: clock() + ms, seq: nextSeq++, run: again }
                    enqueue(held.entry)
                }
            }

            held.entry = { due: base() + ms, seq: nextSeq++, run: again }
            enqueue(held.entry)

            return id
        }

        // **A one-shot forgets itself before the body runs**, so that a callback cancelling its
        // own timer is not left holding an id that names nothing.
        held.entry = {
            due: base() + ms,
            seq: nextSeq++,
            run: () => {
                timers.delete(id)
                $.callback(f, [], "setTimeout")
            },
        }
        enqueue(held.entry)

        return id
    }

    B.setTimeout = (...args) => startTimer(args, false)
    B.setInterval = (...args) => startTimer(args, true)

    const clearOne = (v) => {
        if (!$.isInt(v)) fault("a timer is cancelled by its id, and this is " + typeName(v))

        const held = timers.get(v)

        // A stale id names nothing, which is not an error: the timer it named has fired.
        if (held === undefined) return null

        timers.delete(v)
        dequeue(held.entry)

        return null
    }

    B.clearTimeout = clearOne
    B.clearInterval = clearOne

    B.sleep = (...args) => {
        if (args.length !== 1)
            fault("`sleep` takes a number of milliseconds and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        // **A duration says what a bare number cannot**, and is why `sleep(2.seconds())` reads
        // better than `sleep(2000)`. The number form stays, being what node writes and what
        // every program here already says.
        if (!$.isNum(args[0]) && !(args[0] instanceof SDuration))
            fault("`sleep` takes a number of milliseconds or a duration, and this is " + typeName(args[0]))

        const ms = wantDelay(args[0])

        if ($.host.setTimeout === null) noLoop("sleep")

        return new Promise((answer) =>
            enqueue({ due: base() + ms, seq: nextSeq++, run: () => answer(null) }))
    }

    // `resolve(v)` and `reject(message)` -- a promise that has already settled.
    //
    // **A rejection carries a SENTENCE and not the value**, which is the interpreter's rule: what
    // an `await` on a failed promise raises is a fault, and a fault's reason is text. `reject(42)`
    // is caught as `{message: "42", ...}`.
    B.resolve = (...args) => {
        if (args.length !== 1) fault("`resolve` takes one argument and was given " + args.length)

        return Promise.resolve(args[0])
    }

    // **A rejection raises the same fault `throw` raises.** A string is a sentence and anything
    // else is the value a `catch` clause sorts on, or the two ways of raising a fault would
    // answer differently after an `await` -- the interpreter's `do_settled` draws the same line.
    const refusal = (v) => typeof v === "string" ? new $.Fault(v) : new $.Thrown(v)

    B.reject = (...args) => {
        if (args.length !== 1) fault("`reject` takes one argument and was given " + args.length)

        return Promise.reject(refusal(args[0]))
    }

    // `all(xs)`, `allSettled(xs)`, `race(xs)` and `any(xs)` -- one array in, one promise out.
    //
    // **`combine.sysl` is the other half and carries the reasons.** A plain value in the array is
    // a value that has already arrived, which is what `Promise.all` does with one anyway;
    // `allSettled` answers slate's own `{ ok, value }` / `{ ok, error }` rather than JavaScript's
    // `{ status, value | reason }`; and `race([])` and `any([])` FAULT rather than answering a
    // promise that never settles, which is a program that hangs and says nothing.
    const combining = (args, name) => {
        if (args.length !== 1)
            fault("`" + name + "` takes one array of promises, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (!Array.isArray(args[0]))
            fault("`" + name + "` takes an array of promises, and this is " + typeName(args[0]))

        return args[0]
    }

    // What a rejection SAID -- `allSettled`'s `error` and `any`'s sentence, both of which are text
    // rather than the thing that was thrown.
    //
    // **A rejection CARRYING a value says what an uncaught one would say**, which is the sentence
    // `Thrown` was built with: `{ ok: false, error }` is a result and a result's `error` is text,
    // so a fault that can be sorted on is still reported here as words.
    const whyRefused = (e) =>
        e instanceof $.Fault || e instanceof $.Thrown ? e.message : text(e)

    B.all = (...args) => Promise.all(combining(args, "all"))

    B.allSettled = (...args) =>
        Promise.allSettled(combining(args, "allSettled")).then((each) =>
            each.map((one) => one.status === "fulfilled"
                ? $.obj([["ok", true], ["value", one.value]])
                : $.obj([["ok", false], ["error", whyRefused(one.reason)]])))

    B.race = (...args) => {
        const xs = combining(args, "race")

        if (xs.length === 0)
            fault("`race` was given nothing to race -- there is no first answer among no promises")

        return Promise.race(xs)
    }

    // **What JavaScript raises an `AggregateError` for, said as one sentence**, in the order the
    // promises were given: slate's rejections carry text, so there is nothing for an error object
    // to be and what a reader needs is every reason.
    B.any = (...args) => {
        const xs = combining(args, "any")

        if (xs.length === 0)
            fault("`any` was given nothing to wait for -- there is no first answer among no promises")

        return Promise.any(xs).catch((e) => {
            if (!(e instanceof AggregateError)) throw e

            throw new $.Fault("every promise `any` was given failed: " +
                e.errors.map(whyRefused).join("; "))
        })
    }

    // `pending()`, and `settle(p, v)` and `fail(p, message)` which answer it.
    //
    // **This is the bridge from a callback into `await`**, and it is what a program cannot write
    // its way out of: without it the only awaitable things are the ones slate itself started.
    B.pending = (...args) => {
        if (args.length !== 0)
            fault("`pending` takes no arguments and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        let answer, refuse
        const p = new Promise((res, rej) => { answer = res; refuse = rej })

        p.$answer = answer
        p.$refuse = refuse

        return p
    }

    // **A promise settles once and a second answer is DROPPED rather than refused**, which is the
    // interpreter's rule and JavaScript's: two callbacks racing to answer one promise is a program
    // deciding late, not a program in error. A promise something else already owns -- what an
    // `async` function handed back -- has no answer of its own to give, so answering it is the
    // same nothing.
    const answerPromise = (args, name, failing) => {
        if (args.length !== 2)
            fault("`" + name + "` takes a promise and an answer, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        const p = args[0]

        if (!(p instanceof Promise)) fault("`" + name + "` answers a promise, and this is " + typeName(p))

        if (failing) {
            if (p.$refuse !== undefined) p.$refuse(refusal(args[1]))
        } else if (p.$answer !== undefined) {
            p.$answer(args[1])
        }

        return null
    }

    B.settle = (...args) => answerPromise(args, "settle", false)
    B.fail = (...args) => answerPromise(args, "fail", true)

    // -- the file system --------------------------------------------------------------------------
    //
    // **Twenty functions and one shape: ten operations, each in a promise-shaped and a blocking
    // form.** A blocking one answers `{ok: true, value}` or `{ok: false, error}`, a promise-shaped
    // one answers a promise that settles or raises a fault with the same sentence, and `exists`
    // is the exception both ways round -- a plain boolean, a path that is not there being an
    // answer rather than a failure.

    const fsOf = (name) => {
        if ($.host.fs === null)
            fault("`" + name + "` needs a file system, and this JavaScript host has none")

        return $.host.fs
    }

    // libuv's sentence for what went wrong, which is what the interpreter's message carries.
    //
    // **node says the same thing and then some**: `ENOENT: no such file or directory, open 'x'`
    // where libuv says `ENOENT: no such file or directory`. The syscall and the path are node's
    // addition, and cutting at the comma leaves libuv's own text -- which is the whole of making
    // the two back ends say one thing about a file that is not there.
    const uvText = (e) => {
        const said = String(e !== null && e !== undefined && e.message !== undefined ? e.message : e)
        const cut = said.indexOf(", ")

        return cut === -1 ? said : said.slice(0, cut)
    }

    // A file's bytes as text, or null where they are not text at all.
    //
    // **`textOfBytes` and not a `TextDecoder`**, which this used to build lazily so that an engine
    // without one -- quickjs has none -- could still run a program that never touches a file. It
    // is `fromBytes`' own decoder now, so there is one answer to *are these bytes text*, it is
    // strict where the interpreter is strict, and a host with no `TextDecoder` reads files like
    // any other.
    const asText = (bytes) => textOfBytes(Array.from(bytes))

    const onePath = (args, name) => {
        if (args.length !== 1)
            fault("`" + name + "` takes one path and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (!$.isStr(args[0])) fault("`" + name + "` takes a path, and this is " + typeName(args[0]))

        return args[0]
    }

    const ok = (v) => $.obj([["ok", true], ["value", v]])
    const bad = (message) => $.obj([["ok", false], ["error", message]])

    // **A BUFFER, where this answered an array of numbers.** The interpreter's
    // `read_bytes_promise` made the same change, and for its reason: a file read whole cost
    // sixteen times its own size in heap as an array.
    const asBytes = (raw) => $.bytesOf(new Uint8Array(raw))
    // **`modified` is a field and not an extra**, and leaving it out made `files(root)` in
    // `slate:http` die here rather than in `slate:fs`: an `etag` is the size and the
    // modification time, so `info.modified.epochMillis()` reached a missing field and said
    // "`epochMillis` is not something undefined can do" -- a sentence about the wrong module.
    // An `SInstant` of MICROSECONDS is what the interpreter answers, and `mtimeMs` is the
    // finest reading node gives without asking for `BigInt` stats and changing `size` with it.
    const asStat = (st) => $.obj([["size", BigInt(st.size)], ["isFile", st.isFile()],
        ["isDir", st.isDirectory()],
        ["modified", new SInstant(BigInt(Math.round(st.mtimeMs * 1000)))]])

    // The ten blocking ones. Each is its node call, its answer shape, and the sentence for a
    // failure -- and nothing else, which is what the pairing is worth.
    const syncing = (name, what, go) => {
        B[name] = (...args) => {
            const path = onePath(args, name)
            const fs = fsOf(name)

            try {
                return ok(go(fs, path))
            } catch (e) {
                if (e instanceof $.Fault) return bad(e.reason)

                return bad(what + " " + path + ": " + uvText(e))
            }
        }
    }

    // The promise-shaped ten, which answer the same shape.
    //
    // **A file that is not there settles the promise rather than failing it**, which is the
    // interpreter's rule and is the point of the shape: reaching the disk is expected to fail,
    // so a program that does not want to think about it is not made to write a `try` -- and one
    // that does reads `r.ok`. The pair differ in WHEN the answer arrives and in nothing else.
    const promising = (name, what, go) => {
        B[name] = (...args) => {
            const path = onePath(args, name)
            const fs = fsOf(name)

            return Promise.resolve()
                .then(() => go(fs.promises, path))
                .then(ok, (e) => bad(e instanceof $.Fault ? e.reason : what + " " + path + ": " + uvText(e)))
        }
    }

    // **A file that is not text is a sentence and not a decoding**, and the sentence names the
    // builtin that would have read it.
    const textOf = (raw, path, other) => {
        const said = asText(raw)

        if (said === null) fault(path + " is not text -- `" + other + "` reads a file that is not")

        return said
    }

    syncing("readFileSync", "cannot read", (fs, p) => textOf(fs.readFileSync(p), p, "readBytesSync"))
    syncing("readBytesSync", "cannot read", (fs, p) => asBytes(fs.readFileSync(p)))
    syncing("readDirSync", "cannot list", (fs, p) => fs.readdirSync(p))
    syncing("statSync", "cannot stat", (fs, p) => asStat(fs.statSync(p)))
    syncing("removeSync", "cannot remove", (fs, p) => { fs.unlinkSync(p); return null })
    syncing("mkdirSync", "cannot make", (fs, p) => { fs.mkdirSync(p); return null })
    syncing("rmdirSync", "cannot remove", (fs, p) => { fs.rmdirSync(p); return null })

    promising("readFile", "cannot read", (fs, p) => fs.readFile(p).then((raw) => textOf(raw, p, "readBytes")))
    promising("readBytes", "cannot read", (fs, p) => fs.readFile(p).then(asBytes))
    promising("readDir", "cannot list", (fs, p) => fs.readdir(p))
    promising("stat", "cannot stat", (fs, p) => fs.stat(p).then(asStat))
    promising("remove", "cannot remove", (fs, p) => fs.unlink(p).then(() => null))
    promising("mkdir", "cannot make", (fs, p) => fs.mkdir(p).then(() => null))
    promising("rmdir", "cannot remove", (fs, p) => fs.rmdir(p).then(() => null))

    // **`exists` answers a boolean either way round**, which is the one place the pair breaks the
    // shape: a path that is not there is what the question was about.
    B.existsSync = (...args) => {
        const path = onePath(args, "existsSync")
        const fs = fsOf("existsSync")

        try {
            fs.accessSync(path)

            return true
        } catch (e) {
            return false
        }
    }

    B.exists = (...args) => {
        const path = onePath(args, "exists")
        const fs = fsOf("exists")

        return fs.promises.access(path).then(() => true, () => false)
    }

    // **What is written is rendered as `print` would render it**, which is what a program writing
    // a number or an array to a file expects -- and refusing everything but a string would make
    // `writeFile(path, string(x))` the only spelling anybody ever wrote.
    const contentsOf = (args, name) => {
        if (args.length !== 2)
            fault("`" + name + "` takes a path and its contents, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (!$.isStr(args[0])) fault("`" + name + "` takes a path, and this is " + typeName(args[0]))

        return $.isStr(args[1]) ? args[1] : text(args[1])
    }

    B.writeFileSync = (...args) => {
        const said = contentsOf(args, "writeFileSync")
        const fs = fsOf("writeFileSync")

        try {
            fs.writeFileSync(args[0], said)

            return ok(null)
        } catch (e) {
            return bad("cannot write " + args[0] + ": " + uvText(e))
        }
    }

    B.writeFile = (...args) => {
        const said = contentsOf(args, "writeFile")
        const fs = fsOf("writeFile")

        return fs.promises.writeFile(args[0], said).then(
            () => ok(null),
            (e) => bad("cannot write " + args[0] + ": " + uvText(e)))
    }

    // **`print` is the answer and this is what a program says about producing it.** node has the
    // stream; a browser has none, so `console.error` stands in -- which is where a page's
    // diagnostics go and is the nearest thing there is.
    B.stderr = (...args) => {
        const said = args.map((v) => ($.isStr(v) ? v : text(v))).join(" ")

        if (typeof process !== "undefined" && process.stderr) process.stderr.write(said)
        else console.error(said)

        return null
    }

    // **`appendFile` and not a read followed by a write**, which is the same reason the
    // interpreter opens with `O_APPEND`: the bytes go at the end at the moment they are written,
    // and nothing holds the whole file to add a line to it.
    B.appendFile = (...args) => {
        const said = contentsOf(args, "appendFile")
        const fs = fsOf("appendFile")

        return fs.promises.appendFile(args[0], said).then(
            () => ok(null),
            (e) => bad("cannot write " + args[0] + ": " + uvText(e)))
    }

    B.appendFileSync = (...args) => {
        const said = contentsOf(args, "appendFileSync")
        const fs = fsOf("appendFileSync")

        try {
            fs.appendFileSync(args[0], said)

            return ok(null)
        } catch (e) {
            return bad("cannot write " + args[0] + ": " + uvText(e))
        }
    }

    // **Bytes on the writing side, and a value that is not bytes FAULTS here where `writeFile`
    // renders it.** The sentences are `with_bytes`'s in `builtin.sysl`, word for word, because
    // the two hosts have to refuse the same program the same way.
    const twinOf = { writeBytes: "writeFile", appendBytes: "appendFile",
        writeBytesSync: "writeFileSync", appendBytesSync: "appendFileSync" }

    const bytesOf = (args, name) => {
        if (args.length !== 2)
            fault("`" + name + "` takes a path and its bytes, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (!$.isStr(args[0])) fault("`" + name + "` takes a path, and this is " + typeName(args[0]))

        const given = args[1]

        // **A buffer is handed over as it stands**, nothing being decoded on the way to the disk.
        if (given instanceof $.SBytes) return given.view()

        if (!Array.isArray(given))
            fault("`" + name + "` takes bytes or an array of numbers, and this is " + typeName(given) +
                " -- `" + twinOf[name] + "` is what writes anything else")

        const out = new Uint8Array(given.length)

        for (let i = 0; i < given.length; i = i + 1) {
            const b = given[i]

            if (!$.isInt(b))
                fault("`" + name + "` takes an array of numbers, and one of these is " + typeName(b))

            if (b < 0n || b > 255n) fault("a byte is between 0 and 255, and this is " + b)

            out[i] = Number(b)
        }

        return out
    }

    B.writeBytesSync = (...args) => {
        const raw = bytesOf(args, "writeBytesSync")
        const fs = fsOf("writeBytesSync")

        try {
            fs.writeFileSync(args[0], raw)

            return ok(null)
        } catch (e) {
            return bad("cannot write " + args[0] + ": " + uvText(e))
        }
    }

    B.appendBytesSync = (...args) => {
        const raw = bytesOf(args, "appendBytesSync")
        const fs = fsOf("appendBytesSync")

        try {
            fs.appendFileSync(args[0], raw)

            return ok(null)
        } catch (e) {
            return bad("cannot write " + args[0] + ": " + uvText(e))
        }
    }

    B.writeBytes = (...args) => {
        const raw = bytesOf(args, "writeBytes")
        const fs = fsOf("writeBytes")

        return fs.promises.writeFile(args[0], raw).then(
            () => ok(null),
            (e) => bad("cannot write " + args[0] + ": " + uvText(e)))
    }

    B.appendBytes = (...args) => {
        const raw = bytesOf(args, "appendBytes")
        const fs = fsOf("appendBytes")

        return fs.promises.appendFile(args[0], raw).then(
            () => ok(null),
            (e) => bad("cannot write " + args[0] + ": " + uvText(e)))
    }

    const twoPaths = (args, name) => {
        if (args.length !== 2)
            fault("`" + name + "` takes two paths and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        for (const p of args)
            if (!$.isStr(p)) fault("`" + name + "` takes a path, and this is " + typeName(p))
    }

    B.renameSync = (...args) => {
        twoPaths(args, "renameSync")

        const fs = fsOf("renameSync")

        try {
            fs.renameSync(args[0], args[1])

            return ok(null)
        } catch (e) {
            return bad("cannot rename " + args[0] + ": " + uvText(e))
        }
    }

    B.rename = (...args) => {
        twoPaths(args, "rename")

        const fs = fsOf("rename")

        return fs.promises.rename(args[0], args[1]).then(
            () => ok(null),
            (e) => bad("cannot rename " + args[0] + ": " + uvText(e)))
    }

    // -- this program's own environment ------------------------------------------------------------
    //
    // **A host with no environment answers every variable unset**, rather than complaining: an
    // environment with nothing in it is a thing that can be true, and a browser's is exactly that.
    B.env = (...args) => {
        if (args.length !== 1)
            fault("`env` takes one variable name and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (!$.isStr(args[0])) fault("`env` takes a variable name, and this is " + typeName(args[0]))

        if ($.host.env === null) return null

        const said = $.host.env[args[0]]

        return said === undefined ? null : said
    }

    // **`environment()` is a fresh object of every variable, built from a copy of the host's.** A
    // host with no environment answers an empty object, which is `env` answering every name unset
    // said as an object; changing what comes back changes nothing, in either back end.
    B.environment = () => {
        if ($.host.env === null) return new $.SObj()

        return new $.SObj(Object.entries($.host.env).filter(([, v]) => typeof v === "string"))
    }

    // -- the script's own arguments, and stopping ----------------------------------------------------
    //
    // **`args` is a value here as it is in the interpreter**, and the loop below that puts every
    // builtin on the global object copies whatever it finds -- so a name that is not a function
    // needs nothing said about it.
    //
    // **A copy and not the host's own array, and NOT frozen.** The copy keeps a program that
    // sorts its arguments from reordering `process.argv` underneath node; leaving it writable is
    // what keeps the two back ends the same, the interpreter's `args` being an ordinary slate
    // array that a program may sort or shift like any other.
    B.args = $.host.args.slice()

    // **A host that cannot stop says so rather than returning.** Every caller of `exit` has
    // written the line after it expecting never to reach it, so quietly carrying on is the one
    // answer that would be wrong in silence.
    B.exit = (...args) => {
        if (args.length > 1)
            fault("`exit` takes a status or nothing at all, and was given " + args.length + " arguments")

        const status = args.length === 0 ? 0n : args[0]

        if (!$.isInt(status)) fault("`exit` takes a whole number, and this is " + typeName(status))

        if (status < 0n || status > 255n) fault("a status is between 0 and 255, and this is " + status)

        // **`slate test --js` runs the whole suite in one process, so a real `process.exit` here
        // would take every file after this one with it.** `$suite` is the only caller that turns
        // `$testMode` on, and this is a complaint about the test rather than the process actually
        // stopping -- `caught` passes it through every `catch` on the way there exactly as
        // `Skipped` is.
        if ($.inTestMode()) throw new $.Exited(Number(status))

        if ($.host.exit === null) fault("this host cannot stop a program, so `exit` has nowhere to go")

        $.host.exit(Number(status))
    }

    // Every name the interpreter declares, so that a program reaching one this back end has not
    // built yet is told so rather than failing as an undefined name.
    // -- `@test`, so that a slate test suite runs on this back end too ---------------------------
    //
    // **THE POINT OF THIS IS THE DIVISION OF LABOUR, NOT THE FEATURE.** The compiler's own suite
    // is written in sysl and drives the interpreter in this process, so it says nothing whatever
    // about `slate js` -- which is how two divergences sat in a shipped release. Everything that
    // is about what a RUNNING PROGRAM does belongs in slate `@test` functions instead, and those
    // then run against every back end there is. The interpreter's `run_one_test` in `run.sysl`
    // is the other half of this, and the two report in the same words on purpose.
    //
    // **`$test` and `$hook` register and `$suite` runs**, which is `Program.tests`, the four
    // annotations beside it and `run_tests_named` said in JavaScript. Only the ENTRY file
    // registers, exactly as `compile_module`'s `is_entry` decides for the interpreter -- a test
    // file imports the module it tests, and registering every module's would run the imported
    // file's tests once per importer, its `@setup` included.
    const REGISTERED = []

    // What the file wrote AROUND its tests, held under the index `run.sysl` holds it under:
    // `@setup`, `@teardown`, `@setupAll`, `@teardownAll`.
    //
    // **Four slots and not four names, because nothing about them differs but when they run.**
    // That is `HookSetup`/`HookTeardown`/`HookSetupAll`/`HookTeardownAll` in `vm.sysl`, and the
    // emitter writes the number.
    const HOOKS = [null, null, null, null]
    const HOOK_NAMES = ["", "", "", ""]

    // **On `$` and not on `B`, because the EMITTED PROGRAM calls these** -- `B`'s `$`-prefixed
    // names are the runtime's own and never become globals, and the emitter writes `$.$test`.
    $.$test = (name, fn) => { REGISTERED.push([name, fn]) }

    $.$hook = (kind, name, fn) => {
        HOOKS[kind] = fn
        HOOK_NAMES[kind] = name
    }

    // Every file of a suite, in ONE process, reported in the words `slate test` uses.
    //
    // **ONE runner for the whole suite is what makes running these under node affordable.** node
    // costs about twenty-three milliseconds to start, so a process per file made a ten-file suite
    // eight times slower than the work in it -- and the same suite is twenty times faster than an
    // embedded interpreter once it IS running. Scala Native's test framework is arranged the same
    // way and for the same reason: one binary, every test.
    //
    // Each entry is a path and a function that EVALUATES that file's program, which is what
    // registers its tests. Running them is this function's job rather than the program's, so that
    // one report covers the suite and one status leaves it.
    //
    // **`only` narrows what is RUN and never what is loaded**, a test's name being something the
    // file has to run to declare. `run_tests_named` draws the same line.
    $.$suite = async (files, only) => {
        // **`exit` reaches `slate test --js` too, and there it is a complaint rather than the
        // process actually stopping** -- the interpreter's `run_one_test` refuses it for the same
        // reason, and `B.exit` reads this to choose between the two.
        $.enterTestMode()

        let passed = 0
        let failed = 0
        let leftOut = 0

        // Whether any test anywhere was picked, which is the question a filter that matches
        // nothing has to be answered with.
        let anyChosen = false

        // **A passing test's output is DISCARDED and a failing one's is shown**, which is what
        // the interpreter does by clearing `output` before each test and printing it only in the
        // failing branch. So the console is turned off for the run and the lines are read back.
        const echoed = $.host.echo

        $.host.echo = false

        const said = []

        // One call of no arguments: make it, wait for it, and answer what it left behind. An
        // empty answer is a call that did what it was asked to.
        const phase = async (fn) => {
            try {
                const answered = fn()

                if (answered instanceof Promise) await answered
            } catch (e) {
                // **A skip is asked about BEFORE `caught`, which rethrows one.** It is a
                // verdict rather than a fault, on both hosts.
                //
                // **`caught` is otherwise what a `catch` in a slate program would have been
                // given**, so a `throw` of a value, a fault raised by the machine and a
                // JavaScript error from inside the runtime all reach here as one shape --
                // which is `settled_call` reading its `Err` on the other side.
                if (e instanceof $.Skipped) return { skip: e.reason }

                // **Read straight off `Exited` and never through `caught`**, which rethrows it --
                // `run_one_test`'s sentence, word for word, so the two hosts report `exit` inside
                // a test in the same words.
                if (e instanceof $.Exited)
                    return { said: "`exit(" + e.status + ")` was called, and a test may not stop the run it is part of" }

                return { said: $.said(e) }
            }

            return {}
        }

        // One of the four, where the file wrote one at all.
        const runHook = async (kind) => {
            if (HOOKS[kind] === null) return {}

            const ran = await phase(HOOKS[kind])

            if (ran.skip === undefined) return ran

            // **A `skip` in a teardown has no test left to leave out**, the verdict having been
            // given, so it is a complaint about the teardown rather than a third state.
            if (kind === 1 || kind === 3)
                return { said: "`" + HOOK_NAMES[kind] + "` called `skip`, and a teardown has no test to leave out" }

            return ran
        }

        const guardedBy = (kind, complaint) =>
            "`" + HOOK_NAMES[kind] + "` failed before this test ran\n" + complaint

        // A teardown's own failure, kept as a verdict of its own -- never swallowed and never
        // folded into the test's, which is what makes it count on the last line.
        const hookVerdict = (path, kind, ran, from) => {
            if (ran.said === undefined) return

            failed += 1
            said.push("  FAIL  " + path + " :: " + HOOK_NAMES[kind] + "   0ms")

            for (const line of $.host.lines.slice(from)) said.push("        " + line)
            for (const line of ran.said.split("\n")) said.push("        " + line)
        }

        for (const [path, load] of files) {
            // **The registry is emptied per FILE**, which is `compile_module`'s `is_entry` rule
            // said at run time: a test file imports the module it tests, and a registry carried
            // across files would run an imported file's tests once per importer.
            REGISTERED.length = 0
            HOOKS[0] = null
            HOOKS[1] = null
            HOOKS[2] = null
            HOOKS[3] = null

            try {
                // **Waited for, because a file that writes `await` at its own top level is
                // evaluated by an `async` function** -- unwaited, its tests would be registered
                // after the run that was supposed to find them, and a failure in it would arrive
                // as an unhandled rejection rather than as this file failing. A file that waits
                // for nothing answers `undefined` and this costs it a comparison.
                const evaluated = load()

                if (evaluated instanceof Promise) await evaluated
            } catch (e) {
                // **A file whose top level faults is reported as the FILE failing**, not as every
                // test in it failing for one reason -- `run_tests` draws the same line, and its
                // reason is that such a file has no working tests to speak of.
                failed += 1
                said.push("  FAIL  " + path)

                // **`exit` at a file's top level is the same complaint `prepare` renders in the
                // interpreter** -- the file never got as far as declaring a test, and `caught`
                // would only rethrow this rather than answer it.
                const message = e instanceof $.Exited
                    ? "`exit(" + e.status + ")` was called, and a test may not stop the run it is part of"
                    : $.said(e)

                for (const line of message.split("\n"))
                    said.push("        " + line)

                continue
            }

            const chosen = REGISTERED.filter(([name]) => only === "" || name.includes(only))

            // **`@setupAll` runs only where something was chosen**, a filter that picks nothing
            // out of a file leaving it nothing to prepare.
            if (chosen.length === 0) continue

            anyChosen = true

            const opened = await runHook(2)
            const guarded = opened.skip === undefined && opened.said === undefined

            for (const [name, fn] of chosen) {
                const began = Date.now()
                const from = $.host.lines.length

                let skipReason = null
                let complaint = null

                if (opened.skip !== undefined) skipReason = opened.skip
                else if (opened.said !== undefined) complaint = guardedBy(2, opened.said)
                else {
                    const before = await runHook(0)

                    if (before.skip !== undefined) skipReason = before.skip
                    else if (before.said !== undefined) complaint = guardedBy(0, before.said)
                    else {
                        const ran = await phase(fn)

                        if (ran.skip !== undefined) skipReason = ran.skip
                        else if (ran.said !== undefined) complaint = ran.said
                    }
                }

                const ms = Date.now() - began
                const printed = $.host.lines.slice(from)

                if (skipReason !== null) {
                    leftOut += 1
                    said.push("  skip  " + path + " :: " + name + "   " + skipReason)
                } else if (complaint === null) {
                    passed += 1
                    said.push("  ok    " + path + " :: " + name + "   " + ms + "ms")
                } else {
                    failed += 1
                    said.push("  FAIL  " + path + " :: " + name + "   " + ms + "ms")

                    for (const line of printed) said.push("        " + line)
                    for (const line of complaint.split("\n")) said.push("        " + line)
                }

                // **The `@teardown` runs however the test went** -- passed, failed or left out --
                // and only where the test was actually attempted: a `@setupAll` that fell over
                // took the per-test pair with it.
                if (guarded) hookVerdict(path, 1, await runHook(1), from)

                // **An actor left running is a thread of the NEXT test's**, a suite being one
                // process -- `forget_actors` in `reset_events`, said where the runner can call
                // it. It is after the teardown, that being the last thing entitled to talk to
                // one.
                $.actorReset()

                // **Cut back rather than left to grow**, or a long suite holds every line every
                // one of its tests ever printed.
                $.host.lines.length = from
            }

            // **`@teardownAll` runs even where `@setupAll` faulted**, which is what a teardown is
            // for: what it gives back is what a setup that stopped halfway had already taken.
            hookVerdict(path, 3, await runHook(3), $.host.lines.length)
        }

        $.host.echo = echoed
        $.host.lines.length = 0

        for (const line of said) $.host.write(line)

        // **The counts and the status are `test_command`'s, word for word and number for
        // number** -- a file that would not load counts as one failure there too, and this is
        // `summary_line` in `main.sysl`: a count that is zero is not written, so a suite with
        // nothing skipped says exactly what it always said.
        let line = passed + " passed"

        if (failed > 0) line += ", " + failed + " failed"
        if (leftOut > 0) line += ", " + leftOut + " skipped"

        $.host.write("")
        $.host.write(line)

        // **A filter that picks nothing is a failure and not an empty success**, and the sentence
        // is `no_match_line`'s word for word.
        if (only !== "" && !anyChosen) {
            $.host.write("slate: no test name contains \"" + only + "\"")

            if ($.host.exit !== null) $.host.exit(1)

            return
        }

        if ($.host.exit !== null) $.host.exit(failed === 0 ? 0 : 1)
    }

    // -- signals ---------------------------------------------------------------------------

    // **`onSignal` and `offSignal`, over `process.on` and `process.off`.** The interpreter's
    // half is `signals.sysl` and every sentence below is that file's, word for word: which
    // names there are, which two of them cannot be caught, and what an id that names nothing
    // means. A program asking to be told about `SIGTERM` is the same program on either host.
    //
    // **THE LISTENER IS STORED UNDER THE ID BECAUSE `process.off` REMOVES BY IDENTITY.** A
    // fresh wrapper handed to it would remove nothing and the handler would keep firing, which
    // is the `addEventListener`/`removeEventListener` trap arriving on a different host object.
    //
    // **A watcher does not keep the program alive, and node gives that for free** -- which is
    // the rule the interpreter reaches by calling `unref` on the libuv handle, so nothing here
    // has to say it.
    const CATCHABLE = ["SIGHUP", "SIGINT", "SIGQUIT", "SIGABRT", "SIGPIPE", "SIGALRM",
        "SIGTERM", "SIGCHLD", "SIGCONT", "SIGTSTP", "SIGUSR1", "SIGUSR2", "SIGWINCH"]

    const CATCHABLE_SAID = "SIGHUP, SIGINT, SIGQUIT, SIGABRT, SIGPIPE, SIGALRM, SIGTERM, " +
        "SIGCHLD, SIGCONT, SIGTSTP, SIGUSR1, SIGUSR2 and SIGWINCH"

    const signals = new Map()
    let nextSignal = 0n

    // The host's own signal door, or nothing where there is none. **A browser has no
    // `process`**, and a page that could be sent `SIGTERM` is not a thing.
    const signalHost = () => {
        if (typeof process === "undefined") return null
        if (typeof process.on !== "function" || typeof process.off !== "function") return null

        return process
    }

    B.onSignal = (...args) => {
        if (args.length !== 2)
            fault("`onSignal` takes a signal name and a function, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (!$.isStr(args[0]))
            fault("`onSignal` takes a signal name, and this is " + typeName(args[0]))

        const f = args[1]

        if (typeof f !== "function")
            fault("`onSignal` needs a function to call, and this is " + typeName(f))

        const name = args[0]

        // **Refused by name, before the host is asked.** node throws its own error for these
        // two and the interpreter refuses them before libuv sees them; what a program needs to
        // hear is that nothing of its own will run, which neither host's own message says.
        if (name === "SIGKILL" || name === "SIGSTOP")
            fault("`" + name + "` cannot be caught: the kernel acts on it itself, and nothing " +
                "this program says will run first")

        if (CATCHABLE.indexOf(name) < 0)
            fault("there is no signal called `" + name + "`; the ones a program may catch are " +
                CATCHABLE_SAID)

        const host = signalHost()

        if (host === null)
            fault("`onSignal` needs a process to be signalled, and this JavaScript host is not one")

        // **The handler is given nothing**, where node hands its listener the signal's name and
        // a number: slate checks the count of a call's arguments, so a name passed through
        // would be a parameter every program had to write.
        const listener = () => $.callback(f, [], "onSignal")
        const id = ++nextSignal

        signals.set(id, { name: name, listener: listener })
        host.on(name, listener)

        return id
    }

    B.offSignal = (...args) => {
        if (args.length !== 1)
            fault("`offSignal` takes the id `onSignal` answered, and was given " + args.length +
                (args.length === 1 ? " argument" : " arguments"))

        if (!$.isInt(args[0]))
            fault("a signal handler is stopped by its id, and this is " + typeName(args[0]))

        const held = signals.get(args[0])

        // **An id that names nothing is not an error**, which is `clearTimeout`'s rule: a
        // program stopping a handler twice has said something true about what it wants.
        if (held === undefined) return null

        signals.delete(args[0])

        const host = signalHost()

        if (host !== null) host.off(held.name, held.listener)

        return null
    }

    // **`slate:time` IS WHOLE NOW EXCEPT FOR `abbrev` AND `isDST`**, and those two are not owed
    // work -- they are things a JavaScript host does not have. `js_rt_cal.sysl` carries the
    // measurements and `js_rt_cal_builtins.sysl` refuses both with a sentence saying which, so
    // neither is on this list: a name here says "not built yet", which would be a promise
    // nobody can keep. `docs/reference/javascript.md` says which half is which.
    //
    // **`utc` is the one calendar name still genuinely owed**, the interpreter having no such
    // builtin either -- `zone("UTC")` is how a program asks -- so it stays here with the rest.
    //
    // **The five `redis*` names were MISSING FROM BOTH and the three-set test is what found
    // them.** `slate:redis` is written in slate over them, so a program that reached one under
    // `slate js` would have died with `redisReader is not defined` -- a JavaScript sentence
    // about a name slate owns. It was masked only because `connect` refuses first.
    //
    // **`slate:brotli`'s two left this list for the same reason the calendar's two never joined
    // it.** No browser has a brotli encoder and none is coming, so `js_rt_gzip.sysl` refuses
    // them naming brotli and pointing at `slate:gzip`, which is the compression a host does
    // have.
    // **`slate:net` and `slate:llhttp` came OFF this list**, which is what `js_rt_net.sysl` and
    // `js_rt_http.sysl` are: sockets over node's own `net`, and the request parser written out.
    // `startTls` is node's `tls` at both ends; what is still owed of the transport is a listener
    // told a certificate, which refuses naming TLS, and HTTP/2, whose server half is written out
    // in `js_rt_h2.sysl` and whose client half and stand-alone HPACK are still here.
    // **A NAME GOES OFF THIS LIST WITH THE FEATURE THAT DECLARES IT.** `OWED` is checked as a
    // SUBSET of `builtin_names()`, so a name left here for a native this build does not register
    // is a promise about something that does not exist -- which is the half of the three-set
    // check that catches a rename, catching a feature instead.
    const OWED = ["utc",
        "run",

        "redisReader", "redisFeed", "redisTake", "redisCommand", "redisClose",


        "h2Client", "h2Request", "h2RequestStream",
        "h2Settings", "h2Reset", "h2WindowUpdate", "h2Ping", "h2Wants",
        "hpackDeflater", "hpackInflater", "hpackDeflate", "hpackInflate",
        "hpackClose",

    ]

    for (const name of OWED)
        if (B[name] === undefined)
            B[name] = () => fault("`" + name + "` is not in the JavaScript back end yet")

    // **The list, as a name a TEST can read.** A `$`-prefixed name is one no slate program can
    // write, which is what `$method` and `$reTest` are; this one is here so that the three sets
    // in `tests_owed.sysl` can be compared against `builtin_names()` rather than against a scan
    // of this file's text, which would go stale the first time the array is reformatted.
    B.$owed = OWED

    return B
})()

// The receiver rule's other half: a builtin method, found by the kind of what it was asked of.
function builtinMethod(v, name) {
    return $b.$method(v, name)
}

// A builtin kind's property, found the same way. A property answers a VALUE where a method hands
// back the function, so what comes back here is called on the spot.
function builtinProperty(v, name) {
    return $b.$property(v, name)
}

// **A builtin is a name because the PROGRAM is a function of the builtins**, not because slate
// put one in the host's global scope. `js.sysl` writes that wrapper and reads the names off the
// same scope `install_natives` fills, so this file is still the only place a builtin's
// implementation is written and there is no second list of what they are called.
//
// **Nothing is installed on `globalThis` and that is the whole of the change.** Taking those
// names over made every host API that calls one get slate's: node's `WebSocket` calls
// `setTimeout` and wants the host's handle back, and slate's integer id has no `.unref`, so the
// socket never opened. In a browser the same thing takes `fetch` and the timers from every other
// script on the page. slate is a guest there.

;((E, Map, PI, Set, WeakMap, WeakRef, abbrev, abs, acos, actorAsk, actorDetach, actorDone, actorMe, actorSend, actorSpawn, actorStop, actorTransfer, all, allSettled, alpnProtocol, any, appendBytes, appendBytesSync, appendFile, appendFileSync, argon2, argon2NeedsRehash, argon2Verify, args, array, asin, assert, assertEq, assertFaults, at, atan, atan2, boolean, bytes, casefold, cbrt, ceil, channel, chars, chunk, clear, clearInterval, clearTimeout, close, compress, concat, connect, contains, cos, cosh, count, cpus, date, dateTime, day, dayOfYear, days, daysInMonth, decompress, deflate, encodeJPEG, encodePNG, encodeWebP, endsWith, entries, env, environment, epochMicros, epochMillis, epochSeconds, every, execPath, exists, existsSync, exit, exp, fail, fetch, filter, find, findIndex, findLast, findLastIndex, flat, flatMap, floor, forEach, format, formatNumber, freeze, fromBytes, groupBy, gunzip, gzip, h2Client, h2Close, h2Consume, h2Finish, h2Goaway, h2Next, h2Ping, h2Push, h2Receive, h2Request, h2RequestStream, h2Reset, h2Respond, h2RespondStream, h2Send, h2Server, h2Settings, h2Wants, h2WindowUpdate, has, hmac, host, hostHas, hour, hours, hpackClose, hpackDeflate, hpackDeflater, hpackInflate, hpackInflater, httpClose, httpFeed, httpFinish, httpParser, httpStream, httpTake, httpTakePart, httpUpgraded, hypot, imageShape, includes, indexOf, inflate, insert, instant, integer, isDST, isFinite, isFrozen, isLeapYear, isNaN, join, jwsSign, jwsVerify, keys, lastIndexOf, listen, lmdbAbort, lmdbClear, lmdbClose, lmdbCommit, lmdbCursor, lmdbCursorClose, lmdbDb, lmdbDelete, lmdbFirst, lmdbGet, lmdbHas, lmdbInfo, lmdbNext, lmdbOpen, lmdbPut, lmdbRead, lmdbSeek, lmdbStat, lmdbWrite, localPort, localZone, log, log10, log2, lower, map, max, maxBy, md5, micros, millis, min, minBy, minute, minutes, mkdir, mkdirSync, monotonic, month, monthName, months, next, normalize, now, number, offSignal, offset, onBytes, onData, onError, onOrAfter, onSignal, padEnd, padStart, parseDate, parseDateTime, parseJSON, parseTime, parseTimestamp, partition, pbkdf2, pending, pid, pop, pow, print, push, race, random, randomBytes, readBytes, readBytesSync, readDir, readDirSync, readFile, readFileSync, readImage, real, redisClose, redisCommand, redisFeed, redisReader, redisTake, reduce, regex, reject, remoteAddress, remove, removeAt, removeSync, rename, renameSync, repeat, replace, replaceAll, resizeImage, resolve, reverse, reversed, rmdir, rmdirSync, round, run, scriptPath, second, seconds, send, setInterval, setTimeout, settle, sha1, sha256, sha384, sha512, shift, shutdown, sin, sinh, skip, sleep, slice, some, sort, sorted, spawn, split, sqliteClose, sqliteCompiled, sqliteExec, sqliteFinalize, sqliteOpen, sqlitePrepare, sqliteQuery, sqliteRun, sqrt, startOf, startTls, startsWith, stat, statSync, stderr, string, sum, tan, tanh, time, timingSafeEqual, toArray, toBytes, toExponential, toFixed, toJSON, toLowerCase, toPrecision, toReversed, toUpperCase, trim, trimEnd, trimStart, trunc, unique, unshift, unzstd, upper, utc, values, weekday, weeks, without, writeBytes, writeBytesSync, writeFile, writeFileSync, wsClose, wsOnClose, wsOnMessage, wsOpen, wsSend, wsSendBytes, year, years, zip, zone, zstd) => {

;(() => {
    $.files(["tests/js/p56.sl", "slate:fs", "slate:net"]);

    const $m1 = (() => {
        $.at(0, 1);
        const $exports = $.obj([]);

        $exports.setName("readFile", readFile);
        $exports.setName("readBytes", readBytes);
        $exports.setName("writeFile", writeFile);
        $exports.setName("appendFile", appendFile);
        $exports.setName("writeBytes", writeBytes);
        $exports.setName("appendBytes", appendBytes);
        $exports.setName("readDir", readDir);
        $exports.setName("stat", stat);
        $exports.setName("exists", exists);
        $exports.setName("remove", remove);
        $exports.setName("mkdir", mkdir);
        $exports.setName("rmdir", rmdir);
        $exports.setName("rename", rename);
        $exports.setName("readFileSync", readFileSync);
        $exports.setName("readBytesSync", readBytesSync);
        $exports.setName("writeFileSync", writeFileSync);
        $exports.setName("appendFileSync", appendFileSync);
        $exports.setName("writeBytesSync", writeBytesSync);
        $exports.setName("appendBytesSync", appendBytesSync);
        $exports.setName("readDirSync", readDirSync);
        $exports.setName("statSync", statSync);
        $exports.setName("existsSync", existsSync);
        $exports.setName("removeSync", removeSync);
        $exports.setName("mkdirSync", mkdirSync);
        $exports.setName("rmdirSync", rmdirSync);
        $exports.setName("renameSync", renameSync);

        return $exports;
    })();

    const $m2 = (() => {
        $.at(0, 2);
        const $exports = $.obj([]);

        $exports.setName("listen", listen);
        $exports.setName("connect", connect);
        $exports.setName("onData", onData);
        $exports.setName("onBytes", onBytes);
        $exports.setName("onError", onError);
        $exports.setName("send", send);
        $exports.setName("close", close);
        $exports.setName("shutdown", shutdown);
        $exports.setName("localPort", localPort);
        $exports.setName("remoteAddress", remoteAddress);
        $exports.setName("startTls", startTls);
        $exports.setName("alpnProtocol", alpnProtocol);

        return $exports;
    })();

    const $m0 = (() => {
        $.at(0, 0);
        const $exports = $.obj([]);

        $.at(12, 0);
        const readFileSync = $.field($m1, "readFileSync");
        $.at(13, 0);
        const listen = $.field($m2, "listen");
        const connect = $.field($m2, "connect");
        const onData = $.field($m2, "onData");
        const send = $.field($m2, "send");
        const shutdown = $.field($m2, "shutdown");
        const close = $.field($m2, "close");
        const localPort = $.field($m2, "localPort");
        const startTls = $.field($m2, "startTls");
        $.at(15, 0);
        const theCert = $.keep($.field($.call(readFileSync, ["tests/tls/cert.pem"]), "value"), "bound to `theCert`");
        $.at(16, 0);
        const theKey = $.keep($.field($.call(readFileSync, ["tests/tls/key.pem"]), "value"), "bound to `theKey`");
        $.at(19, 0);
        async function waitFor(ready) {
            let $t1;
            $.at(20, 0);
            let turns = 0n;
            $.at(22, 0);
            let $t2 = null;
            let $t3 = false;
            $L4: while (true) {
                let $t5 = (!($.call(ready, [])));
                if ($t5) {
                    $t5 = $.compare("<", turns, 300n);
                }
                if (!($t5)) break $L4;
                $.at(23, 0);
                await $.awaited($.call(sleep, [10n]));
                $.at(24, 0);
                turns = $.arith("+", turns, 1n);
            }
            $t1 = $t2;
            return $.keep($t1, "returned");
        }
        $.sig(waitFor, ["ready"], 1, "waitFor");
        $.at(28, 0);
        async function replied(conn, heard) {
            let $t6;
            $.at(29, 0);
            await $.awaited($.call(send, [conn, $.arith("+", "reply to ", heard)]));
            $.at(30, 0);
            $t6 = $.call(close, [conn]);
            return $t6;
        }
        $.sig(replied, ["conn", "heard"], 2, "replied");
        $.at(34, 0);
        function serving(serverSide) {
            let $t7;
            $.at(35, 0);
            const $t8 = function(conn) {
                let $t9;
                $.at(36, 0);
                let heard = "";
                $.at(37, 0);
                let secured = $.eq(serverSide, null);
                $.at(39, 0);
                const $t10 = function(chunk) {
                    let $t11;
                    $.at(40, 0);
                    let $t12;
                    if ($.eq(chunk, null)) {
                        $.at(41, 0);
                        $t12 = $.call(replied, [conn, heard]);
                    } else {
                        $.at(42, 0);
                        let $t13;
                        if (secured) {
                            $.at(43, 0);
                            heard = $.arith("+", heard, chunk);
                            $t13 = null;
                        } else {
                            $.at(45, 0);
                            secured = true;
                            $.at(47, 0);
                            $.call(send, [conn, "S"]);
                            $.at(48, 0);
                            $t13 = $.call(startTls, [conn, serverSide]);
                        }
                        $t12 = $t13;
                    }
                    $t11 = $t12;
                    return $.keep($t11, "returned");
                };
                $.sig($t10, ["chunk"], 1, "");
                $t9 = $.call(onData, [conn, $t10]);
                return $t9;
            };
            $.sig($t8, ["conn"], 1, "");
            $t7 = $.call(listen, [0n, $t8]);
            return $t7;
        }
        $.sig(serving, ["serverSide"], 1, "serving");
        $.at(51, 0);
        async function halfClosed(serverSide, clientSide) {
            let $t14;
            $.at(52, 0);
            const server = $.call(serving, [serverSide]);
            $.at(53, 0);
            const c = $.keep($.field(await $.awaited($.call(connect, ["127.0.0.1", $.call(localPort, [server])])), "value"), "bound to a local");
            $.at(54, 0);
            let heard = $.arr([]);
            $.at(55, 0);
            let ended = false;
            $.at(57, 0);
            const $t15 = function(chunk) {
                let $t16;
                $.at(58, 0);
                let $t17;
                if ($.eq(chunk, null)) {
                    $.at(58, 0);
                    ended = true;
                    $t17 = null;
                } else {
                    $.at(58, 0);
                    $t17 = $.method(heard, "push", [chunk]);
                }
                $t16 = $t17;
                return $.keep($t16, "returned");
            };
            $.sig($t15, ["chunk"], 1, "");
            $.call(onData, [c, $t15]);
            $.at(60, 0);
            let $t18;
            if ((!$.eq(clientSide, null))) {
                $.at(61, 0);
                await $.awaited($.call(send, [c, "SSLRequest"]));
                $.at(62, 0);
                const $t19 = function() {
                    let $t20;
                    $.at(62, 0);
                    $t20 = $.compare(">", $.field(heard, "length"), 0n);
                    return $t20;
                };
                $.sig($t19, [], 0, "");
                await $.awaited($.call(waitFor, [$t19]));
                $.at(64, 0);
                const up = $.keep(await $.awaited($.call(startTls, [c, clientSide])), "bound to a local");
                $.at(66, 0);
                $.call(print, ["upgraded", $.field(up, "ok")]);
                $.at(68, 0);
                heard = $.arr([]);
                $t18 = null;
            } else {
                $t18 = null;
            }
            $.at(70, 0);
            const sent = $.keep(await $.awaited($.call(send, [c, "hello"])), "bound to a local");
            $.at(71, 0);
            const first = $.keep(await $.awaited($.call(shutdown, [c])), "bound to a local");
            $.at(72, 0);
            const again = $.keep(await $.awaited($.call(shutdown, [c])), "bound to a local");
            $.at(73, 0);
            const after = $.keep(await $.awaited($.call(send, [c, "more"])), "bound to a local");
            $.at(75, 0);
            const $t21 = function() {
                let $t22;
                $.at(75, 0);
                $t22 = ended;
                return $.keep($t22, "returned");
            };
            $.sig($t21, [], 0, "");
            await $.awaited($.call(waitFor, [$t21]));
            $.at(77, 0);
            $.call(print, ["sent", $.field(sent, "ok")]);
            $.at(78, 0);
            $.call(print, ["shutdown", $.field(first, "ok"), "twice", $.field(again, "ok")]);
            $.at(79, 0);
            $.call(print, ["send after", $.field(after, "ok"), $.field(after, "error")]);
            $.at(80, 0);
            $.call(print, ["heard", $.method(heard, "join", [""]), "ended", ended]);
            $.at(82, 0);
            $.call(close, [c]);
            $.at(83, 0);
            $t14 = $.call(close, [server]);
            return $t14;
        }
        $.sig(halfClosed, ["serverSide", "clientSide"], 2, "halfClosed");
        $.at(85, 0);
        async function plain() {
            let $t23;
            $.at(86, 0);
            $t23 = await $.awaited($.call(halfClosed, [null, null]));
            return $.keep($t23, "returned");
        }
        $.sig(plain, [], 0, "plain");
        $.at(88, 0);
        async function overTls() {
            let $t24;
            $.at(89, 0);
            $t24 = await $.awaited($.call(halfClosed, [$.obj([["cert", theCert], ["key", theKey]]), $.obj([["host", "localhost"], ["trust", theCert]])]));
            return $.keep($t24, "returned");
        }
        $.sig(overTls, [], 0, "overTls");
        $.at(92, 0);
        async function refused() {
            let $t25;
            $.at(93, 0);
            const $t26 = function(conn) {
                let $t27;
                $.at(93, 0);
                $t27 = $.call(close, [conn]);
                return $t27;
            };
            $.sig($t26, ["conn"], 1, "");
            const server = $.call(listen, [0n, $t26]);
            $.at(94, 0);
            const onServer = $.keep(await $.awaited($.call(shutdown, [server])), "bound to a local");
            $.at(96, 0);
            $.call(print, ["listener", $.field(onServer, "ok")]);
            $.at(98, 0);
            const c = $.keep($.field(await $.awaited($.call(connect, ["127.0.0.1", $.call(localPort, [server])])), "value"), "bound to a local");
            $.at(100, 0);
            $.call(close, [c]);
            $.at(101, 0);
            $t25 = $.call(close, [server]);
            return $t25;
        }
        $.sig(refused, [], 0, "refused");
        $.at(103, 0);
        async function main() {
            let $t28;
            $.at(104, 0);
            await $.awaited($.call(plain, []));
            $.at(105, 0);
            await $.awaited($.call(overTls, []));
            $.at(106, 0);
            $t28 = await $.awaited($.call(refused, []));
            return $.keep($t28, "returned");
        }
        $.sig(main, [], 0, "main");
        $.at(108, 0);
        $.call(main, []);

        return $exports;
    })();
})();
})($b["E"], $b["Map"], $b["PI"], $b["Set"], $b["WeakMap"], $b["WeakRef"], $b["abbrev"], $b["abs"], $b["acos"], $b["actorAsk"], $b["actorDetach"], $b["actorDone"], $b["actorMe"], $b["actorSend"], $b["actorSpawn"], $b["actorStop"], $b["actorTransfer"], $b["all"], $b["allSettled"], $b["alpnProtocol"], $b["any"], $b["appendBytes"], $b["appendBytesSync"], $b["appendFile"], $b["appendFileSync"], $b["argon2"], $b["argon2NeedsRehash"], $b["argon2Verify"], $b["args"], $b["array"], $b["asin"], $b["assert"], $b["assertEq"], $b["assertFaults"], $b["at"], $b["atan"], $b["atan2"], $b["boolean"], $b["bytes"], $b["casefold"], $b["cbrt"], $b["ceil"], $b["channel"], $b["chars"], $b["chunk"], $b["clear"], $b["clearInterval"], $b["clearTimeout"], $b["close"], $b["compress"], $b["concat"], $b["connect"], $b["contains"], $b["cos"], $b["cosh"], $b["count"], $b["cpus"], $b["date"], $b["dateTime"], $b["day"], $b["dayOfYear"], $b["days"], $b["daysInMonth"], $b["decompress"], $b["deflate"], $b["encodeJPEG"], $b["encodePNG"], $b["encodeWebP"], $b["endsWith"], $b["entries"], $b["env"], $b["environment"], $b["epochMicros"], $b["epochMillis"], $b["epochSeconds"], $b["every"], $b["execPath"], $b["exists"], $b["existsSync"], $b["exit"], $b["exp"], $b["fail"], $b["fetch"], $b["filter"], $b["find"], $b["findIndex"], $b["findLast"], $b["findLastIndex"], $b["flat"], $b["flatMap"], $b["floor"], $b["forEach"], $b["format"], $b["formatNumber"], $b["freeze"], $b["fromBytes"], $b["groupBy"], $b["gunzip"], $b["gzip"], $b["h2Client"], $b["h2Close"], $b["h2Consume"], $b["h2Finish"], $b["h2Goaway"], $b["h2Next"], $b["h2Ping"], $b["h2Push"], $b["h2Receive"], $b["h2Request"], $b["h2RequestStream"], $b["h2Reset"], $b["h2Respond"], $b["h2RespondStream"], $b["h2Send"], $b["h2Server"], $b["h2Settings"], $b["h2Wants"], $b["h2WindowUpdate"], $b["has"], $b["hmac"], $b["host"], $b["hostHas"], $b["hour"], $b["hours"], $b["hpackClose"], $b["hpackDeflate"], $b["hpackDeflater"], $b["hpackInflate"], $b["hpackInflater"], $b["httpClose"], $b["httpFeed"], $b["httpFinish"], $b["httpParser"], $b["httpStream"], $b["httpTake"], $b["httpTakePart"], $b["httpUpgraded"], $b["hypot"], $b["imageShape"], $b["includes"], $b["indexOf"], $b["inflate"], $b["insert"], $b["instant"], $b["integer"], $b["isDST"], $b["isFinite"], $b["isFrozen"], $b["isLeapYear"], $b["isNaN"], $b["join"], $b["jwsSign"], $b["jwsVerify"], $b["keys"], $b["lastIndexOf"], $b["listen"], $b["lmdbAbort"], $b["lmdbClear"], $b["lmdbClose"], $b["lmdbCommit"], $b["lmdbCursor"], $b["lmdbCursorClose"], $b["lmdbDb"], $b["lmdbDelete"], $b["lmdbFirst"], $b["lmdbGet"], $b["lmdbHas"], $b["lmdbInfo"], $b["lmdbNext"], $b["lmdbOpen"], $b["lmdbPut"], $b["lmdbRead"], $b["lmdbSeek"], $b["lmdbStat"], $b["lmdbWrite"], $b["localPort"], $b["localZone"], $b["log"], $b["log10"], $b["log2"], $b["lower"], $b["map"], $b["max"], $b["maxBy"], $b["md5"], $b["micros"], $b["millis"], $b["min"], $b["minBy"], $b["minute"], $b["minutes"], $b["mkdir"], $b["mkdirSync"], $b["monotonic"], $b["month"], $b["monthName"], $b["months"], $b["next"], $b["normalize"], $b["now"], $b["number"], $b["offSignal"], $b["offset"], $b["onBytes"], $b["onData"], $b["onError"], $b["onOrAfter"], $b["onSignal"], $b["padEnd"], $b["padStart"], $b["parseDate"], $b["parseDateTime"], $b["parseJSON"], $b["parseTime"], $b["parseTimestamp"], $b["partition"], $b["pbkdf2"], $b["pending"], $b["pid"], $b["pop"], $b["pow"], $b["print"], $b["push"], $b["race"], $b["random"], $b["randomBytes"], $b["readBytes"], $b["readBytesSync"], $b["readDir"], $b["readDirSync"], $b["readFile"], $b["readFileSync"], $b["readImage"], $b["real"], $b["redisClose"], $b["redisCommand"], $b["redisFeed"], $b["redisReader"], $b["redisTake"], $b["reduce"], $b["regex"], $b["reject"], $b["remoteAddress"], $b["remove"], $b["removeAt"], $b["removeSync"], $b["rename"], $b["renameSync"], $b["repeat"], $b["replace"], $b["replaceAll"], $b["resizeImage"], $b["resolve"], $b["reverse"], $b["reversed"], $b["rmdir"], $b["rmdirSync"], $b["round"], $b["run"], $b["scriptPath"], $b["second"], $b["seconds"], $b["send"], $b["setInterval"], $b["setTimeout"], $b["settle"], $b["sha1"], $b["sha256"], $b["sha384"], $b["sha512"], $b["shift"], $b["shutdown"], $b["sin"], $b["sinh"], $b["skip"], $b["sleep"], $b["slice"], $b["some"], $b["sort"], $b["sorted"], $b["spawn"], $b["split"], $b["sqliteClose"], $b["sqliteCompiled"], $b["sqliteExec"], $b["sqliteFinalize"], $b["sqliteOpen"], $b["sqlitePrepare"], $b["sqliteQuery"], $b["sqliteRun"], $b["sqrt"], $b["startOf"], $b["startTls"], $b["startsWith"], $b["stat"], $b["statSync"], $b["stderr"], $b["string"], $b["sum"], $b["tan"], $b["tanh"], $b["time"], $b["timingSafeEqual"], $b["toArray"], $b["toBytes"], $b["toExponential"], $b["toFixed"], $b["toJSON"], $b["toLowerCase"], $b["toPrecision"], $b["toReversed"], $b["toUpperCase"], $b["trim"], $b["trimEnd"], $b["trimStart"], $b["trunc"], $b["unique"], $b["unshift"], $b["unzstd"], $b["upper"], $b["utc"], $b["values"], $b["weekday"], $b["weeks"], $b["without"], $b["writeBytes"], $b["writeBytesSync"], $b["writeFile"], $b["writeFileSync"], $b["wsClose"], $b["wsOnClose"], $b["wsOnMessage"], $b["wsOpen"], $b["wsSend"], $b["wsSendBytes"], $b["year"], $b["years"], $b["zip"], $b["zone"], $b["zstd"]);
