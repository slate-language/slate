// What a slate project says about itself.
//
// A manifest is data: it is parsed and never run, so everything here is a literal.
{
    name: "example",
    version: "0.1.0",

    main: "main.sl",

    dependencies: {
        parsing: { git: "github.com/sysl-lang/parsing", version: "0.4.0" },
        gc: { git: "github.com/sysl-lang/gc", version: "0.2.2" },
    },
}
