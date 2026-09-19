# The Python twin of arrays.sl. `append` is the push and `for v in xs` is the walk.


def build(n):
    xs = []
    i = 0

    while i < n:
        xs.append(i * 2)
        i = i + 1

    return xs


def by_index(xs):
    total, i = 0, 0

    while i < len(xs):
        total = total + xs[i]
        i = i + 1

    return total


def by_walk(xs):
    total = 0

    for v in xs:
        total = total + v

    return total


def run():
    xs = build(500000)
    total, turns = 0, 0

    while turns < 10:
        total = total + by_index(xs) + by_walk(xs)
        turns = turns + 1

    return total


print(run())
