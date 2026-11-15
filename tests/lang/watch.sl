// `watch` and `unwatch` in `slate:fs`: being told what changed under a directory.
//
// **Every wait here is a wait FOR an event, with a limit, and never a fixed sleep.** A watcher's
// events arrive whenever the operating system gets round to them, and a loaded machine is slower
// than an idle one by more than any fixed pause would allow for. So each test polls what its
// watcher has heard until the event it wants is there or `Patience` runs out -- which costs nothing
// when the event is prompt and fails rather than hangs when it never comes.
//
// **A watcher is proved to be listening before anything is changed.** FSEvents starts its stream a
// moment after it is asked to, and a change made in that moment is not reported to anybody. So
// `listening` writes probe files until one of them is heard, and only then does a test make the
// change it is about. Every assertion names its own file, so a late probe event cannot be mistaken
// for the one a test wanted.
//
// **Off macOS `watch` answers an error rather than watching one level deep**, so every test that
// needs a watcher skips there, and says why.

import { watch, unwatch, mkdirSync, writeFileSync, appendFileSync, removeSync, renameSync, rmdirSync, readDirSync, statSync } from slate:fs
import { pid } from slate:process

// How long a test waits for an event before it says it never came, in milliseconds.
val Patience = 5000

// A value whose type the checker cannot see, so that a refusal is the MACHINE's rather than the
// pass's. `tests/lang/spawn.sl` has the same helper for the same reason.
anything(v) = v

var made = 0

// A directory of this test's own. **Named for the process**, because the interpreter's run and
// node's run of this file are two processes that may be running at the same moment.
scratch(name)
    made = made + 1

    val dir = "/tmp/slate-watch-" + string(pid()) + "-" + string(made) + "-" + name

    mkdirSync(dir)
    dir

// Give a scratch directory back, with everything in it.
scrub(dir)
    for name in readDirSync(dir).value
        val inside = dir + "/" + name

        if statSync(inside).value.isDir
            scrub(inside)
        else
            removeSync(inside)

    rmdirSync(dir)

// Whether a probe has been heard.
probed(heard) = heard.some(e -> e.path != null && e.path.contains(".probe"))

// Watch `dir`, keeping everything it reports, and come back once the watcher has been heard from.
async listening(dir)
    val heard = []
    val started = watch(dir, e -> heard.push(e))

    if !started.ok
        scrub(dir)
        skip(started.error)

    var n = 0

    while !probed(heard)
        if n * 20 > Patience
            unwatch(started.value)
            assert(false, "the watcher never heard its own probes")

        n = n + 1
        writeFileSync(dir + "/.probe" + string(n), "x")
        await sleep(20)

    { id: started.value, heard: heard }

// Wait until the watcher has heard something `wanted` accepts, and say whether it did.
async heardOf(w, wanted)
    var waited = 0

    while !w.heard.some(wanted)
        if waited > Patience then return false

        await sleep(10)
        waited = waited + 10

    true

// -- what each change is heard as -----------------------------------------------------------------

@test
async A_NEW_FILE_IS_HEARD_AS_A_RENAME_NAMING_IT()
    val dir = scratch("create")
    val w = await listening(dir)

    writeFileSync(dir + "/fresh.txt", "one")

    val came = await heardOf(w, e -> e.path == "fresh.txt")

    unwatch(w.id)

    assert(came, "nothing was heard about fresh.txt")

    // **The event is the two fields and nothing else**: the path relative to the directory, and
    // node's word for a name appearing.
    assertEq(w.heard.find(e -> e.path == "fresh.txt"), { path: "fresh.txt", kind: "rename" })
    scrub(dir)

@test
async A_FILE_WRITTEN_TO_IS_HEARD_AND_ITS_KIND_IS_ONE_OF_THE_TWO_WORDS()
    val dir = scratch("modify")

    writeFileSync(dir + "/kept.txt", "one")

    val w = await listening(dir)

    appendFileSync(dir + "/kept.txt", " two")

    val came = await heardOf(w, e -> e.path == "kept.txt")

    unwatch(w.id)

    assert(came, "nothing was heard about kept.txt")

    // **Not pinned to `change`, and that is FSEvents and not slate.** It carries a file's recent
    // history in the flags of a later event, so a file made a moment ago is still reported as a
    // rename when it is written to. What a program may count on is that it is told.
    for e in w.heard.filter(e -> e.path == "kept.txt")
        assert(e.kind == "change" || e.kind == "rename", "an event's kind is change or rename")

    scrub(dir)

@test
async A_REMOVED_FILE_IS_HEARD_AS_A_RENAME()
    val dir = scratch("remove")

    writeFileSync(dir + "/doomed.txt", "one")

    val w = await listening(dir)

    removeSync(dir + "/doomed.txt")

    val came = await heardOf(w, e -> e.path == "doomed.txt" && e.kind == "rename")

    unwatch(w.id)

    assert(came, "the removal was not heard as a rename")
    scrub(dir)

@test
async A_RENAME_IS_HEARD_FOR_THE_OLD_NAME_AND_THE_NEW_ONE()
    val dir = scratch("rename")

    writeFileSync(dir + "/before.txt", "one")

    val w = await listening(dir)

    renameSync(dir + "/before.txt", dir + "/after.txt")

    val old = await heardOf(w, e -> e.path == "before.txt" && e.kind == "rename")
    val fresh = await heardOf(w, e -> e.path == "after.txt" && e.kind == "rename")

    unwatch(w.id)

    assert(old, "the old name was not heard")
    assert(fresh, "the new name was not heard")
    scrub(dir)

