// Every way a call can lead out of one file and back into it.
//
// **A return puts the caller's own code and file back**, and while a program is one file that is
// invisible: the file is always source zero and the code is always the one buffer. These exports
// exist so that a caller in another file goes away and comes back by each of the routes the machine
// has -- an ordinary call, a call through a callback, a constructor, a builtin running a callback, a
// generator stepped by whoever wants a value, and a fault unwinding several frames.

// The rung a caller climbs back onto: it calls what it was handed, so the frames alternate between
// this file and the caller's.
export ladder(f, n) = if n <= 0 then 0 else 1 + f(n - 1)

export class Box
    val room = 1

    new(held) = { held: held }

    holding(self) = self.held * 2

export doubled(x) = x * 2

export counting(n) =
    for i in 0..<n
        yield i * 10

export raises() = 1 \ 0

// An `await` is the other way a machine is put back, and a rejection is the other way again: the
// scheduler pops the frame the `await` wrote and carries on -- or hands it the fault -- and either
// way the frame is the only record of whose code and whose file that is.
export async waiting(n)
    await sleep(1)
    n * 2

export async refusing()
    await sleep(1)
    1 \ 0
