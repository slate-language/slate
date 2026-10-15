---
title: The packages
weight: 50
summary: What is written in slate today — an API server, a PostgreSQL client, a logger, configuration, a UI framework and a component library.
---

# The packages

Six packages, all in the [slate-language](https://github.com/slate-language) organisation, all
written in slate. Each is installed the same way:

```
slate install github.com/slate-language/<name>
```

which writes the dependency into `package.sl`, fetches it into `$HOME/.slate/pkg`, and records the
hash of the extracted tree in `slate.sum`. [Packages](../reference/packages.md) is the reference for
the manifest, the cache and what that hash guarantees.

**Installing one runs nothing.** A manifest is read as data wherever a tool is working out what to
fetch, so the `scripts` a project may declare for `slate run` are its own and are never read out of
anything it depends on — see [Scripts](../reference/packages.md).

**These are packages rather than `slate:` modules on purpose.** What ships inside the compiler is the
infrastructure an API server needs — sockets, TLS, HTTP, a file system, digests. A framework is not
that: it iterates far faster than the language does, and baking one in would tie every framework fix
to a language release.

## A server

### sluice — an API server

```
slate install github.com/slate-language/sluice
```

**A request is a value, a handler is a function of it, and everything else is composition.** No
`next`, no mutable response, no ambient context, no `app.use()`.

```slate
import { api, stack, body, bearer, problem, json } from sluice
import { serve } from slate:http

type NewNote = { title: string, text: string, pinned?: boolean }
```

<https://github.com/slate-language/sluice>

### pg — PostgreSQL

```
slate install github.com/slate-language/pg
```

**A PostgreSQL client written in slate, speaking the wire protocol itself.** No libpq, no C binding,
no blocking call: it is `slate:net` and `slate:crypto` and about a thousand lines of slate.

```slate
import { connect } from pg
```

<https://github.com/slate-language/pg>

### logger — structured logging

```
slate install github.com/slate-language/logger
```

**A record is a value and a sink is a function of it.** What a record looks like is a rendering
somebody chooses rather than something this package decided on the way out — so a terminal gets a
line, a collector gets a JSON object, and a test gets the record itself with nothing rendered at all.

```slate
import { info, warn, setLevel, setSink, json } from logger
```

<https://github.com/slate-language/logger>

### env — configuration from the environment

```
slate install github.com/slate-language/env
```

**The configuration is read once, converted, and checked against a type the program declares — and a
program with a bad one is told every problem at once, before it starts.** `env(Shape, { defaults,
source, file })` answers `{ ok: true, value }` or `{ ok: false, error }`: it reads the whole
environment and an optional dotenv file, converts each value to the kind the shape declares, and lists
every problem without ever printing a value. `dotenv(text)` is exported too. It needs slate 0.1.22 or
later.

```slate
import { env } from env
import { stderr, exit } from slate:process

type Config = { PORT: integer, DATABASE_URL: string, DEBUG?: boolean }

val config = env(Config, { defaults: { PORT: "8080" }, file: ".env" }) match
    { ok: true, value } -> value
    { error } ->
        stderr(error + "\n")
        exit(1)
```

<https://github.com/slate-language/env>

## A page

### lath — a UI framework

```
slate install github.com/slate-language/lath
```

**A React-shaped UI framework.** A component is a function of its props, state lives in hooks kept on
call-order slots, and a change re-renders the component that owns it while the reconciler matches the
new children against the old by key and moves them into place — React's model **and** React's
mechanism.

```slate
import { createElement, Fragment, mount, useState } from lath
import { domHost } from lath/dom
```

The name is the strip a roof's slates are nailed to — the frame the pieces hang on.

<https://github.com/slate-language/lath>

### mortar — components for lath

```
slate install github.com/slate-language/mortar
```

**A component library for lath**, twenty-seven components with a stylesheet beside each one — modern
css, native nesting, custom properties for the theme. **No preprocessor, no build step, and nothing
to fetch at run time**: a stylesheet is a file the compiler reads and the program carries, so a page
ends up with a `<style>` for exactly the components it rendered, on a server and in a browser alike.

```slate
import { Card, Page, Theme } from mortar
```

<https://github.com/slate-language/mortar>

## What a package may not do

**A package cannot have a native of its own.** Everything a package can reach is either slate or
something the compiler already binds, which is why [pg](https://github.com/slate-language/pg) had to
wait for `slate:crypto` — PostgreSQL 14 and later default to SCRAM-SHA-256, so a client needs SHA-256,
HMAC, PBKDF2 and a nonce from the kernel before it can log in at all.

**That is the shape to expect from a package: not a missing convenience, but a door the language
never opened.** When one turns up, it is a language release rather than a workaround.
