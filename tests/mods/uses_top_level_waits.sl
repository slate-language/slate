// The importer, which may not run until the module it imports has finished waiting.

import { ready } from "./waits_lib.sl"

print("the importer ran", ready)
