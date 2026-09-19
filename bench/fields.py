# The Python twin of fields.sl.
#
# A dict rather than an attribute on an object, because that is what slate's `{ a: 0 }` is: a value
# keyed by a name, with nothing declared about which names it has. An attribute lookup on a class
# with `__slots__` would be the faster Python and would not be the same thing.


def run():
    o = {"a": 0, "b": 1, "c": 2}
    i = 0

    while i < 5000000:
        o["a"] = o["a"] + o["b"] + o["c"]
        i = i + 1

    return o["a"]


print(run())
