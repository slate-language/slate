# The Python twin of methods.sl, written with a real `class`.
#
# No `__slots__`, so an instance keeps a `__dict__` and a field read is a dictionary lookup -- which
# is what a slate object's field read is. Adding `__slots__` would make this faster Python and a
# different measurement.


class Vec:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def dot(self, o):
        return self.x * o.x + self.y * o.y

    def scaled(self, k):
        return self.x * k + self.y * k


def run():
    a, b = Vec(2, 3), Vec(5, 7)
    total, i = 0, 0

    while i < 3000000:
        total = total + a.dot(b) + b.scaled(1)
        i = i + 1

    return total


print(run())
