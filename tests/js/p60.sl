// `slate:redis`, on both back ends, against servers written in slate.
//
// **The client is slate source and is shared; the RESP reader under it is not.** The interpreter's
// is hiredis and the JavaScript host's is `js_rt_redis.sysl`, a port of hiredis's `read.c` -- so
// this file is where the two readings of one protocol are made to agree: every reply type RESP2 and
// RESP3 can say, a reply split across packets, pipelining, a push, the two failure channels, and
// every sentence a stream that stops being RESP is answered with, whole.
//
// **Each server answers the n-th command it hears on a connection with the n-th reply it was
// given**, so nothing depends on how the commands were cut into packets. A broken stream ends its
// connection for good, which is why every wrong reply below gets a server of its own.

import { listen, onBytes, send, close, localPort } from slate:net
import { redis } from slate:redis

watchdog()
    throw "the redis corpus did not finish in time"

val dog = setTimeout(watchdog, 10000)

fake(replies)
    serving(conn)
        var n = 0

        heard(chunk)
            if chunk == null
                close(conn)

                return

            if n < replies.length
                send(conn, replies[n])

                n = n + 1

        onBytes(conn, heard)

    listen(0, serving)

said(r) = if r.ok then r.value else s"error: ${r.error}"

// Every command in `commands` in turn, each answered by the reply at the same position.
async asking(title, replies, commands)
    print(s"-- ${title}")

    val server = fake(replies)
    val r = (await redis("127.0.0.1", localPort(server))).value

    for c in commands
        print(said(await r.command(...c)))

    r.close()
    close(server)

// One wrong reply, and what the connection says about it.
async broken(reply)
    val server = fake([reply])
    val r = (await redis("127.0.0.1", localPort(server))).value

    print(said(await r.command("GET", "k")))

    close(server)

async main()
    await asking("resp2", ["+OK\r\n", ":42\r\n", ":-9223372036854775808\r\n", "$5\r\nhello\r\n", "$0\r\n\r\n",
        "$-1\r\n", "*3\r\n$1\r\na\r\n:2\r\n$-1\r\n", "*-1\r\n", "*0\r\n", "*2\r\n*1\r\n:1\r\n$1\r\nx\r\n",
        "*2\r\n-ERR inner\r\n:1\r\n", "-ERR unknown command 'NOPE'\r\n"],
        [["PING"], ["INCR", "n"], ["MIN"], ["GET", "k"], ["GET", "e"], ["GET", "gone"], ["LRANGE", "l", "0", "2"],
            ["NIL"], ["EMPTY"], ["NESTED"], ["EXEC"], ["NOPE"]])

    await asking("resp3", [",3.25\r\n", ",-1.5e3\r\n", "#t\r\n", "#F\r\n", "_\r\n",
        "%2\r\n$1\r\na\r\n:1\r\n$1\r\nb\r\n:2\r\n", "%1\r\n:7\r\n$1\r\nv\r\n", "%2\r\n$1\r\nk\r\n:1\r\n$1\r\nk\r\n:2\r\n",
        "~2\r\n$1\r\nx\r\n$1\r\ny\r\n", "(3492890328409238509324850943850943825024\r\n",
        "=15\r\ntxt:hello world\r\n", "|1\r\n+key\r\n+value\r\n"],
        [["ZSCORE"], ["NEG"], ["T"], ["F"], ["NULL"], ["HGETALL"], ["INTKEY"], ["TWICE"], ["SMEMBERS"], ["BIG"],
            ["LOLWUT"], ["ATTR"]])

    // A bulk string that is not UTF-8 is its bytes, as an array of numbers.
    await asking("bytes", [concat(concat(toBytes("$3\r\n"), [255, 254, 0]), toBytes("\r\n"))], [["GET", "jpeg"]])

    await splitting()
    await pipelining()
    await pushing()
    await channels()
    await counted()

    print("-- broken")

    await broken("this is not RESP\r\n")
    await broken("\r\n")
    await broken(bytes([128, 13, 10]))
    await broken("\"x\r\n")
    await broken(":12a\r\n")
    await broken(":\r\n")
    await broken(":01\r\n")
    await broken(":-0\r\n")
    await broken(":9223372036854775808\r\n")
    await broken("$abc\r\n")
    await broken("$-2\r\n")
    await broken("*x\r\n")
    await broken("*-2\r\n")
    await broken("*4294967296\r\n")
    await broken("#x\r\n")
    await broken("_x\r\n")
    await broken(",abc\r\n")
    await broken(",1e400\r\n")
    await broken("," + repeat("1", 330) + "\r\n")
    await broken("(12a\r\n")
    await broken("+a\rb\r\n")
    await broken("=3\r\nabc\r\n")
    await broken("=5\r\nabcde\r\n")
    await broken(repeat("*1\r\n", 1025))

    // A reply that goes wrong half way through an array is wrong too.
    await broken("*2\r\n:1\r\n?\r\n")

    clearTimeout(dog)

