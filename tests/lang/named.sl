// Named arguments: `f(b: 1, a: 2)`, and what a name is allowed to pick out.
//
// **Which parameter a name fills is a question about the callee, and the callee is a value** -- so
// nothing here is settled while compiling. The names travel to the call and are placed against the
// parameters the function turned out to have, which is why both back ends have to agree about every
// one of these.

sub(a, b) = a - b

greet(name, greeting = "hello", punct = "!") = greeting + ", " + name + punct

gather(a, ...rest) = a

class Rect
    var w
    var h

    scale(self, by, add = 0) = self.w * by + add

data Shape
    Circle(r)
    Sized(w, h)

@test
a_name_says_which_parameter_an_argument_fills() =
    assertEq(sub(5, 1), 4)
    assertEq(sub(b: 1, a: 5), 4)
    assertEq(sub(a: 5, b: 1), 4)

@test
a_named_argument_may_follow_positional_ones() =
    assertEq(sub(5, b: 1), 4)

@test
a_SKIPPED_default_is_worked_out_by_the_callee_exactly_as_a_missing_one_is() =
    assertEq(greet("ada"), "hello, ada!")

    // **The hole is the whole of what named arguments buy here.** `punct:` is the third parameter
    // and `greeting:` was not given, so the call has to leave a gap in the middle -- which is the
    // one thing a positional call cannot express at all.
    assertEq(greet("ada", punct: "?"), "hello, ada?")
    assertEq(greet(punct: "?", name: "ada"), "hello, ada?")
    assertEq(greet(greeting: "hi", name: "ada"), "hi, ada!")

@test
a_class_and_a_data_variant_are_made_by_name_too() =
    // A class is made through its `new` and a variant through its own maker, so a name here picks
    // out a parameter of that -- which is where the field names are written.
    assertEq(string(Rect.new(h: 4, w: 3)), "Rect(w = 3, h = 4)")
    assertEq(string(Rect(h: 4, w: 3)), "Rect(w = 3, h = 4)")
    assertEq(string(Circle(r: 7)), "Circle(7)")
    assertEq(string(Sized(h: 2, w: 1)), "Sized(1, 2)")

@test
a_method_names_its_parameters_and_not_its_receiver() =
    val r = Rect.new(3, 4)

    assertEq(r.scale(by: 2), 6)
    assertEq(r.scale(add: 1, by: 2), 7)

@test
a_function_stored_on_an_object_is_named_the_same_way() =
    val o = { f: (a, b) -> a - b }

    assertEq(o.f(b: 1, a: 5), 4)

@test
a_name_no_parameter_answers_to_is_refused_and_the_message_lists_them() =
    val said = sub(a: 1, c: 2) catch e -> e.message

    assert(said.contains("no parameter called `c`"))
    assert(said.contains("`a` and `b`"))

@test
giving_one_parameter_twice_is_refused_however_it_was_written() =
    // Positionally and then by name fills the first slot from both directions, and letting the
    // later one win would make the argument that was written first do nothing.
    assert((sub(1, a: 2) catch e -> e.message).contains("gives `a` twice"))

@test
a_required_parameter_nobody_gave_is_named() =
    assert((greet(punct: "?") catch e -> e.message).contains("`name`"))

@test
a_BUILTIN_has_no_parameter_names_to_pick_out() =
    // Its arguments are a list and the names it is documented under are prose, so there is nothing
    // to look up. Saying so is better than matching against something that was never a parameter.
    assert((len(xs: [1]) catch e -> e.message).contains("builtin"))

@test
a_function_that_GATHERS_cannot_have_an_argument_named() =
    // A rest parameter is not a slot a name can pick out -- it is everything left over.
    assert((gather(a: 1) catch e -> e.message).contains("gathers"))
