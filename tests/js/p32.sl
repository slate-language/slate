// A default parameter that reads `await`, on both back ends.
//
// **`slate js` used to emit this straight into the parameter list**, where node refuses it outright
// -- `SyntaxError: Illegal await-expression in formal parameters` -- raised while the file is parsed
// and before a line of the program runs, even though the interpreter has always allowed it. The
// default is now a guarded assignment at the top of the body instead, which is legal wherever
// `await` is legal and answers the same value either way.

async withDefault(x = await 5)
    x

async main()
    print(await withDefault())
    print(await withDefault(9))

    // The default runs at the CALL, exactly as any other default does, so two calls that leave it
    // out each get their own turn through it rather than sharing one answer.
    print(await withDefault(), await withDefault())

main()