// A reply in pieces is one reply: a bulk string cut in its body, and an array cut between elements.
async splitting()
    print("-- split")

    halves(conn)
        var n = 0

        heard(chunk)
            if chunk == null
                close(conn)

                return

            later(text)
                () -> send(conn, text)

            if n == 0
                send(conn, "$11\r\nhel")
                setTimeout(later("lo world\r\n"), 30)
            else
                send(conn, "*2\r\n:1")
                setTimeout(later("\r\n:2\r\n"), 30)

            n = n + 1

        onBytes(conn, heard)

    val server = listen(0, halves)
    val r = (await redis("127.0.0.1", localPort(server))).value

    print(said(await r.command("GET", "k")))
    print(said(await r.command("LRANGE", "l")))

    r.close()
    close(server)

// Commands issued without awaiting are answered in the order they went out. The server waits for
// the third before answering any, so the three replies arrive together.
async pipelining()
    print("-- pipelined")

    batched(conn)
        var seen = ""

        heard(chunk)
            if chunk == null
                close(conn)

                return

            seen = seen + fromBytes(chunk).value

            if !seen.endsWith("$1\r\nc\r\n") then return

            send(conn, "$3\r\none\r\n$3\r\ntwo\r\n$5\r\nthree\r\n")

        onBytes(conn, heard)

    val server = listen(0, batched)
    val r = (await redis("127.0.0.1", localPort(server))).value

    val a = r.command("GET", "a")
    val b = r.command("GET", "b")
    val c = r.command("GET", "c")

    print(said(await a), said(await b), said(await c))

    r.close()
    close(server)

// A push goes to `onPush`, before and between replies, and never answers a waiting command.
async pushing()
    print("-- push")

    val server = fake([">3\r\n$7\r\nmessage\r\n$4\r\nnews\r\n$5\r\nhello\r\n$3\r\nred\r\n>2\r\n$4\r\nkind\r\n:1\r\n:5\r\n"])
    val r = (await redis("127.0.0.1", localPort(server))).value

    seen(p)
        print("pushed", p)

    r.onPush(seen)

    print(said(await r.command("GET", "colour")))

    r.close()
    close(server)

// The two channels: a server that goes away answers what is waiting, a stream that broke closes the
// client, and a command on a closed client throws.
async channels()
    print("-- channels")

    rude(conn)
        heard(chunk)
            close(conn)

        onBytes(conn, heard)

    val gone = listen(0, rude)
    val r = (await redis("127.0.0.1", localPort(gone))).value

    print(said(await r.command("GET", "k")))
    print(await r.command("PING") catch e -> s"threw: ${e}")

    close(gone)

    val bad = fake(["?\r\n"])
    val s = (await redis("127.0.0.1", localPort(bad))).value

    print(said(await s.command("GET", "k")))
    print(await s.command("PING") catch e -> s"threw: ${e}")

    close(bad)

    val ok = fake(["+OK\r\n"])
    val t = (await redis("127.0.0.1", localPort(ok))).value

    t.close()
    print(await t.command("PING") catch e -> s"threw: ${e}")

    close(ok)

    val nobody = await redis("127.0.0.1", 1)

    print(nobody.ok)

// Every argument crosses as a counted string -- text, bytes, and a command assembled and spread.
async counted()
    print("-- wire")

    watcher(conn)
        heard(chunk)
            if chunk == null
                close(conn)

                return

            print(toJSON(chunk.toArray()))
            send(conn, "+OK\r\n")

        onBytes(conn, heard)

    val server = listen(0, watcher)
    val r = (await redis("127.0.0.1", localPort(server))).value

    await r.command("SET", "k", "a\r\nGET evil\r\n")
    await r.command("SET", "é", bytes([0, 255]))
    await r.command(...concat(["RPUSH", "l"], ["a", "b"]))

    r.close()
    close(server)

main()
