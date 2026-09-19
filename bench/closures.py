# The Python twin of closures.sl. `scale` is a free variable of the lambda, which CPython compiles
# to a cell read -- the same arrangement slate keeps a scope for.


def run():
    total, turns = 0, 0
    scale = 3

    def weigh(v):
        return v * scale

    while turns < 4000000:
        total = total + weigh(turns)
        turns = turns + 1

    return total


print(run())
