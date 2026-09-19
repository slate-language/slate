# The Python twin of strindex.sl.
#
# **`s[i]` is a constant-time read**, so this walk is linear where slate's is quadratic. CPython
# indexes CODE POINTS, which is the same unit slate indexes -- of the three twins this is the one
# whose `s[i]` means exactly what slate's means, and it is still constant time, because a Python
# string of all-ASCII text is stored one byte per code point.


def run(s):
    found, i = 0, 0

    while i < len(s):
        if s[i] == "x":
            found = found + 1

        i = i + 1

    return found


print(run("".join("abcdexfghi" + "jklmnxopqr" for _ in range(1000))))
