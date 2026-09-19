# The Python twin of loops.sl. `for a, b in pairs` unpacks in the loop head, which is what slate's
# `for [a, b] in pairs` does.


def run(pairs):
    total, turns = 0, 0

    while turns < 8000:
        for a, b in pairs:
            total = total + a * b

        turns = turns + 1

    return total


print(run([[i, i + 1] for i in range(1000)]))
