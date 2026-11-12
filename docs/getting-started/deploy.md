---
title: Deploy to Linux
weight: 15
summary: Install slate on a Linux server, run a program under `slate:cluster`, and keep it up with systemd.
---

# Deploy to Linux

A deployment is three things: the binary on the machine, a program that uses every core with
[`slate:cluster`](../library/cluster.md), and a service manager that starts it, restarts it, and tells it
when to drain or reload. None of the three needs anything beyond what apt and systemd already give a
Linux box.

## Installing

**There is no prebuilt Linux binary and no Linux formula as of 0.2.0.** The releases carry macOS binaries only, and Linux
builds return once sysl publishes Linux builds. Until then, build slate from source on the box, which is a
clone and one command given [sysl](https://sysl.sh) installed (see the README's *Installing*). A bare
container image also wants `tzdata`, which `zone(...)` reads from and any real installation already has.

## A program that uses every core

One slate process is one thread; [`cluster`](../library/cluster.md) runs the program N times and
spreads connections over the copies, with the supervisor as the process a service manager watches.
`PORT` comes from the environment because systemd is what sets it, not the program:

```slate
import { cluster } from slate:cluster
import { env } from slate:process

val port = number(env("PORT") ?? "8080")

await cluster({}, async w ->
    val app = await w.serve(port, req -> "hello from worker " + string(w.workerId))

    w.onShutdown(async () ->
        print("worker " + string(w.workerId) + " is finishing what it has")))
```

This is the whole of `entry.sl`. **It is a fragment on this page and not run** — it holds a listening
socket open forever, which is exactly what a deployment wants and exactly what a documentation harness
that runs every program to completion cannot. What it does when a signal arrives is
[`slate:cluster`'s](../library/cluster.md) own rule and does not change here:

- **`SIGTERM` drains.** The supervisor stops accepting, tells every worker to shut down, and each
  worker runs what it registered with `onShutdown` before ending — a request already being answered
  finishes; nothing new is accepted.
- **`SIGHUP` rolls.** The workers are replaced one at a time, and the replacement is serving before the
  one it replaces is asked to leave, so the port is never unserved — which is how new code arrives
  without dropping a connection.

## The unit

One user, one working directory, one `ExecStart`. `KillSignal=SIGTERM` is systemd's default and is
named here only so the drain above is not an accident of it; `ExecReload` is the one line that turns
`systemctl reload` into the `SIGHUP` the cluster already knows what to do with.

```
[Unit]
Description=myapp
After=network.target

[Service]
Type=simple
User=myapp
Group=myapp
WorkingDirectory=/srv/myapp
ExecStart=/usr/local/bin/slate entry.sl
Environment=PORT=8080
Restart=on-failure
RestartSec=1
KillSignal=SIGTERM
TimeoutStopSec=15
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

`ExecStart` is the path of the `slate` binary you built, `/usr/local/bin/slate` here. **`TimeoutStopSec` should be a little longer
than `cluster`'s own `drainMillis`** (ten seconds by default) — systemd sends `SIGKILL` at the timeout
whether or not the drain finished, so a shorter one can cut off a worker that was still finishing a
slow request.

A dedicated user owns nothing else on the box:

```
sudo useradd --system --home /srv/myapp --shell /usr/sbin/nologin myapp
sudo mkdir -p /srv/myapp
sudo cp entry.sl /srv/myapp/
sudo chown -R myapp:myapp /srv/myapp
```

## Running it

```
sudo cp myapp.service /etc/systemd/system/myapp.service
sudo systemctl daemon-reload
sudo systemctl enable --now myapp
```

`systemctl status myapp` and `journalctl -u myapp -f` are the ordinary way to watch it; the `print` in
`onShutdown` above lands in the journal. **A new build is picked up with a reload, not a restart** —
`sudo systemctl reload myapp` sends the `SIGHUP` that rolls the workers one at a time, where `sudo
systemctl restart myapp` would take the whole thing down and back up, dropping every connection open at
the moment it stopped accepting. Stopping the service outright is the drain:

```
sudo systemctl stop myapp
```

which is `SIGTERM`, waits out the `onShutdown` handlers up to `TimeoutStopSec`, and only then ends the
process.

There is no pm2 here and no Redis: `slate:cluster` is one process's cores, and a program on one box that
needs a message bus between workers has [`slate:cluster`'s own `publish`/`subscribe`](../library/cluster.md#the-supervisor-is-the-message-bus)
rather than a second service to run and keep up.
