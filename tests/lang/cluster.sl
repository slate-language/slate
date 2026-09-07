// A worker cluster, driven from the SUPERVISOR's side.
//
// **The workers are `/bin/sh`, which is the same decision `spawn.sl` makes and for the same reason.**
// A cluster starts another copy of the program it is running inside, and the program running these
// tests is a test suite — so a real slate worker here would be the suite starting itself. What is
// being tested is the supervisor: that it starts what it was asked for, numbers the workers, carries
// a published value from one to the others, starts a worker again when it dies, and drains or kills
// on the way out. A shell speaking the same one-JSON-value-per-line channel says all of it.
//
// **What a shell CANNOT do is take a connection**, a socket crossing only between two slate programs
// — so the round-robin half of the module is not here. `tests_cluster.sysl` drives a real worker over
// a real channel from the other side, and the two together are the protocol.
//
// **EVERY TEST SHUTS THE CLUSTER DOWN BEFORE IT ASSERTS ANYTHING.** A live child keeps the program
// alive, so an assertion that fails between starting a cluster and stopping it does not fail the
// test — it hangs the whole suite with nothing printed. So each of these gathers what it saw, stops,
// waits for the promise, and only then says what it expected.

import { cluster, isPrimary, isWorker, workerId } from slate:cluster
import { cpus } from slate:process

// A value whose type the checker cannot see, so a refusal is the machine's rather than the pass's.
anything(v) = v

// A shell worker: it says hello, then answers the lines the supervisor sends until it is told to go.
// **The brackets are not decoration**: a trailing `+` does not continue a line outside them.
shellWorker(extra) = (
    "printf '{\"$cluster\":\"ready\"}\\n' >&3\n" +
    "while IFS= read -r line <&3; do\n" +
    "  case \"$line\" in\n" +
    "    *'\"shutdown\"'*) exit 0 ;;\n" +
    extra +
    "    *) : ;;\n" +
    "  esac\n" +
    "done\n")

// The arm that publishes once this worker has been given its number.
val publishesOnce = "    *'\"id\"'*) printf '{\"$cluster\":\"publish\",\"topic\":\"t\",\"value\":\"x\"}\\n' >&3 ;;\n"

// The arm that answers a published value on ONE topic with a publish of its own.
//
// **It matches the topic and not the word `publish`**, and that is not fussiness: an arm answering
// every publish answers its own echo, so two workers echoing each other never stop. The topic it
// answers ON is one nothing listens for.
echoesTopic(topic) = (
    "    *'\"topic\":\"" + topic + "\"'*) " +
    "printf '{\"$cluster\":\"publish\",\"topic\":\"echo\",\"value\":\"e\"}\\n' >&3 ;;\n")

// Wait until something is true, or give up. **A deadline and not a fixed sleep**: a test that waits
// long enough on a quiet machine is a test that fails on a busy one.
async until(f, ms)
    var left = ms

    while left > 0 && !f()
        await sleep(20)

        left = left - 20

    f()

@test
A_PROGRAM_NOBODY_STARTED_IS_THE_SUPERVISOR_AND_IS_NO_WORKER()
    assert(isPrimary)
    assert(!isWorker)
    assertEq(workerId(), 0)

@test
THE_MACHINE_SAYS_HOW_MANY_THINGS_IT_CAN_DO_AT_ONCE()
    // **Never zero**, whatever the machine reports: a program dividing its work by this would be
    // dividing by nothing.
    assert(cpus() >= 1)
    assert(cpus() is integer)

@test
A_CLUSTER_OF_NO_WORKERS_IS_REFUSED()
    assertFaults(() -> cluster({ workers: 0 }, w -> null),
        "a cluster runs at least one worker, and was asked for 0")

@test
A_WORKER_COUNT_THAT_IS_NOT_A_NUMBER_IS_REFUSED()
    assertFaults(() -> cluster({ workers: anything("four") }, w -> null),
        "`workers` is how many processes to run")

@test
A_SCHEDULING_NOBODY_HAS_IS_REFUSED_AND_THE_TWO_NAMES_ARE_SAID_BACK()
    assertFaults(() -> cluster({ workers: 1, scheduling: "random" }, w -> null),
        "`scheduling` is \"roundRobin\" or \"reusePort\"")

@test
OPTIONS_THAT_ARE_NOT_AN_OBJECT_ARE_REFUSED()
    assertFaults(() -> cluster(anything(4), w -> null), "`cluster` takes its options as an object")

