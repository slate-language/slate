# The Python twin of sorting.sl.
#
# `sorted` answers a new list, which is what slate's `sorted` does, so no copy has to be written out.
# The comparison is CPython's own on integers and never calls back into the program, which is slate's
# arrangement and not JavaScript's.


def build(n):
    xs, seed = [], 1

    for _ in range(n):
        seed = (seed * 16807) % 2147483647
        xs.append(seed)

    return xs


def run():
    xs = build(20000)
    total, turns = 0, 0

    while turns < 200:
        ys = sorted(xs)

        total = total + ys[0] + ys[19999]
        turns = turns + 1

    return total


print(run())
