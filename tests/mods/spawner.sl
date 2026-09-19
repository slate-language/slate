// A module that spawns an actor at its own top level, which is the one thing a VM being loaded for an
// actor refuses: that actor's VM would run this file, which would spawn again, without end.

import { spawn } from slate:actor

export actor Echo
    on ping(self) = 1

export val child = spawn(Echo)
