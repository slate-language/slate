// A module the language suite imports, so that the emitter's module wrapper is exercised on both
// back ends. It is under `lib/` because the harness walks the top of `tests/lang` only.

val factor = 3

export triple(x) = x * factor

export type Greeting = { to: string }

export greet(name) = "hello " + name

export val version = 2
