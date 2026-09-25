{
    name: "app",
    version: "0.1.0",
    main: "app.sl",

    // What `slate brew` writes into the formula, and nothing else reads.
    description: "Two packages, one of which imports the other",
    homepage: "https://github.com/example/app",
    license: "ISC",

    dependencies: {
        greet: { git: "github.com/example/greet", version: "1.0.0" },
        loud: { git: "github.com/example/loud", version: "1.0.0" },
    },
}
