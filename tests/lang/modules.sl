// A program is as many files as it imports, and each back end assembles them differently: the
// interpreter runs each module's chunk in a scope of its own, and `slate js` writes one function per
// file whose answer is its exports. An export that did not arrive is silent under both until
// something reads it — `$exports.fields.set` emptied EVERY built-in module for a release and
// surfaced three layers away.

import { triple, greet, version, tally, bump, currentTally, Greeting } from "./lib/greet.sl"
import * as kit from "./lib/greet.sl"
import { breaks, breaksAfterParking } from "./lib/faulty.sl"

@test
an_imported_definition_is_called_like_any_other() =
    assertEq(triple(5), 15)
    assertEq(greet("ada"), "hello ada")

@test
an_imported_value_is_the_snapshot_the_module_finished_with() =
    assertEq(version, 2)

@test
an_imported_variable_is_the_snapshot_too_and_the_module_goes_on_writing_its_own() =
    // The module's own functions read the binding as it is now; what the importer bound is what the
    // file finished with, and a write afterwards does not reach either of the two names here.
    val had = currentTally()

    assertEq(bump(4), had + 4)
    assertEq(currentTally(), had + 4)
    assertEq(tally, 0)
    assertEq(kit.tally, 0)

@test
an_imported_type_is_a_pattern_and_a_value() =
    assert({ to: "ada" } is Greeting)
    assert(!({ to: 1 } is Greeting))
    assertEq(Greeting.name(), "Greeting")

@test
a_star_import_is_the_module_object() =
    assertEq(kit.triple(2), 6)
    assertEq(kit.version, 2)

@test
what_a_module_did_not_export_is_not_reachable_through_it() =
    assert(!has(kit, "factor"))

@test
a_fault_raised_in_an_imported_file_says_that_file_and_its_line() =
    val e = breaks(1) catch e -> e

    assert(contains(e.file, "lib/faulty.sl"))
    assertEq(e.line, 3)

@test
async a_fault_raised_after_an_await_in_an_imported_file_says_that_file_too() =
    // The coroutine parked in the other file and came back there, so the place is still that
    // file's — which is the half that is easy to lose, the machine being somewhere else by the
    // time anybody asks.
    val e = (await breaksAfterParking(1)) catch e -> e

    assert(contains(e.file, "lib/faulty.sl"))
    assertEq(e.line, 8)
