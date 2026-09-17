---
title: Design
weight: 60
---

# Design

**These pages are designs for things slate has not got yet**, written before the work so that the
decisions are argued once and in one place. Nothing here describes the compiler as it stands today.

**Their programs are not run.** Every other page under `docs/` is executed by the test suite, which is
what makes it trustworthy; a design page shows syntax that does not compile yet, so its blocks carry no
language tag and the harness reads none of them. A page is rewritten as a
[reference](../reference/) page when the thing it describes is built, and the design page goes.

| | |
|---|---|
| [Actors](actors.md) | parallelism: one thread, one heap and one loop per actor, and messages that are copied |
