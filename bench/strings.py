# The Python twin of strings.sl.
#
# **CPython MAY MAKE THIS LINEAR, and that is a property of the interpreter rather than of the
# language.** Where the string being extended has exactly one reference, `+=` resizes it in place
# instead of copying -- which is true of this loop -- so the same source text that is quadratic in
# slate and in Lua can be linear here. The idiomatic Python for building a big string is a list and
# one `join`, exactly as it is in Lua, and this file is deliberately the naive form for comparison.
#
# `len` counts code points, which is slate's unit.


def run():
    out, i = "", 0

    while i < 150000:
        out = out + "x" + str(i % 10)
        i = i + 1

    return len(out)


print(run())
