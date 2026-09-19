# The Python twin of options.sl.
#
# A dict with `get` and a default is what Python writes where slate writes a pattern default -- there
# is no destructuring of a mapping in Python, so `**opts` into keyword parameters would be the other
# spelling and would build a second dict per call.


def sized(opts):
    width = opts.get("width", 10)
    height = opts["height"]
    scale = opts.get("scale", 2)

    return width * height * scale


def run(given, partial):
    total, turns = 0, 0

    while turns < 2000000:
        total = total + sized(given) + sized(partial)
        turns = turns + 1

    return total


print(run({"width": 3, "height": 4, "scale": 5}, {"height": 4}))
