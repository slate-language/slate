# The Python twin of funcs.sl. `add3` is looked up as a global once per call, which is a dictionary
# read CPython cannot avoid for a module-level function -- the closest Python gets to slate's call.


def add3(a, b, c):
    return a + b + c


def run():
    total = i = 0

    while i < 4000000:
        total = total + add3(i, 1, 2)
        i = i + 1

    return total


print(run())
