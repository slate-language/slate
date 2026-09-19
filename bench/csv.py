# The Python twin of csv.sl.
#
# `str.split` and `int` are the builtins, and `len` counts code points -- the same unit slate counts.
# The standard library's `csv` module would be the idiomatic reader for a real file and would not be
# the same work: it handles quoting and would be measuring a different program.


def build(rows):
    return "\n".join(f"{i},{i * 2},name{i % 100}" for i in range(rows))


def parse(text):
    total = 0

    for line in text.split("\n"):
        parts = line.split(",")

        total = total + int(parts[0]) + int(parts[1]) + len(parts[2])

    return total


def run():
    text = build(20000)
    total, turns = 0, 0

    while turns < 30:
        total = total + parse(text)
        turns = turns + 1

    return total


print(run())
