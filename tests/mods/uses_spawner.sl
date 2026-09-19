// An entry file whose imported module spawns at its own top level. Loading it for an actor is what
// the refusal is about.

import { child } from "./spawner.sl"

print("the importer ran")