// -- the whole tree -------------------------------------------------------------------------------

@test
async A_CHANGE_IN_A_SUBDIRECTORY_IS_HEARD_WITH_ITS_PATH_FROM_THE_TOP()
    val dir = scratch("deep")

    mkdirSync(dir + "/sub")

    val w = await listening(dir)

    writeFileSync(dir + "/sub/inner.txt", "one")

    val came = await heardOf(w, e -> e.path == "sub/inner.txt")

    unwatch(w.id)

    assert(came, "nothing was heard about sub/inner.txt")
    scrub(dir)

@test
async A_DIRECTORY_MADE_AFTER_THE_WATCH_BEGAN_IS_WATCHED_TOO()
    // **The tree is the tree as it is NOW**, not as it was when the watch began: a development
    // server whose project grows a directory has to hear what is written into it.
    val dir = scratch("grown")
    val w = await listening(dir)

    mkdirSync(dir + "/later")
    writeFileSync(dir + "/later/new.txt", "one")

    val came = await heardOf(w, e -> e.path == "later/new.txt")

    unwatch(w.id)

    assert(came, "nothing was heard about later/new.txt")
    scrub(dir)

// -- stopping -------------------------------------------------------------------------------------

@test
async A_STOPPED_WATCHER_HEARS_NOTHING_MORE()
    // **An absence needs a witness**, so a second watcher on the same directory stays running: once
    // it has heard the change, the stopped one has had every chance to hear it too.
    val dir = scratch("stop")
    val stopped = await listening(dir)
    val witness = await listening(dir)

    unwatch(stopped.id)
    writeFileSync(dir + "/after.txt", "one")

    val came = await heardOf(witness, e -> e.path == "after.txt")

    unwatch(witness.id)

    assert(came, "the witness heard nothing")
    assertEq(stopped.heard.some(e -> e.path == "after.txt"), false)
    scrub(dir)

@test
async STOPPING_A_WATCHER_TWICE_OR_ONE_THAT_IS_NOT_THERE_IS_NOT_AN_ERROR()
    val dir = scratch("twice")
    val w = await listening(dir)

    assertEq(unwatch(w.id), null)
    assertEq(unwatch(w.id), null)
    assertEq(unwatch(987654321), null)
    scrub(dir)

@test
async unwatch_GIVEN_A_TIMER_S_ID_LEAVES_THE_TIMER_ALONE()
    // Ids come from one counter in the interpreter, so this is what says `unwatch` stops only a
    // watcher and never whatever else an id happens to name.
    var fired = false

    ring()
        fired = true

    val t = setTimeout(ring, 20)

    unwatch(t)
    await sleep(60)
    assert(fired)

// -- keeping the program alive --------------------------------------------------------------------

@test
async A_WATCHER_KEEPS_THE_PROGRAM_RUNNING_UNTIL_IT_IS_STOPPED()
    // **Nothing but the watcher can wake this await**: `listening`'s timers have all run by the
    // time it answers, the write is a blocking one, and there is no timer here at all. A watcher
    // that did not keep the program alive would leave the loop empty with the promise unsettled,
    // which both back ends report as a failure -- and one that never let go would leave this test's
    // handle open, which the interpreter names.
    val dir = scratch("alive")
    val heardFinal = pending()
    var settled = false
    val heard = []
    val started = watch(dir, e ->
        heard.push(e)

        if e.path == "final.txt" && !settled
            settled = true
            settle(heardFinal, true))

    if !started.ok
        scrub(dir)
        skip(started.error)

    var n = 0

    while !probed(heard) && n * 20 <= Patience
        n = n + 1
        writeFileSync(dir + "/.probe" + string(n), "x")
        await sleep(20)

    writeFileSync(dir + "/final.txt", "x")

    assertEq(await heardFinal, true)
    unwatch(started.value)
    scrub(dir)

// -- what is refused, and how ---------------------------------------------------------------------

@test
A_DIRECTORY_THAT_IS_NOT_THERE_IS_AN_ERROR_RESULT()
    val r = watch("/tmp/slate-watch-nowhere-" + string(pid()), e -> e)

    assertEq(r.ok, false)
    assert(r.error.contains("cannot watch /tmp/slate-watch-nowhere-"), r.error)
    assert(r.error.contains("ENOENT"), r.error)

@test
A_FILE_IS_NOT_A_DIRECTORY_TO_WATCH()
    val dir = scratch("file")

    writeFileSync(dir + "/plain.txt", "one")

    val r = watch(dir + "/plain.txt", e -> e)

    assertEq(r.ok, false)
    assert(r.error.contains("it is not a directory"), r.error)
    scrub(dir)

@test
A_CALL_WRITTEN_WRONG_IS_A_FAULT_AND_NOT_A_RESULT()
    // **A wrong argument is a defect in the program**, which is `slate:fs`'s rule: `readFile(42)`
    // faults where `readFile("/gone")` answers.
    assertFaults(() -> watch(anything(42), e -> e), "`watch` takes a directory, and this is")
    assertFaults(() -> watch("/tmp", anything(3)), "`watch` needs a function to call")
    assertFaults(() -> anything(watch)("/tmp"), "`watch` takes a directory and a function, and was given 1 argument")
    assertFaults(() -> unwatch(anything("x")), "a watcher is stopped by the id `watch` answered")
