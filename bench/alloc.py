# The Python twin of alloc.sl.
#
# A dict rather than an object, matching fields.py's reasoning: slate's `{ x: i, y: i + 1 }` is a
# value keyed by names with nothing declared about them. CPython refcounts, so the dict here is freed
# on the line that drops it and the cyclic collector never sees it -- which is a different bargain
# from slate's tracing collector rather than a faster version of the same one.


def run():
    total = i = 0

    while i < 3000000:
        p = {"x": i, "y": i + 1}

        total = total + p["x"] + p["y"]
        i = i + 1

    return total


print(run())
