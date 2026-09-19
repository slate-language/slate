# The Python twin of strwalk.sl.
#
# **`s[i]` is a constant-time read of a CODE POINT**, which is the same unit slate indexes -- so of
# the three twins this is the one whose walk means exactly what the slate program's means.
#
# **It is constant time because CPython picks a fixed width per string** (PEP 393): a string holding
# any character above U+00FF is stored four bytes per code point, so this text costs four times its
# UTF-8 size in memory and an index is a multiplication. That is the trade slate does not make -- it
# keeps the UTF-8 and remembers where it last was.


def run(s):
    found, i = 0, 0

    while i < len(s):
        if s[i] == "本":
            found = found + 1

        i = i + 1

    return found


print(run("".join("日本語あいうえおかきく" + "さしすせそたちつてと" for _ in range(1000))))
