// What a call's own frame holds: its parameters, and the fact that they are its and nobody else's.

@test
A_val_MAY_SHADOW_A_PARAMETER_AND_THE_PARAMETER_IS_GONE_FROM_THERE_ON()
    // **slate reads a parameter list and a body as two scopes and JavaScript reads them as one**, so
    // this is ordinary shadowing here and a `const` beside a parameter of the same name there -- a
    // SYNTAX error, which takes the whole emitted program with it rather than one function.
    shadowed(x) =
        val y = x + 1
        val x = y * 10

        x

    assertEq(shadowed(2), 30)
