{
    name: "toolbox",
    version: "1.0.0",
    main: "toolbox.sl",

    dependencies: {
        greet: { git: "github.com/example/greet", version: "1.0.0" },
    },

    // **A package's own dev dependency, naming something that is NOT in this cache.** That is the
    // point of the fixture: a consumer of `toolbox` must not resolve this, and if one ever did the
    // failure would be loud rather than a claim in a comment.
    devDependencies: {
        ghost: { git: "github.com/example/ghost", version: "9.9.9" },
    },
}
