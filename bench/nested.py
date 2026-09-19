# The Python twin of nested.sl: loops.py's loop inside a function that also holds a closure over one
# of its names.


def run(pairs):
    total, turns = 0, 0
    scale = 1

    def weigh(v):
        return v * scale

    while turns < 6000:
        for a, b in pairs:
            total = total + weigh(a * b)

        turns = turns + 1

    return total


print(run([[i, i + 1] for i in range(1000)]))
