// A program is as many files as it imports, and each back end assembles them differently: the
// interpreter runs each module's chunk in a scope of its own, and `slate js` writes one function per
// file whose answer is its exports. An export that did not arrive is silent under both until
// something reads it — `$exports.fields.set` emptied EVERY built-in module for a release and
// surfaced three layers away.

import { triple, greet, version, Greeting } from "./lib/greet.sl"
import * as kit from "./lib/greet.sl"

@test
an_imported_definition_is_called_like_any_other() =
    assertEq(triple(5), 15)
    assertEq(greet("ada"), "hello ada")

@test
an_imported_value_is_the_snapshot_the_module_finished_with() =
    assertEq(version, 2)

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
