# The Python twin of arith.sl. Python's integers are arbitrary precision, so this loop never wraps
# and never promotes -- which costs something at this size and would cost much more past 2^63.


def run():
    total = i = 0

    while i < 10000000:
        total = total + i * 2 - 1
        i = i + 1

    return total


print(run())