@test
async THE_SUPERVISOR_STARTS_WHAT_IT_WAS_ASKED_FOR_AND_NUMBERS_THEM_FROM_ONE()
    var said = []
    var gone = []
    var howMany = 0
    var stop = null

    val down = cluster({ workers: 3, exec: "/bin/sh", args: ["-c", shellWorker(publishesOnce)],
        primary: sup ->
            howMany = sup.workers
            stop = sup.shutdown

            sup.subscribe("t", v -> said.push(v))
            sup.onWorkerExit(e -> gone.push(e.id)) },
        w -> null)

    // Every worker said hello, was answered with its number, and published on the strength of it.
    val allThree = await until(() -> said.length == 3, 8000)

    stop()

    await down

    assertEq(howMany, 3)
    assert(allThree)

    // **The numbers are 1, 2 and 3 and they are the order they were started in**, which is what makes
    // a log line naming a worker mean anything.
    assertEq(gone.sorted(), [1, 2, 3])

@test
async A_PUBLISHED_VALUE_REACHES_EVERY_OTHER_WORKER_AND_NOT_THE_ONE_THAT_SENT_IT()
    // One worker, which publishes once and echoes anything published to it. If a publisher heard
    // itself there would be an echo — and, since the echo is a publish too, it would not stop.
    var heard = []
    var echoes = []
    var stop = null

    val down = cluster({ workers: 1, exec: "/bin/sh",
        args: ["-c", shellWorker(publishesOnce + echoesTopic("t"))],
        primary: sup ->
            stop = sup.shutdown

            sup.subscribe("t", v -> heard.push(v))
            sup.subscribe("echo", v -> echoes.push(v)) },
        w -> null)

    val published = await until(() -> heard.length == 1, 8000)

    // Long enough for an echo to have come back had one been sent.
    await sleep(200)

    val quiet = echoes.length

    stop()

    await down

    assert(published)
    assertEq(quiet, 0)

@test
async A_SUPERVISOR_CAN_PUBLISH_TO_EVERY_WORKER()
    var echoes = []
    var ready = []
    var send = null
    var stop = null

    val down = cluster({ workers: 2, exec: "/bin/sh",
        args: ["-c", shellWorker(publishesOnce + echoesTopic("go"))],
        primary: sup ->
            send = sup.publish
            stop = sup.shutdown

            sup.subscribe("t", v -> ready.push(v))
            sup.subscribe("echo", v -> echoes.push(v)) },
        w -> null)

    val bothUp = await until(() -> ready.length == 2, 8000)

    send("go", 1)

    // **Both workers**, where a worker publishing the same thing would have reached only the other.
    val bothHeard = await until(() -> echoes.length == 2, 8000)

    stop()

    await down

    assert(bothUp)
    assert(bothHeard)

@test
async A_WORKER_THAT_DIES_IS_STARTED_AGAIN_UNDER_A_NEW_NUMBER()
    var gone = []
    var stop = null

    // A worker that cannot even say hello, which is the failure the backoff exists for. The ceiling
    // is tiny here so that the test is quick; in a deployment it is thirty seconds.
    val down = cluster({ workers: 1, exec: "/bin/sh", args: ["-c", "exit 3"], maxBackoffMillis: 20,
        primary: sup ->
            stop = sup.shutdown

            sup.onWorkerExit(e -> gone.push(e.id)) },
        w -> null)

    val threeDeaths = await until(() -> gone.length >= 3, 8000)

    stop()

    await down

    assert(threeDeaths)

    // **Each one is a NEW worker and says so.** A restarted process is not the one that died, and a
    // log that reused the number would say two things had happened to one thing.
    assert(gone[1] > gone[0])
    assert(gone[2] > gone[1])

@test
async A_WORKER_THAT_IGNORES_A_SHUTDOWN_IS_KILLED_AFTER_drainMillis()
    var how = []
    var stop = null

    // It says hello and then stops listening, which is what a worker stuck in a request looks like.
    val script = "printf '{\"$cluster\":\"ready\"}\\n' >&3\nsleep 30\n"

    val down = cluster({ workers: 1, exec: "/bin/sh", args: ["-c", script], drainMillis: 300,
        primary: sup ->
            stop = sup.shutdown

            sup.onWorkerExit(e -> how.push(e.signal)) },
        w -> null)

    await sleep(300)

    stop()

    await down

    // **`SIGKILL` is 9**, and it is what is left once a drain has been asked for and waited out.
    assertEq(how, [9])

@test
async A_SHUTDOWN_ASKED_FOR_TWICE_IS_NOT_AN_ERROR()
    var stop = null

    val down = cluster({ workers: 1, exec: "/bin/sh", args: ["-c", shellWorker("")],
        primary: sup ->
            stop = sup.shutdown },
        w -> null)

    stop()

    // **A shutdown is the sort of thing a signal handler and a program's own last statement can both
    // reach**, so asking twice does nothing the second time rather than complaining.
    stop()

    await down

    assert(true)
