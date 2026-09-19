# The Python twin of reals.sl. A Python float is a double and `i * 1.5` promotes the integer, so the
# arithmetic is the same sequence of operations on the same values.


def run():
    total, i = 0.0, 0

    while i < 10000000:
        total = total + i * 1.5 - 0.5
        i = i + 1

    return total


print(f"{run():.1f}")
