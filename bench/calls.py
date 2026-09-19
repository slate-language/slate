# The Python twin of calls.sl: a method call that allocates, once per iteration.
#
# No `__slots__`, for methods.py's reason -- a slate object's field is a keyed lookup and declaring
# the layout would be measuring something slate has no way to say.


class Counter:
    def __init__(self, n):
        self.n = n

    def bump(self, by):
        return Counter(self.n + by)


def run():
    c, i = Counter(0), 0

    while i < 2000000:
        c = c.bump(1)
        i = i + 1

    return c.n


print(run())
