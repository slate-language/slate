// A module: what it exports is what other files can see, and nothing else.

export val greeting = "hello"

export double(x) = x * 2

// No `export`, so no other file can reach this -- `main.sl` asking for it is a diagnostic.
secret() = "you cannot see me"

export shout(text) = s"${text}!"
