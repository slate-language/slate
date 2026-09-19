# The Python twin of mapset.sl, using `dict` and `set`.
#
# Python's rule is hash-and-equality, which is slate's rule rather than JavaScript's -- a class that
# defines `__hash__` and `__eq__` is keyed by value here exactly as a slate class writing `hash` and
# `==` is. Every key in this program is a small integer, so nothing rests on that.


def run():
    m, s, i = {}, set(), 0

    while i < 2000000:
        m[i % 1000] = i
        s.add(i % 1000)
        i = i + 1

    total, k = 0, 0

    while k < 1000:
        total = total + m[k]

        if k in s:
            total = total + 1

        k = k + 1

    return total


print(run())
