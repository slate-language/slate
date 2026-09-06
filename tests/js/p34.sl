// `host()` -- which of the three hosts a program is running on, and the branch it exists to write.
//
// **This corpus runs one program on both back ends and diffs what it prints**, so `host()` itself
// cannot be printed here: it answers `"interpreter"` on one side and `"node"` on the other, by
// design, and a differential test would fail on the one thing working as documented. What CAN be
// pinned is a program that BRANCHES on it and prints the same thing regardless -- which is the
// actual shape `docs/library/dom.md`'s cookie guard is: a shared file with no control over where it
// runs, asking once and taking one of two paths that happen to answer alike here.

if host() == "interpreter" || host() == "node" || host() == "browser"
    print("a known host")
else
    print("an unknown host")

// A shared component's real shape: one call guarded by the one host that cannot make it.
setting(name) =
    if host() == "browser" then "read from the page"
    else "read from the environment"

print(setting("theme"))

// Constant for the life of a program -- asking twice never disagrees, on either back end.
print(host() == host())
